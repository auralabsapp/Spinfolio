import Foundation
import CloudKit
import Observation
import OSLog
import UIKit

private let cloudSyncLogger = Logger(subsystem: "com.auralabs.Spinlog", category: "CloudSyncEngine")

/// Identifie, à partir du `recordName` d'un `CKRecord`, à quel store local un enregistrement
/// synchronisé correspond. Chaque genre a son propre `recordType` CloudKit et sa propre
/// convention de nommage, mais partage le même champ `payload` (JSON) et la même zone par compte
/// (`account-<username>`), gérés génériquement par `CloudSyncEngine`.
private enum SyncedRecordKind: Equatable {
    /// Un exemplaire de la collection et ses tags (voir `TagStore`).
    case tag(instanceId: Int)
    /// Une session d'écoute individuelle (voir `ListeningLogStore`) : contrairement aux autres
    /// genres, chaque session est son propre `CKRecord` et peut être supprimée individuellement.
    case listeningSession(id: UUID)
    /// Préférences "durables" de la collection (voir `CollectionPreferencesStore`) : un seul
    /// enregistrement singleton par compte.
    case collectionPreferences
    /// Personnalisations de tri des artistes (voir `ShelfPreferencesStore`) : un seul
    /// enregistrement singleton par compte.
    case shelfPreferences

    private static let tagPrefix = "tags_"
    private static let sessionPrefix = "session_"
    private static let collectionPreferencesRecordName = "preferences"
    private static let shelfPreferencesRecordName = "shelfOverrides"

    var recordName: String {
        switch self {
        case .tag(let instanceId): return "\(Self.tagPrefix)\(instanceId)"
        case .listeningSession(let id): return "\(Self.sessionPrefix)\(id.uuidString)"
        case .collectionPreferences: return Self.collectionPreferencesRecordName
        case .shelfPreferences: return Self.shelfPreferencesRecordName
        }
    }

    var recordType: String {
        switch self {
        case .tag: return "TagAssignment"
        case .listeningSession: return "ListeningSession"
        case .collectionPreferences: return "CollectionPreferences"
        case .shelfPreferences: return "ShelfPreferences"
        }
    }

    static func from(recordName: String) -> SyncedRecordKind? {
        if recordName.hasPrefix(tagPrefix), let instanceId = Int(recordName.dropFirst(tagPrefix.count)) {
            return .tag(instanceId: instanceId)
        }
        if recordName.hasPrefix(sessionPrefix),
           let id = UUID(uuidString: String(recordName.dropFirst(sessionPrefix.count))) {
            return .listeningSession(id: id)
        }
        if recordName == collectionPreferencesRecordName { return .collectionPreferences }
        if recordName == shelfPreferencesRecordName { return .shelfPreferences }
        return nil
    }
}

/// Instantané synchronisable des préférences de collection "durables" (voir
/// `CollectionPreferencesStore`) : uniquement celles qui ont du sens à retrouver identiques sur
/// tous les appareils (devise, champs de suivi de cote, dossier d'ajout par défaut) — pas le
/// tri/filtre actif ni le dernier dossier consulté, qui restent volontairement propres à chaque
/// appareil.
private struct SyncedCollectionPreferences: Codable, Sendable {
    let defaultCurrency: String
    let purchasePriceFieldId: Int?
    let mediaConditionFieldId: Int?
    let defaultAddFolderId: Int
}

/// Synchronise les tags, le journal d'écoute et certaines préférences via iCloud (base privée
/// CloudKit) entre les appareils d'un même compte premium. Une zone `CKRecordZone` dédiée par
/// compte Discogs (`account-<username>`) isole les données de chaque compte à l'intérieur d'une
/// seule base privée, comme `TagStore` le fait déjà localement avec ses clés `UserDefaults`
/// préfixées par compte.
///
/// Entièrement gaté par `PremiumStore.shared.isPremium` : côté non-premium, aucun appel réseau
/// n'est fait et aucune donnée ne quitte l'appareil. En cas de désabonnement, les zones et
/// enregistrements déjà présents sur iCloud ne sont jamais supprimés — seul le push/pull depuis
/// cet appareil s'arrête, pour permettre une reprise sans perte en cas de réabonnement.
@Observable
@MainActor
final class CloudSyncEngine {
    static let shared = CloudSyncEngine()

    private var syncEngine: CKSyncEngine?
    private(set) var activeUsername: String?
    /// Coalesce plusieurs signalements rapprochés (ex: la poussée initiale de nombreux exemplaires
    /// tagués) en un seul envoi réseau, plutôt que de lancer un `sendChanges()` concurrent par
    /// appel — inutile et potentiellement instable sur le même moteur.
    private var pendingSendTask: Task<Void, Never>?
    /// `true` uniquement pendant le tout premier `fetchChanges()` réussi pour le compte actif sur
    /// cet appareil — voir `apply(remoteRecord:allowMerge:)`.
    private var isFirstHydrateForActiveAccount = false

    private let container = CKContainer.default()
    private static let stateStorageKey = "com.spinlog.cloudSyncEngineState"
    private static let payloadField = "payload"
    private static let hydratedFlagKeyPrefix = "com.spinlog.cloudSync.hydrated_"
    private static let initialPushDoneKeyPrefix = "com.spinlog.cloudSync.initialPushDone_"

    private init() {
        NotificationCenter.default.addObserver(
            forName: .premiumStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.premiumStatusChanged()
            }
        }
        // Sans ce déclencheur, un appareil déjà lancé (pas relancé) ne rattraperait jamais les
        // modifications faites sur un autre appareil pendant qu'il était en arrière-plan — la
        // synchro automatique de CKSyncEngine est documentée comme "indéterminée" (dépend des
        // conditions système), donc pas fiable pour un retour au premier plan.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                cloudSyncLogger.log("didBecomeActiveNotification — fetchLatestChanges()")
                self.fetchLatestChanges()
            }
        }

        if PremiumStore.shared.isPremium {
            start()
        }
    }

    private func premiumStatusChanged() {
        if PremiumStore.shared.isPremium {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard syncEngine == nil else { return }
        cloudSyncLogger.log("start() — activeUsername=\(self.activeUsername ?? "nil", privacy: .public)")
        var stateSerialization: CKSyncEngine.State.Serialization?
        if let data = UserDefaults.standard.data(forKey: Self.stateStorageKey) {
            do {
                stateSerialization = try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
            } catch {
                cloudSyncLogger.error("Échec décodage de l'état persisté du moteur : \(error, privacy: .public)")
            }
        }
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: stateSerialization,
            delegate: self
        )
        syncEngine = CKSyncEngine(configuration)

        container.accountStatus { status, error in
            if let error {
                cloudSyncLogger.error("accountStatus() a échoué : \(error, privacy: .public)")
            } else {
                cloudSyncLogger.log("accountStatus() = \(status.rawValue, privacy: .public)")
            }
        }

        if activeUsername != nil {
            hydrateActiveZone()
        }
    }

    private func stop() {
        cloudSyncLogger.log("stop()")
        syncEngine = nil
    }

    /// Bascule ce moteur sur le compte Discogs indiqué. Ne recrée jamais le moteur lui-même (une
    /// seule base privée pour tout le compte iCloud, avec une zone par compte Discogs à
    /// l'intérieur) : rapatrie simplement tout ce que la zone de ce compte contient déjà côté
    /// iCloud et le fusionne dans les stores locaux. Appelé par `DiscogsAuthManager` aux mêmes
    /// points que `TagStore.setActiveUsername`/`ListeningLogStore.setActiveUsername`.
    func setActiveUsername(_ username: String?) {
        let normalized = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cloudSyncLogger.log("setActiveUsername(\(username ?? "nil", privacy: .public)) — était \(self.activeUsername ?? "nil", privacy: .public), syncEngine \(self.syncEngine == nil ? "absent" : "présent", privacy: .public)")
        guard normalized != activeUsername else { return }
        activeUsername = normalized
        guard normalized != nil else { return }
        hydrateActiveZone()
    }

    private func zoneID(for username: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "account-\(username)", ownerName: CKCurrentUserDefaultName)
    }

    private func ensureZoneExists(for username: String) {
        guard let syncEngine else { return }
        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID(for: username)))])
    }

    // MARK: - Envoi (push)

    private func markDirty(_ kind: SyncedRecordKind) {
        guard let syncEngine, let activeUsername else {
            cloudSyncLogger.log("markDirty(\(String(describing: kind), privacy: .public)) ignoré — syncEngine=\(self.syncEngine == nil ? "nil" : "ok", privacy: .public) activeUsername=\(self.activeUsername ?? "nil", privacy: .public)")
            return
        }
        ensureZoneExists(for: activeUsername)
        let recordID = CKRecord.ID(recordName: kind.recordName, zoneID: zoneID(for: activeUsername))
        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        cloudSyncLogger.log("markDirty(\(String(describing: kind), privacy: .public)) — envoi vers zone \(recordID.zoneID.zoneName, privacy: .public)")
        // La planification automatique du moteur est documentée comme "indéterminée" (dépend des
        // conditions système). On force un envoi pour que le changement apparaisse sur les autres
        // appareils sans attendre un cycle de synchronisation en arrière-plan.
        scheduleSend()
    }

    private func markDeleted(_ kind: SyncedRecordKind) {
        guard let syncEngine, let activeUsername else {
            cloudSyncLogger.log("markDeleted(\(String(describing: kind), privacy: .public)) ignoré — syncEngine=\(self.syncEngine == nil ? "nil" : "ok", privacy: .public) activeUsername=\(self.activeUsername ?? "nil", privacy: .public)")
            return
        }
        let recordID = CKRecord.ID(recordName: kind.recordName, zoneID: zoneID(for: activeUsername))
        syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        cloudSyncLogger.log("markDeleted(\(String(describing: kind), privacy: .public)) — suppression vers zone \(recordID.zoneID.zoneName, privacy: .public)")
        scheduleSend()
    }

    /// Signale qu'un exemplaire a des tags à envoyer vers iCloud. No-op silencieux si le moteur
    /// n'est pas actif (non premium) ou si aucun compte n'est actif.
    func markTagsDirty(instanceId: Int) {
        markDirty(.tag(instanceId: instanceId))
    }

    /// Signale qu'une session d'écoute a été créée/modifiée et doit être envoyée vers iCloud.
    func markSessionDirty(id: UUID) {
        markDirty(.listeningSession(id: id))
    }

    /// Signale qu'une session d'écoute a été supprimée localement et doit l'être aussi sur iCloud.
    func markSessionDeleted(id: UUID) {
        markDeleted(.listeningSession(id: id))
    }

    /// Signale que les préférences de collection "durables" ont changé (voir
    /// `SyncedCollectionPreferences`).
    func markCollectionPreferencesDirty() {
        markDirty(.collectionPreferences)
    }

    /// Signale que les personnalisations de tri des artistes ont changé.
    func markShelfPreferencesDirty() {
        markDirty(.shelfPreferences)
    }

    /// Regroupe plusieurs signalements rapprochés en un seul envoi : CKSyncEngine ne doit pas
    /// recevoir plusieurs appels concurrents à `sendChanges()`, et ce serait de toute façon
    /// redondant (un seul envoi couvre déjà tous les changements en attente).
    private func scheduleSend() {
        guard pendingSendTask == nil, let syncEngine else { return }
        pendingSendTask = Task {
            do {
                try await syncEngine.sendChanges()
                cloudSyncLogger.log("sendChanges() terminé")
            } catch {
                cloudSyncLogger.error("sendChanges() a échoué : \(error, privacy: .public)")
            }
            pendingSendTask = nil
            // Si de nouveaux changements sont arrivés pendant l'envoi (y compris ceux remis en
            // attente après un conflit détecté dans `handleEvent`), on relance un envoi pour eux.
            if !syncEngine.state.pendingRecordZoneChanges.isEmpty {
                scheduleSend()
            }
        }
    }

    // MARK: - Rapatriement (première synchro / changement de compte actif)

    /// Déclenche une récupération complète des changements côté iCloud. Découvre au passage les
    /// zones que cet appareil n'a jamais vues (ex: compte déjà utilisé sur un autre appareil) —
    /// les enregistrements reçus sont filtrés à la zone active dans `apply(remoteRecord:)`.
    private func hydrateActiveZone() {
        guard let activeUsername else {
            cloudSyncLogger.log("hydrateActiveZone() ignoré — activeUsername=nil")
            return
        }
        cloudSyncLogger.log("hydrateActiveZone() pour \(activeUsername, privacy: .public)")

        // Poussée initiale : les données déjà créées localement avant que la synchro ne soit
        // active (ou avant l'ajout d'un genre synchronisé) n'ont jamais déclenché de `markDirty`
        // — on les envoie donc explicitement, mais UNE SEULE FOIS par compte sur cet appareil
        // (clé dédiée, distincte de celle de `fetchLatestChanges`). Sans cette garde, repousser
        // des dizaines d'exemplaires à chaque lancement/retour au premier plan sature le quota de
        // l'environnement CloudKit (observé : rafale de `CKError.serviceUnavailable` qui bloque
        // aussi les vraies modifications en attente).
        let pushDoneKey = Self.initialPushDoneKeyPrefix + activeUsername
        if !UserDefaults.standard.bool(forKey: pushDoneKey) {
            let existingInstanceIds = TagStore.shared.allTaggedInstanceIds()
            let existingSessionIds = ListeningLogStore.shared.allSessionIds()
            cloudSyncLogger.log("Poussée initiale (première synchro) de \(existingInstanceIds.count) exemplaire(s) tagué(s) et \(existingSessionIds.count) session(s) d'écoute enregistrées localement")
            for instanceId in existingInstanceIds {
                markTagsDirty(instanceId: instanceId)
            }
            for sessionId in existingSessionIds {
                markSessionDirty(id: sessionId)
            }
            markCollectionPreferencesDirty()
            markShelfPreferencesDirty()
            // Marqué tout de suite, sans attendre la confirmation réseau : les changements sont
            // déjà enregistrés dans l'état persisté du moteur (`state.add` dans `markDirty`), qui
            // les redélivrera lui-même même si cet envoi immédiat échoue (ex: throttling).
            // Attendre le succès avant de marquer redéclencherait la même rafale à chaque
            // lancement tant que l'erreur passagère persiste.
            UserDefaults.standard.set(true, forKey: pushDoneKey)
        }

        fetchLatestChanges()
    }

    /// Récupère les derniers changements côté iCloud, sans attendre la fin (fire-and-forget) —
    /// adapté aux déclencheurs premier plan (`hydrateActiveZone`, retour au premier plan), où
    /// personne n'a besoin d'attendre le résultat.
    private func fetchLatestChanges() {
        Task {
            await performFetchChanges()
        }
    }

    /// Appelé par `AppDelegate` à la réception d'une notification silencieuse CloudKit, pour que
    /// la récupération se fasse pendant la fenêtre d'exécution en arrière-plan accordée par l'OS.
    /// Contrairement à `fetchLatestChanges()`, celui-ci attend réellement la fin de l'opération :
    /// si on rendait la main avant que `fetchChanges()` ait fini, l'OS pourrait suspendre l'app
    /// avant que la modification distante n'ait été récupérée.
    @discardableResult
    func handleRemoteNotification() async -> Bool {
        cloudSyncLogger.log("handleRemoteNotification() — réveil par notification silencieuse CloudKit")
        return await performFetchChanges()
    }

    /// Cœur partagé de la récupération, utilisé à la fois en fire-and-forget
    /// (`fetchLatestChanges`) et en `await` direct (`handleRemoteNotification`).
    @discardableResult
    private func performFetchChanges() async -> Bool {
        guard let syncEngine, let activeUsername else {
            cloudSyncLogger.log("performFetchChanges() ignoré — syncEngine=\(self.syncEngine == nil ? "nil" : "ok", privacy: .public) activeUsername=\(self.activeUsername ?? "nil", privacy: .public)")
            return false
        }

        // Seul le tout premier `fetchChanges()` réussi pour ce compte sur cet appareil doit
        // fusionner (union) l'état distant avec le local — voir `apply(remoteRecord:allowMerge:)`
        // pour le détail par genre d'enregistrement. Une fois cette réconciliation faite, tout
        // changement distant reçu doit être appliqué tel quel, sinon une suppression faite sur un
        // autre appareil serait systématiquement "ressuscitée" par l'union avec l'état local.
        let hydratedKey = Self.hydratedFlagKeyPrefix + activeUsername
        let isFirstHydrate = !UserDefaults.standard.bool(forKey: hydratedKey)
        isFirstHydrateForActiveAccount = isFirstHydrate
        cloudSyncLogger.log("performFetchChanges() — première synchro pour ce compte sur cet appareil : \(isFirstHydrate)")

        defer { isFirstHydrateForActiveAccount = false }
        do {
            try await syncEngine.fetchChanges()
            cloudSyncLogger.log("fetchChanges() terminé pour \(activeUsername, privacy: .public)")
            if isFirstHydrate {
                UserDefaults.standard.set(true, forKey: hydratedKey)
            }
            return true
        } catch {
            cloudSyncLogger.error("fetchChanges() a échoué pour \(activeUsername, privacy: .public) : \(error, privacy: .public)")
            return false
        }
    }

    /// Applique un enregistrement reçu d'iCloud, quel que soit son genre.
    /// - `allowMerge: true` fusionne (union) avec l'état local — réservé à la réconciliation
    ///   initiale de deux appareils divergents (voir `isFirstHydrateForActiveAccount`). Uniquement
    ///   pertinent pour les genres qui représentent une collection pouvant légitimement diverger
    ///   (tags, personnalisations de tri) ; les sessions d'écoute et préférences n'ont pas besoin
    ///   de fusion (identifiées individuellement ou simples scalaires).
    /// - `allowMerge: false` (cas normal, `fetchedRecordZoneChanges`) remplace directement l'état
    ///   local par le contenu distant : c'est ce qui permet à une suppression faite sur un autre
    ///   appareil de se propager correctement, plutôt que d'être ré-ajoutée par une union.
    private func apply(remoteRecord record: CKRecord, allowMerge: Bool) {
        guard let activeUsername else {
            cloudSyncLogger.log("apply(remoteRecord:) ignoré — aucun compte actif")
            return
        }
        guard record.recordID.zoneID == zoneID(for: activeUsername) else {
            cloudSyncLogger.log("apply(remoteRecord:) ignoré — zone \(record.recordID.zoneID.zoneName, privacy: .public) différente de la zone active")
            return
        }
        guard let kind = SyncedRecordKind.from(recordName: record.recordID.recordName) else {
            cloudSyncLogger.log("apply(remoteRecord:) ignoré — recordName inattendu \(record.recordID.recordName, privacy: .public)")
            return
        }
        guard let payload = record[Self.payloadField] as? Data else {
            cloudSyncLogger.error("apply(remoteRecord:) — payload absent pour \(String(describing: kind), privacy: .public)")
            return
        }

        switch kind {
        case .tag(let instanceId):
            guard let remoteTags = try? JSONDecoder().decode([SyncedTag].self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour instance \(instanceId)")
                return
            }
            let resolved: [SyncedTag]
            if allowMerge {
                resolved = TagMergeLogic.merge(local: TagStore.shared.syncSnapshot(for: instanceId), remote: remoteTags)
            } else {
                resolved = remoteTags
            }
            cloudSyncLogger.log("apply(remoteRecord:) tag instance \(instanceId) — remote=\(remoteTags.count) allowMerge=\(allowMerge) résultat=\(resolved.count)")
            TagStore.shared.applyRemoteTags(instanceId: instanceId, tags: resolved)

        case .listeningSession:
            guard let session = try? JSONDecoder().decode(ListeningSession.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour une session d'écoute")
                return
            }
            cloudSyncLogger.log("apply(remoteRecord:) session d'écoute \(session.id, privacy: .public)")
            ListeningLogStore.shared.applyRemoteSession(session)

        case .collectionPreferences:
            guard let prefs = try? JSONDecoder().decode(SyncedCollectionPreferences.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les préférences de collection")
                return
            }
            cloudSyncLogger.log("apply(remoteRecord:) préférences de collection")
            CollectionPreferencesStore.applyRemotePreferences(
                currency: prefs.defaultCurrency,
                purchasePriceFieldId: prefs.purchasePriceFieldId,
                mediaConditionFieldId: prefs.mediaConditionFieldId,
                defaultAddFolderId: prefs.defaultAddFolderId,
                for: activeUsername
            )

        case .shelfPreferences:
            guard let remoteOverrides = try? JSONDecoder().decode([String: String].self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les personnalisations de tri")
                return
            }
            let resolved: [String: String]
            if allowMerge {
                // Union simple : conserve la personnalisation locale en cas de conflit sur un même
                // artiste (rare), ajoute les entrées distantes absentes localement. Un simple
                // remplacement ferait perdre les personnalisations de l'appareil qui n'a pas
                // encore poussé les siennes lors de cette toute première synchro.
                resolved = remoteOverrides.merging(ShelfPreferencesStore.shared.customArtistSortOverrides) { _, local in local }
            } else {
                resolved = remoteOverrides
            }
            cloudSyncLogger.log("apply(remoteRecord:) personnalisations de tri — remote=\(remoteOverrides.count) allowMerge=\(allowMerge) résultat=\(resolved.count)")
            ShelfPreferencesStore.shared.applyRemoteCustomArtistSortOverrides(resolved)
        }
    }

    /// Applique une suppression reçue d'iCloud. Seules les sessions d'écoute sont supprimées en
    /// tant que `CKRecord` (les tags et préférences ne sont eux jamais supprimés, uniquement
    /// remplacés par un contenu vide/par défaut) — tout autre genre est ignoré silencieusement.
    private func applyDeletion(recordID: CKRecord.ID) {
        guard let activeUsername, recordID.zoneID == zoneID(for: activeUsername) else { return }
        guard case .listeningSession(let id) = SyncedRecordKind.from(recordName: recordID.recordName) else { return }
        cloudSyncLogger.log("applyDeletion(recordID:) session d'écoute \(id, privacy: .public)")
        ListeningLogStore.shared.applyRemoteSessionDeletion(id: id)
    }

    /// Construit le contenu (payload JSON) à envoyer pour un genre d'enregistrement donné, à
    /// partir de l'état local actuel — jamais fusionné avec le contenu serveur (voir
    /// `nextRecordZoneChangeBatch`).
    private func payloadData(for kind: SyncedRecordKind) -> Data? {
        switch kind {
        case .tag(let instanceId):
            return try? JSONEncoder().encode(TagStore.shared.syncSnapshot(for: instanceId))

        case .listeningSession(let id):
            guard let session = ListeningLogStore.shared.session(id: id) else { return nil }
            return try? JSONEncoder().encode(session)

        case .collectionPreferences:
            guard let activeUsername else { return nil }
            let prefs = SyncedCollectionPreferences(
                defaultCurrency: CollectionPreferencesStore.defaultCurrency(for: activeUsername),
                purchasePriceFieldId: CollectionPreferencesStore.purchasePriceFieldId(for: activeUsername),
                mediaConditionFieldId: CollectionPreferencesStore.mediaConditionFieldId(for: activeUsername),
                defaultAddFolderId: CollectionPreferencesStore.defaultAddFolderId(for: activeUsername)
            )
            return try? JSONEncoder().encode(prefs)

        case .shelfPreferences:
            return try? JSONEncoder().encode(ShelfPreferencesStore.shared.customArtistSortOverrides)
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncEngine: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        cloudSyncLogger.log("handleEvent: \(String(describing: event), privacy: .public)")
        switch event {
        case .stateUpdate(let stateUpdate):
            if let data = try? JSONEncoder().encode(stateUpdate.stateSerialization) {
                UserDefaults.standard.set(data, forKey: Self.stateStorageKey)
            }

        case .accountChange(let accountChange):
            // Compte iCloud déconnecté/changé sur l'appareil : on repart de zéro comme si le
            // statut premium venait d'être désactivé. L'appareil retombe sur ses données locales.
            cloudSyncLogger.error("accountChange: \(String(describing: accountChange), privacy: .public)")
            stop()

        case .fetchedRecordZoneChanges(let fetchedChanges):
            cloudSyncLogger.log("fetchedRecordZoneChanges — \(fetchedChanges.modifications.count) modification(s), \(fetchedChanges.deletions.count) suppression(s)")
            for modification in fetchedChanges.modifications {
                apply(remoteRecord: modification.record, allowMerge: isFirstHydrateForActiveAccount)
            }
            for deletion in fetchedChanges.deletions {
                applyDeletion(recordID: deletion.recordID)
            }

        case .sentRecordZoneChanges(let sentChanges):
            cloudSyncLogger.log("sentRecordZoneChanges — \(sentChanges.savedRecords.count) sauvé(s), \(sentChanges.deletedRecordIDs.count) supprimé(s), \(sentChanges.failedRecordSaves.count) échec(s) de sauvegarde, \(sentChanges.failedRecordDeletes.count) échec(s) de suppression")
            for failedSave in sentChanges.failedRecordSaves {
                cloudSyncLogger.error("failedRecordSave \(failedSave.record.recordID.recordName, privacy: .public) : \(String(describing: failedSave.error), privacy: .public)")
                // Pas besoin de logique de résolution ici : `nextRecordZoneChangeBatch` repart
                // toujours de la version serveur actuelle (voir plus bas), donc il suffit de
                // remettre le changement en attente pour qu'il soit retenté avec les bonnes
                // métadonnées.
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failedSave.record.recordID)])
            }
            for (recordID, error) in sentChanges.failedRecordDeletes {
                cloudSyncLogger.error("failedRecordDelete \(recordID.recordName, privacy: .public) : \(String(describing: error), privacy: .public)")
                syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // Un seul enregistrement par lot, volontairement : CloudKit envoie chaque lot comme UNE
        // opération réseau atomique par zone — si on regroupait plusieurs disques dans le même
        // lot, un conflit sur l'un d'eux (backlog en retard, ou modification concurrente sur un
        // autre appareil) ferait échouer TOUS les disques du même lot, même sans rapport entre
        // eux (observé : "problème de synchro même sur un disque différent" quand les deux
        // appareils sont ouverts en même temps). CKSyncEngine rappelle cette méthode autant de
        // fois que nécessaire tant qu'un lot non-nil est renvoyé, donc renvoyer un seul
        // changement à la fois n'empêche pas les autres d'être traités, juste dans des
        // opérations séparées et isolées les unes des autres.
        guard let change = syncEngine.state.pendingRecordZoneChanges.first else { return nil }

        guard case .saveRecord(let recordID) = change else {
            // `.deleteRecord` : CKSyncEngine gère la suppression sans consulter ce bloc — il
            // suffit de lui transmettre le changement tel quel.
            return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: [change]) { _ in nil }
        }

        guard let kind = SyncedRecordKind.from(recordName: recordID.recordName),
              let payload = payloadData(for: kind) else {
            return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: [change]) { _ in nil }
        }

        // Repart toujours de la version serveur actuelle (jamais d'un cache local qui pourrait
        // être périmé), mais UNIQUEMENT pour ses métadonnées système (identité/version) — jamais
        // pour fusionner son contenu. Fusionner (union) le contenu serveur avec l'état local ici
        // referait exactement le bug déjà corrigé côté réception : si l'utilisateur vient de
        // retirer un tag localement, le serveur a encore l'ancienne liste (le retrait n'a pas
        // encore été poussé) — une union des deux ferait "ressusciter" le tag qu'on vient de
        // retirer. Le contenu envoyé est donc toujours l'état local actuel tel quel.
        let record: CKRecord
        if let serverRecord = try? await syncEngine.database.record(for: recordID) {
            record = serverRecord
        } else {
            record = CKRecord(recordType: kind.recordType, recordID: recordID)
        }
        record[Self.payloadField] = payload as CKRecordValue

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: [change]) { _ in record }
    }
}
