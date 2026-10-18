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
private nonisolated enum SyncedRecordKind: Equatable {
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
    /// Point d'historique de la valeur globale de la collection pour un jour donné (voir
    /// `CollectionSnapshot`/`LocalDataStore`) : un enregistrement par jour, jamais supprimé.
    case collectionSnapshot(dayStamp: String)
    /// Une alerte de prix wantlist (voir `WantlistAlertStore`) : un enregistrement par release,
    /// qui peut être supprimé individuellement (comme les sessions d'écoute).
    case wantlistAlert(releaseId: Int)
    /// La bibliothèque de tags "autonomes" (créés sans être encore appliqués à un exemplaire —
    /// voir `TagStore.standaloneTags`) : un seul enregistrement singleton par compte.
    case standaloneTags
    /// Sections (Albums, Singles & EP…) des masters Discogs déjà classés (voir
    /// `DiscogsWorkCategoryCache`) : un seul enregistrement singleton par compte. Partagé pour
    /// qu'un classement fait sur un appareil (une requête par master) serve aux autres.
    case discogsWorkCategories
    /// Thème de couleur (`ThemeManager`), apparence clair/sombre/système et durée maximale de la
    /// Live Activity d'écoute (`AppearancePreferencesStore`) : un seul enregistrement singleton
    /// par compte. Contrairement à la connexion Apple Music (device-wide, jamais synchronisée et
    /// réinitialisée à la déconnexion — voir `DiscogsAuthManager.logout()`), ces réglages sont
    /// propres au compte Discogs et doivent se retrouver à la reconnexion ou sur un autre appareil.
    case appPreferences

    private static let tagPrefix = "tags_"
    private static let sessionPrefix = "session_"
    private static let collectionPreferencesRecordName = "preferences"
    private static let shelfPreferencesRecordName = "shelfOverrides"
    private static let snapshotPrefix = "snapshot_"
    private static let wantlistAlertPrefix = "alert_"
    private static let standaloneTagsRecordName = "standaloneTags"
    private static let discogsWorkCategoriesRecordName = "discogsWorkCategories"
    private static let appPreferencesRecordName = "appPreferences"

    var recordName: String {
        switch self {
        case .tag(let instanceId): return "\(Self.tagPrefix)\(instanceId)"
        case .listeningSession(let id): return "\(Self.sessionPrefix)\(id.uuidString)"
        case .collectionPreferences: return Self.collectionPreferencesRecordName
        case .shelfPreferences: return Self.shelfPreferencesRecordName
        case .collectionSnapshot(let dayStamp): return "\(Self.snapshotPrefix)\(dayStamp)"
        case .wantlistAlert(let releaseId): return "\(Self.wantlistAlertPrefix)\(releaseId)"
        case .standaloneTags: return Self.standaloneTagsRecordName
        case .discogsWorkCategories: return Self.discogsWorkCategoriesRecordName
        case .appPreferences: return Self.appPreferencesRecordName
        }
    }

    var recordType: String {
        switch self {
        case .tag: return "TagAssignment"
        case .listeningSession: return "ListeningSession"
        case .collectionPreferences: return "CollectionPreferences"
        case .shelfPreferences: return "ShelfPreferences"
        case .collectionSnapshot: return "CollectionValueSnapshot"
        case .wantlistAlert: return "WantlistAlert"
        case .standaloneTags: return "StandaloneTags"
        case .discogsWorkCategories: return "DiscogsWorkCategories"
        case .appPreferences: return "AppPreferences"
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
        if recordName.hasPrefix(snapshotPrefix) {
            return .collectionSnapshot(dayStamp: String(recordName.dropFirst(snapshotPrefix.count)))
        }
        if recordName.hasPrefix(wantlistAlertPrefix),
           let releaseId = Int(recordName.dropFirst(wantlistAlertPrefix.count)) {
            return .wantlistAlert(releaseId: releaseId)
        }
        if recordName == standaloneTagsRecordName { return .standaloneTags }
        if recordName == discogsWorkCategoriesRecordName { return .discogsWorkCategories }
        if recordName == appPreferencesRecordName { return .appPreferences }
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

/// Instantané synchronisable des préférences de rangement (voir `ShelfPreferencesStore`) : la
/// règle de tri, les deux réglages "ignorer les articles"/"trier par nom de famille", et les
/// personnalisations manuelles par artiste.
private struct SyncedShelfPreferences: Codable, Sendable {
    let sortStrategy: String
    let ignoreArticles: Bool
    let sortByLastName: Bool
    let restrictToSameFolder: Bool
    let customArtistSortOverrides: [String: String]

    private enum CodingKeys: String, CodingKey {
        case sortStrategy, ignoreArticles, sortByLastName, restrictToSameFolder, customArtistSortOverrides
    }

    init(
        sortStrategy: String,
        ignoreArticles: Bool,
        sortByLastName: Bool,
        restrictToSameFolder: Bool,
        customArtistSortOverrides: [String: String]
    ) {
        self.sortStrategy = sortStrategy
        self.ignoreArticles = ignoreArticles
        self.sortByLastName = sortByLastName
        self.restrictToSameFolder = restrictToSameFolder
        self.customArtistSortOverrides = customArtistSortOverrides
    }

    /// `restrictToSameFolder` est absent des payloads écrits par une version antérieure de
    /// l'app sur un autre appareil : `decodeIfPresent` évite de faire échouer tout le décodage
    /// (et donc de perdre les autres préférences déjà synchronisées) pour ce seul champ récent.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sortStrategy = try container.decode(String.self, forKey: .sortStrategy)
        ignoreArticles = try container.decode(Bool.self, forKey: .ignoreArticles)
        sortByLastName = try container.decode(Bool.self, forKey: .sortByLastName)
        restrictToSameFolder = try container.decodeIfPresent(Bool.self, forKey: .restrictToSameFolder) ?? false
        customArtistSortOverrides = try container.decode([String: String].self, forKey: .customArtistSortOverrides)
    }
}

/// Instantané synchronisable du thème de couleur, de l'apparence et de la durée maximale de la
/// Live Activity d'écoute (voir `ThemeManager`/`AppearancePreferencesStore`).
private struct SyncedAppPreferences: Codable, Sendable {
    let colorTheme: String
    let appearance: String
    let maxListeningDuration: TimeInterval
}

/// Instantané synchronisable d'un point d'historique de la valeur globale de la collection pour
/// un jour donné (voir `CollectionSnapshot`).
private struct SyncedCollectionSnapshot: Codable, Sendable {
    let date: Date
    let currency: String
    let low: Double
    let median: Double
    let high: Double
}

/// Synchronise les tags, le journal d'écoute, les alertes wantlist et certaines préférences via iCloud (base privée
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
    /// `true` pendant toute la réapplication d'un lot de changements distants (`handleEvent`,
    /// cas `.fetchedRecordZoneChanges`). `TagStore`/`LocalDataStore` ne doivent jamais redéclencher
    /// un envoi (`markDirty`/`markDeleted`) pendant cette fenêtre : ils ne le font aujourd'hui que
    /// par discipline (leurs méthodes `applyRemote*` sont des chemins de code dédiés, distincts de
    /// leurs méthodes d'écriture normales), sans garde-fou explicite. Ce flag rend cet invariant
    /// vérifiable au lieu de reposer uniquement sur cette convention — un futur appel égaré vers une
    /// méthode d'écriture normale depuis le chemin "distant" échoue bruyamment (assertion en debug)
    /// plutôt que de rouvrir silencieusement une boucle d'envoi vers iCloud.
    private var isApplyingRemoteChange = false
    /// Mis à `true` par `handleEvent` dès qu'un enregistrement individuel échoue pendant l'envoi
    /// en cours (ex: `CKError.zoneBusy`/`.requestRateLimited` après une rafale de changements) —
    /// consulté par `scheduleSend()` pour appliquer le même délai qu'un échec global, qui sinon ne
    /// couvre que l'échec de `sendChanges()` lui-même, pas celui de disques individuels à
    /// l'intérieur d'un envoi par ailleurs "réussi".
    private var hadRecordLevelFailureInLastSend = false
    /// Métadonnées système (`encodeSystemFields`) de la dernière version serveur connue de chaque
    /// enregistrement, alimentées par les récupérations, les envois réussis et les conflits
    /// `.serverRecordChanged`. Utilisées par `nextRecordZoneChangeBatch` pour repartir de la bonne
    /// version sans la redemander au serveur. En mémoire seulement : après un relancement, le
    /// premier envoi d'un enregistrement existant peut provoquer un conflit, résolu au tour suivant.
    private var serverSystemFields: [CKRecord.ID: Data] = [:]

    private let container = CKContainer.default()
    private static let stateStorageKey = "com.spinlog.cloudSyncEngineState"
    private nonisolated static let payloadField = "payload"
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
        cloudSyncLogger.log("start() — activeUsername=\(self.activeUsername ?? "nil", privacy: .private(mask: .hash))")
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
        // L'envoi en cours capture le moteur : sans cette annulation, il continuait d'envoyer
        // (et de se relancer) après la fin du premium.
        pendingSendTask?.cancel()
        pendingSendTask = nil
        syncEngine = nil
    }

    /// Repart d'un moteur neuf après une déconnexion/un changement de compte iCloud : l'état
    /// persisté et les métadonnées serveur mémorisées appartiennent à l'ancien compte, et la
    /// zone du nouveau compte n'a encore jamais reçu la poussée initiale.
    private func resetForNewICloudAccount() {
        cloudSyncLogger.log("resetForNewICloudAccount()")
        stop()
        UserDefaults.standard.removeObject(forKey: Self.stateStorageKey)
        serverSystemFields = [:]
        forgetSyncProgressForAllAccounts()
        if PremiumStore.shared.isPremium {
            start()
        }
    }

    /// Oublie, pour tous les comptes Discogs, que la réconciliation et la poussée initiales ont
    /// été faites : elles sont propres à un compte iCloud donné.
    private func forgetSyncProgressForAllAccounts() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.hydratedFlagKeyPrefix) || key.hasPrefix(Self.initialPushDoneKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Bascule ce moteur sur le compte Discogs indiqué. Ne recrée jamais le moteur lui-même (une
    /// seule base privée pour tout le compte iCloud, avec une zone par compte Discogs à
    /// l'intérieur) : rapatrie simplement tout ce que la zone de ce compte contient déjà côté
    /// iCloud et le fusionne dans les stores locaux. Appelé par `DiscogsAuthManager` aux mêmes
    /// points que `TagStore.setActiveUsername`/`ListeningLogStore.setActiveUsername`.
    func setActiveUsername(_ username: String?) {
        let normalized = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cloudSyncLogger.log("setActiveUsername(\(username ?? "nil", privacy: .private(mask: .hash))) — était \(self.activeUsername ?? "nil", privacy: .private(mask: .hash)), syncEngine \(self.syncEngine == nil ? "absent" : "présent", privacy: .public)")
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

    // MARK: - Suppression complète de la zone utilisateur (Guideline Apple 5.1.1(v))

    /// Supprime définitivement la zone iCloud privée et tous les enregistrements CloudKit
    /// associés à un utilisateur (tags, historique d'écoute, préférences, snapshots).
    func deleteCloudData(for username: String) {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        let targetZoneID = zoneID(for: normalized)

        // Réinitialise les marqueurs d'hydratation / push local
        UserDefaults.standard.removeObject(forKey: "\(Self.hydratedFlagKeyPrefix)\(normalized)")
        UserDefaults.standard.removeObject(forKey: "\(Self.initialPushDoneKeyPrefix)\(normalized)")

        // Si CKSyncEngine est actif, on lui demande de supprimer la zone
        if let syncEngine {
            syncEngine.state.add(pendingDatabaseChanges: [.deleteZone(targetZoneID)])
            scheduleSend()
        }

        // On ordonne également la suppression directe auprès de CloudKit pour garantir l'exécution
        container.privateCloudDatabase.delete(withRecordZoneID: targetZoneID) { zoneID, error in
            if let error {
                cloudSyncLogger.error("Suppression de la zone CloudKit \(targetZoneID.zoneName) : \(error.localizedDescription, privacy: .public)")
            } else {
                cloudSyncLogger.info("Zone CloudKit \(targetZoneID.zoneName) supprimée avec succès.")
            }
        }
    }

    // MARK: - Envoi (push)

    private func markDirty(_ kind: SyncedRecordKind) {
        // Voir le commentaire sur `isApplyingRemoteChange` : un appel ici pendant la réapplication
        // d'un changement distant indiquerait qu'une méthode d'écriture normale (au lieu d'un
        // `applyRemote*`) a été invoquée par erreur depuis `apply(remoteRecord:)`, ce qui
        // rouvrirait une boucle d'envoi vers iCloud.
        assert(!isApplyingRemoteChange, "markDirty appelé pendant l'application d'un changement distant")
        guard !isApplyingRemoteChange else { return }
        guard let syncEngine, let activeUsername else {
            cloudSyncLogger.log("markDirty(\(String(describing: kind), privacy: .public)) ignoré — syncEngine=\(self.syncEngine == nil ? "nil" : "ok", privacy: .public) activeUsername=\(self.activeUsername ?? "nil", privacy: .private(mask: .hash))")
            return
        }
        ensureZoneExists(for: activeUsername)
        let recordID = CKRecord.ID(recordName: kind.recordName, zoneID: zoneID(for: activeUsername))
        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        cloudSyncLogger.log("markDirty(\(String(describing: kind), privacy: .public)) — envoi vers zone \(recordID.zoneID.zoneName, privacy: .private(mask: .hash))")
        // La planification automatique du moteur est documentée comme "indéterminée" (dépend des
        // conditions système). On force un envoi pour que le changement apparaisse sur les autres
        // appareils sans attendre un cycle de synchronisation en arrière-plan.
        scheduleSend()
    }

    private func markDeleted(_ kind: SyncedRecordKind) {
        // Voir le commentaire sur `isApplyingRemoteChange` dans `markDirty`.
        assert(!isApplyingRemoteChange, "markDeleted appelé pendant l'application d'un changement distant")
        guard !isApplyingRemoteChange else { return }
        guard let syncEngine, let activeUsername else {
            cloudSyncLogger.log("markDeleted(\(String(describing: kind), privacy: .public)) ignoré — syncEngine=\(self.syncEngine == nil ? "nil" : "ok", privacy: .public) activeUsername=\(self.activeUsername ?? "nil", privacy: .private(mask: .hash))")
            return
        }
        let recordID = CKRecord.ID(recordName: kind.recordName, zoneID: zoneID(for: activeUsername))
        syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        cloudSyncLogger.log("markDeleted(\(String(describing: kind), privacy: .public)) — suppression vers zone \(recordID.zoneID.zoneName, privacy: .private(mask: .hash))")
        scheduleSend()
    }

    /// Signale qu'un exemplaire a des tags à envoyer vers iCloud. No-op silencieux si le moteur
    /// n'est pas actif (non premium) ou si aucun compte n'est actif.
    func markTagsDirty(instanceId: Int) {
        // Identifiant temporaire négatif d'un exemplaire en cours d'ajout (voir `ReleaseActions`) :
        // il ne doit jamais atteindre iCloud. Ses tags y partiront sous l'identifiant définitif,
        // via `TagStore.remapInstanceId`. Auparavant, chaque ajout créait un enregistrement parasite.
        guard instanceId > 0 else { return }
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

    /// Signale que les préférences de rangement (règle de tri, ignorer les articles, tri par nom
    /// de famille, ou personnalisations de tri des artistes) ont changé.
    func markShelfPreferencesDirty() {
        markDirty(.shelfPreferences)
    }

    /// Signale qu'un point d'historique de la valeur de la collection a été créé/mis à jour.
    func markCollectionSnapshotDirty(dayStamp: String) {
        markDirty(.collectionSnapshot(dayStamp: dayStamp))
    }

    /// Signale qu'une alerte de prix wantlist a été créée/modifiée (y compris par une vérification
    /// en arrière-plan) et doit être envoyée vers iCloud.
    func markWantlistAlertDirty(releaseId: Int) {
        markDirty(.wantlistAlert(releaseId: releaseId))
    }

    /// Signale qu'une alerte de prix wantlist a été supprimée localement et doit l'être aussi sur
    /// iCloud.
    func markWantlistAlertDeleted(releaseId: Int) {
        markDeleted(.wantlistAlert(releaseId: releaseId))
    }

    /// Signale que la bibliothèque de tags autonomes (créés sans être encore appliqués à un
    /// exemplaire) a changé.
    func markStandaloneTagsDirty() {
        markDirty(.standaloneTags)
    }

    /// Signale que de nouveaux masters Discogs ont été classés (voir `DiscogsWorkCategoryCache`).
    func markDiscogsWorkCategoriesDirty() {
        markDirty(.discogsWorkCategories)
    }

    /// Signale que le thème de couleur, l'apparence ou la durée maximale de la Live Activity
    /// d'écoute ont changé (voir `ThemeManager`/`AppearancePreferencesStore`).
    func markAppPreferencesDirty() {
        markDirty(.appPreferences)
    }

    /// Regroupe plusieurs signalements rapprochés en un seul envoi : CKSyncEngine ne doit pas
    /// recevoir plusieurs appels concurrents à `sendChanges()`, et ce serait de toute façon
    /// redondant (un seul envoi couvre déjà tous les changements en attente).
    private func scheduleSend() {
        guard pendingSendTask == nil, let syncEngine else { return }
        pendingSendTask = Task {
            var didFail = false
            hadRecordLevelFailureInLastSend = false
            do {
                try await syncEngine.sendChanges()
                cloudSyncLogger.log("sendChanges() terminé")
            } catch {
                didFail = true
                cloudSyncLogger.error("sendChanges() a échoué : \(error, privacy: .public)")
            }
            // Annulé par `stop()` : un nouveau moteur (et sa propre tâche d'envoi) a peut-être
            // déjà pris le relais, il ne faut ni l'effacer ni relancer d'envoi avec l'ancien.
            guard !Task.isCancelled else { return }
            pendingSendTask = nil
            // Si de nouveaux changements sont arrivés pendant l'envoi (y compris ceux remis en
            // attente après un conflit détecté dans `handleEvent`), on relance un envoi pour eux.
            // Après un échec, on attend avant de retenter : sans cette pause, un échec immédiat
            // (ex. CKError 36 "Account Temporarily Unavailable" juste après le lancement, ou un
            // throttling CloudKit après une rafale de changements type "poussée initiale" sur une
            // grosse collection) relance `scheduleSend()` en boucle serrée, des milliers de fois
            // par seconde, sans jamais laisser à CloudKit le temps de redevenir disponible — un
            // envoi peut par ailleurs "réussir" globalement (`sendChanges()` ne lève rien) tout en
            // ayant des échecs par disque individuel (`hadRecordLevelFailureInLastSend`), qui
            // méritent le même délai.
            // Seuls les changements de la zone active comptent : ceux d'un autre compte ne sont
            // jamais envoyés tant qu'il n'est pas actif (voir `nextRecordZoneChangeBatch`), et
            // les prendre en compte ici relancerait des envois à vide en boucle.
            if !pendingChangesForActiveZone(syncEngine).isEmpty {
                if didFail || hadRecordLevelFailureInLastSend {
                    try? await Task.sleep(for: .seconds(5))
                }
                guard syncEngine === self.syncEngine else { return }
                scheduleSend()
            }
        }
    }

    /// Changements en attente appartenant à la zone du compte actif (aucun si personne n'est
    /// connecté).
    private func pendingChangesForActiveZone(_ syncEngine: CKSyncEngine) -> [CKSyncEngine.PendingRecordZoneChange] {
        guard let activeUsername else { return [] }
        let activeZoneID = zoneID(for: activeUsername)
        return syncEngine.state.pendingRecordZoneChanges.filter { change in
            switch change {
            case .saveRecord(let recordID), .deleteRecord(let recordID):
                return recordID.zoneID == activeZoneID
            @unknown default:
                return false
            }
        }
    }

    // MARK: - Rapatriement (première synchro / changement de compte actif)

    /// Déclenche une récupération complète des changements côté iCloud. Découvre au passage les
    /// zones que cet appareil n'a jamais vues (ex: compte déjà utilisé sur un autre appareil) —
    /// les enregistrements reçus sont filtrés à la zone active dans `apply(remoteRecord:)`.
    private func hydrateActiveZone() {
        // `setActiveUsername` est appelé à chaque connexion Discogs, indépendamment du statut
        // premium (voir `DiscogsAuthManager`). Sans ce garde-fou sur `syncEngine`, un utilisateur
        // connecté AVANT de devenir premium déclencherait ici un cycle complet no-op (aucun appel
        // réseau, `markDirty` ignoré partout) qui marquerait quand même `pushDoneKey` à `true` plus
        // bas — et la vraie poussée initiale de ses données pré-existantes ne se déclencherait
        // alors plus jamais lors de son passage effectif au premium.
        guard let activeUsername, syncEngine != nil else {
            cloudSyncLogger.log("hydrateActiveZone() ignoré — activeUsername=\(self.activeUsername ?? "nil", privacy: .private(mask: .hash)) syncEngine=\(self.syncEngine == nil ? "nil" : "ok", privacy: .public)")
            return
        }
        cloudSyncLogger.log("hydrateActiveZone() pour \(activeUsername, privacy: .private(mask: .hash))")

        let pushDoneKey = Self.initialPushDoneKeyPrefix + activeUsername
        guard !UserDefaults.standard.bool(forKey: pushDoneKey) else {
            // Poussée initiale déjà faite pour ce compte sur cet appareil : un simple
            // rafraîchissement suffit, comme à chaque retour au premier plan. On relance aussi
            // l'envoi des changements de ce compte restés en attente pendant qu'un autre compte
            // était actif (voir `nextRecordZoneChangeBatch`).
            fetchLatestChanges()
            scheduleSend()
            return
        }

        // Poussée initiale : les données déjà créées localement avant que la synchro ne soit
        // active n'ont jamais déclenché de `markDirty` — on les envoie donc explicitement pour
        // TOUS les genres synchronisés, mais UNE SEULE FOIS par compte sur cet appareil. Si un
        // genre est ajouté plus tard, voir `resetInitialSyncForActiveAccount()` (option
        // développeur) pour redéclencher manuellement cette poussée sur un appareil qui l'a déjà
        // faite, plutôt que de multiplier les drapeaux de version.
        //
        // Cas critique : un compte utilisé sans premium sur deux appareils, chacun avec ses
        // propres tags/personnalisations de tri/sessions divergents, qui active la synchro sur
        // les deux. Il FAUT récupérer et fusionner (`await performFetchChanges()`, avec
        // `allowMerge` actif pour ce tout premier fetch) ce que l'autre appareil a peut-être déjà
        // poussé AVANT de construire et d'envoyer la poussée initiale de cet appareil — sinon les
        // deux poussées partiraient chacune avec un état purement local, et celle qui arrive en
        // second écraserait celle de l'autre au lieu de fusionner (le `nextRecordZoneChangeBatch`
        // n'envoie jamais que l'état local tel quel, volontairement, pour ne pas ressusciter des
        // suppressions — voir plus bas). Une fois cette fusion faite EN LOCAL, la poussée qui
        // suit envoie déjà l'état fusionné, quel que soit l'ordre d'activation entre les deux
        // appareils.
        Task {
            await performFetchChanges()

            let existingInstanceIds = TagStore.shared.allTaggedInstanceIds()
            let existingSessionIds = ListeningLogStore.shared.allSessionIds()
            let existingDayStamps = LocalDataStore.shared.collectionSnapshotDayStamps()
            let existingAlertReleaseIds = WantlistAlertStore.shared.allAlertReleaseIds()
            cloudSyncLogger.log("Poussée initiale de \(existingInstanceIds.count) exemplaire(s) tagué(s), \(existingSessionIds.count) session(s) d'écoute, \(existingDayStamps.count) point(s) d'historique de valeur et \(existingAlertReleaseIds.count) alerte(s) wantlist, ainsi que des préférences")
            // Cède périodiquement la main (toutes les 25 itérations) : pour une grosse collection,
            // ces boucles peuvent enregistrer des centaines/milliers de changements. Sans ces
            // points de cession, tout s'exécute en une seule rafale synchrone sur l'acteur
            // principal, sans jamais laisser SwiftUI rendre une image entre deux — perceptible
            // comme un blocage au moment même de la poussée initiale.
            for (index, instanceId) in existingInstanceIds.enumerated() {
                markTagsDirty(instanceId: instanceId)
                if index % 25 == 24 { await Task.yield() }
            }
            for (index, sessionId) in existingSessionIds.enumerated() {
                markSessionDirty(id: sessionId)
                if index % 25 == 24 { await Task.yield() }
            }
            for dayStamp in existingDayStamps {
                markCollectionSnapshotDirty(dayStamp: dayStamp)
            }
            for (index, releaseId) in existingAlertReleaseIds.enumerated() {
                markWantlistAlertDirty(releaseId: releaseId)
                if index % 25 == 24 { await Task.yield() }
            }
            markCollectionPreferencesDirty()
            markShelfPreferencesDirty()
            markStandaloneTagsDirty()
            markDiscogsWorkCategoriesDirty()
            markAppPreferencesDirty()
            // Marqué tout de suite, sans attendre la confirmation réseau : les changements sont
            // déjà enregistrés dans l'état persisté du moteur (`state.add` dans `markDirty`), qui
            // les redélivrera lui-même même si cet envoi immédiat échoue (ex: throttling).
            // Attendre le succès avant de marquer redéclencherait la même rafale à chaque
            // lancement tant que l'erreur passagère persiste.
            UserDefaults.standard.set(true, forKey: pushDoneKey)
        }
    }

    /// Option développeur (voir `DeveloperOptionsView`) : oublie que la poussée initiale a déjà
    /// été faite pour le compte actif sur cet appareil, et la redéclenche immédiatement. Utile
    /// pour retester la réconciliation de deux appareils divergents, ou pour repousser
    /// manuellement des données pré-existantes après l'ajout d'un nouveau genre synchronisé.
    func resetInitialSyncForActiveAccount() {
        guard let activeUsername else {
            cloudSyncLogger.log("resetInitialSyncForActiveAccount() ignoré — activeUsername=nil")
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.initialPushDoneKeyPrefix + activeUsername)
        UserDefaults.standard.removeObject(forKey: Self.hydratedFlagKeyPrefix + activeUsername)
        cloudSyncLogger.log("resetInitialSyncForActiveAccount() — drapeaux réinitialisés pour \(activeUsername, privacy: .private(mask: .hash)), nouvelle poussée initiale")
        hydrateActiveZone()
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
            cloudSyncLogger.log("performFetchChanges() ignoré — syncEngine=\(self.syncEngine == nil ? "nil" : "ok", privacy: .public) activeUsername=\(self.activeUsername ?? "nil", privacy: .private(mask: .hash))")
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
            cloudSyncLogger.log("fetchChanges() terminé pour \(activeUsername, privacy: .private(mask: .hash))")
            if isFirstHydrate {
                UserDefaults.standard.set(true, forKey: hydratedKey)
            }
            return true
        } catch {
            cloudSyncLogger.error("fetchChanges() a échoué pour \(activeUsername, privacy: .private(mask: .hash)) : \(error, privacy: .public)")
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
            cloudSyncLogger.log("apply(remoteRecord:) ignoré — zone \(record.recordID.zoneID.zoneName, privacy: .private(mask: .hash)) différente de la zone active")
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
            guard let remotePrefs = try? JSONDecoder().decode(SyncedShelfPreferences.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les préférences de rangement")
                return
            }
            let resolvedOverrides: [String: String]
            if allowMerge {
                // Union : ajoute les personnalisations locales absentes du serveur (l'appareil qui
                // n'avait encore rien poussé ne perd pas les siennes). En cas de conflit sur un
                // même artiste (rare), le serveur fait autorité — c'est-à-dire la valeur du
                // PREMIER appareil à avoir synchronisé ce compte, puisque cette fusion tourne
                // toujours après un fetch qui récupère l'état déjà poussé par un appareil
                // précédent (voir `hydrateActiveZone`). Un appareil qui synchronise après un autre
                // hérite donc de ses personnalisations en cas de désaccord, plutôt que d'imposer
                // les siennes.
                resolvedOverrides = remotePrefs.customArtistSortOverrides.merging(ShelfPreferencesStore.shared.customArtistSortOverrides) { remote, _ in remote }
            } else {
                resolvedOverrides = remotePrefs.customArtistSortOverrides
            }
            // La règle de tri, "ignorer les articles" et "trier par nom de famille" sont de
            // simples scalaires (comme `CollectionPreferences`) : pas de fusion possible, le
            // serveur fait toujours autorité — voir `hydrateActiveZone` pour l'explication du
            // choix "premier appareil synchronisé = maître" que ça implique en cas de désaccord.
            let resolvedStrategy = ShelfSortStrategy(rawValue: remotePrefs.sortStrategy) ?? ShelfPreferencesStore.shared.sortStrategy
            cloudSyncLogger.log("apply(remoteRecord:) préférences de rangement — overrides distants=\(remotePrefs.customArtistSortOverrides.count) allowMerge=\(allowMerge) résultat=\(resolvedOverrides.count)")
            ShelfPreferencesStore.shared.applyRemoteShelfPreferences(
                sortStrategy: resolvedStrategy,
                ignoreArticles: remotePrefs.ignoreArticles,
                sortByLastName: remotePrefs.sortByLastName,
                restrictToSameFolder: remotePrefs.restrictToSameFolder,
                customArtistSortOverrides: resolvedOverrides
            )

        case .collectionSnapshot(let dayStamp):
            guard let snapshot = try? JSONDecoder().decode(SyncedCollectionSnapshot.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour un point d'historique de valeur")
                return
            }
            cloudSyncLogger.log("apply(remoteRecord:) point d'historique de valeur \(dayStamp, privacy: .public)")
            LocalDataStore.shared.applyRemoteCollectionSnapshot(
                dayStamp: dayStamp,
                date: snapshot.date,
                currency: snapshot.currency,
                low: snapshot.low,
                median: snapshot.median,
                high: snapshot.high
            )

        case .wantlistAlert:
            guard let alert = try? JSONDecoder().decode(WantlistAlert.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour une alerte wantlist")
                return
            }
            cloudSyncLogger.log("apply(remoteRecord:) alerte wantlist \(alert.releaseId)")
            WantlistAlertStore.shared.applyRemoteAlert(alert)

        case .standaloneTags:
            guard let remoteStandaloneTags = try? JSONDecoder().decode(Set<String>.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les tags autonomes")
                return
            }
            // Union pure et sans conflit possible (un ensemble de chaînes, contrairement aux
            // personnalisations de tri qui associent une valeur par artiste) : pas besoin de
            // départager quoi que ce soit, contrairement à `.shelfPreferences`.
            let resolved = allowMerge ? remoteStandaloneTags.union(TagStore.shared.standaloneTags) : remoteStandaloneTags
            cloudSyncLogger.log("apply(remoteRecord:) tags autonomes — remote=\(remoteStandaloneTags.count) allowMerge=\(allowMerge) résultat=\(resolved.count)")
            TagStore.shared.applyRemoteStandaloneTags(resolved)

        case .discogsWorkCategories:
            guard let remoteCategories = try? JSONDecoder().decode([String: String].self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les sections Discogs")
                return
            }
            // Toujours fusionné, quel que soit `allowMerge` : un classement est une propriété
            // publique du master, identique sur tous les appareils — rien à départager ni à
            // supprimer, contrairement aux données de l'utilisateur.
            cloudSyncLogger.log("apply(remoteRecord:) sections Discogs — remote=\(remoteCategories.count)")
            DiscogsWorkCategoryCache.shared.applyRemote(remoteCategories)

        case .appPreferences:
            guard let prefs = try? JSONDecoder().decode(SyncedAppPreferences.self, from: payload) else {
                cloudSyncLogger.error("apply(remoteRecord:) — payload illisible pour les préférences d'apparence")
                return
            }
            // Scalaires, comme `.collectionPreferences` : pas de fusion possible, le serveur fait
            // toujours autorité.
            cloudSyncLogger.log("apply(remoteRecord:) préférences d'apparence")
            ThemeManager.shared.applyRemoteTheme(AppColorTheme(rawValue: prefs.colorTheme) ?? ThemeManager.shared.currentTheme)
            AppearancePreferencesStore.shared.applyRemotePreferences(
                appearance: AppTheme(rawValue: prefs.appearance) ?? AppearancePreferencesStore.shared.appearance,
                maxListeningDuration: prefs.maxListeningDuration
            )
        }
    }

    /// Applique une suppression reçue d'iCloud. Seules les sessions d'écoute et les alertes
    /// wantlist sont supprimées en tant que `CKRecord` (les tags et préférences ne sont eux
    /// jamais supprimés, uniquement remplacés par un contenu vide/par défaut) — tout autre genre
    /// est ignoré silencieusement.
    private func applyDeletion(recordID: CKRecord.ID) {
        guard let activeUsername, recordID.zoneID == zoneID(for: activeUsername) else { return }
        switch SyncedRecordKind.from(recordName: recordID.recordName) {
        case .listeningSession(let id):
            cloudSyncLogger.log("applyDeletion(recordID:) session d'écoute \(id, privacy: .public)")
            ListeningLogStore.shared.applyRemoteSessionDeletion(id: id)

        case .wantlistAlert(let releaseId):
            cloudSyncLogger.log("applyDeletion(recordID:) alerte wantlist \(releaseId)")
            WantlistAlertStore.shared.applyRemoteAlertDeletion(releaseId: releaseId)

        default:
            break
        }
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
            let prefs = SyncedShelfPreferences(
                sortStrategy: ShelfPreferencesStore.shared.sortStrategy.rawValue,
                ignoreArticles: ShelfPreferencesStore.shared.ignoreArticles,
                sortByLastName: ShelfPreferencesStore.shared.sortByLastName,
                restrictToSameFolder: ShelfPreferencesStore.shared.restrictToSameFolder,
                customArtistSortOverrides: ShelfPreferencesStore.shared.customArtistSortOverrides
            )
            return try? JSONEncoder().encode(prefs)

        case .collectionSnapshot(let dayStamp):
            guard let snapshot = LocalDataStore.shared.collectionSnapshot(dayStamp: dayStamp) else { return nil }
            let synced = SyncedCollectionSnapshot(
                date: snapshot.date,
                currency: snapshot.currency,
                low: snapshot.low,
                median: snapshot.median,
                high: snapshot.high
            )
            return try? JSONEncoder().encode(synced)

        case .wantlistAlert(let releaseId):
            guard let alert = WantlistAlertStore.shared.alert(for: releaseId) else { return nil }
            return try? JSONEncoder().encode(alert)

        case .standaloneTags:
            return try? JSONEncoder().encode(TagStore.shared.standaloneTags)

        case .discogsWorkCategories:
            return try? JSONEncoder().encode(DiscogsWorkCategoryCache.shared.syncPayload)

        case .appPreferences:
            let prefs = SyncedAppPreferences(
                colorTheme: ThemeManager.shared.currentTheme.rawValue,
                appearance: AppearancePreferencesStore.shared.appearance.rawValue,
                maxListeningDuration: AppearancePreferencesStore.shared.maxListeningDuration
            )
            return try? JSONEncoder().encode(prefs)
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncEngine: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // Un moteur remplacé (changement de compte iCloud) ou arrêté (fin du premium) peut encore
        // émettre des événements : les traiter réécrirait par exemple son état périmé par-dessus
        // celui du nouveau moteur.
        guard syncEngine === self.syncEngine else {
            cloudSyncLogger.log("handleEvent ignoré — moteur qui n'est plus actif")
            return
        }
        cloudSyncLogger.log("handleEvent: \(String(describing: event), privacy: .public)")
        switch event {
        case .stateUpdate(let stateUpdate):
            if let data = try? JSONEncoder().encode(stateUpdate.stateSerialization) {
                UserDefaults.standard.set(data, forKey: Self.stateStorageKey)
            }

        case .accountChange(let accountChange):
            cloudSyncLogger.log("accountChange: \(String(describing: accountChange), privacy: .public)")
            switch accountChange.changeType {
            case .signIn:
                // Compte iCloud (nouvellement) disponible pour ce moteur : la zone de ce compte
                // iCloud n'a encore jamais reçu les données locales, on refait donc la
                // réconciliation initiale (récupération + fusion, puis poussée complète). Le
                // moteur, lui, est conservé : ce n'est pas un changement de base.
                forgetSyncProgressForAllAccounts()
                hydrateActiveZone()
            case .signOut, .switchAccounts:
                // L'état persisté du moteur (jetons de changement, changements en attente)
                // appartient à l'ancien compte iCloud : le réutiliser avec un autre compte le
                // corromprait. On repart d'un moteur neuf. Les données locales sont conservées
                // (ce sont les données de l'utilisateur, pas un simple cache).
                resetForNewICloudAccount()
            @unknown default:
                resetForNewICloudAccount()
            }

        case .fetchedRecordZoneChanges(let fetchedChanges):
            cloudSyncLogger.log("fetchedRecordZoneChanges — \(fetchedChanges.modifications.count) modification(s), \(fetchedChanges.deletions.count) suppression(s)")
            // Voir le commentaire sur `isApplyingRemoteChange` : couvre toute cette réapplication,
            // pour que `markDirty`/`markDeleted` refusent bruyamment d'être appelées entre-temps.
            isApplyingRemoteChange = true
            defer { isApplyingRemoteChange = false }
            // Un lot peut contenir des centaines d'enregistrements (première synchro) : regroupés
            // pour que chaque store n'écrive sur disque et ne notifie l'UI qu'une fois par lot.
            TagStore.shared.performBatchUpdate {
                ListeningLogStore.shared.performBatchUpdate {
                    for modification in fetchedChanges.modifications {
                        rememberSystemFields(of: modification.record)
                        apply(remoteRecord: modification.record, allowMerge: isFirstHydrateForActiveAccount)
                    }
                    for deletion in fetchedChanges.deletions {
                        serverSystemFields[deletion.recordID] = nil
                        applyDeletion(recordID: deletion.recordID)
                    }
                }
            }

        case .sentRecordZoneChanges(let sentChanges):
            cloudSyncLogger.log("sentRecordZoneChanges — \(sentChanges.savedRecords.count) sauvé(s), \(sentChanges.deletedRecordIDs.count) supprimé(s), \(sentChanges.failedRecordSaves.count) échec(s) de sauvegarde, \(sentChanges.failedRecordDeletes.count) échec(s) de suppression")
            for savedRecord in sentChanges.savedRecords {
                rememberSystemFields(of: savedRecord)
            }
            for recordID in sentChanges.deletedRecordIDs {
                serverSystemFields[recordID] = nil
            }
            if !sentChanges.failedRecordSaves.isEmpty || !sentChanges.failedRecordDeletes.isEmpty {
                hadRecordLevelFailureInLastSend = true
            }
            for failedSave in sentChanges.failedRecordSaves {
                handleFailedSave(recordID: failedSave.record.recordID, error: failedSave.error, syncEngine: syncEngine)
            }
            for (recordID, error) in sentChanges.failedRecordDeletes {
                handleFailedDelete(recordID: recordID, error: error, syncEngine: syncEngine)
            }

        default:
            break
        }
    }

    /// Remet en attente un enregistrement dont l'envoi a échoué, mais uniquement si un nouvel
    /// essai a une chance d'aboutir. Auparavant, tout échec était remis en attente sans
    /// distinction — y compris les erreurs définitives (quota iCloud plein, permission refusée,
    /// argument invalide…), retentées toutes les 5 secondes indéfiniment.
    private func handleFailedSave(recordID: CKRecord.ID, error: CKError, syncEngine: CKSyncEngine) {
        cloudSyncLogger.error("failedRecordSave \(recordID.recordName, privacy: .public) : \(String(describing: error), privacy: .public)")
        switch error.code {
        case .serverRecordChanged:
            // Version locale périmée : on mémorise celle du serveur, et le prochain envoi part
            // de ses métadonnées (avec toujours le contenu local, voir `nextRecordZoneChangeBatch`).
            if let serverRecord = error.serverRecord {
                rememberSystemFields(of: serverRecord)
            }
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .zoneNotFound:
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: recordID.zoneID))])
            serverSystemFields[recordID] = nil
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .unknownItem:
            // Supprimé côté serveur entre-temps : les métadonnées mémorisées ne sont plus
            // valides, le prochain envoi le recrée.
            serverSystemFields[recordID] = nil
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .networkFailure, .networkUnavailable, .serviceUnavailable, .zoneBusy,
             .requestRateLimited, .notAuthenticated, .accountTemporarilyUnavailable,
             .operationCancelled, .batchRequestFailed:
            // Passager : nouvel essai (avec le délai de `scheduleSend`).
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        default:
            // Définitif (ex: `.quotaExceeded`, `.permissionFailure`, `.invalidArguments`, ou
            // `.userDeletedZone` — l'utilisateur a lui-même effacé les données iCloud de l'app,
            // à respecter). Abandonné : la prochaine modification locale de cet enregistrement
            // le renverra de toute façon.
            cloudSyncLogger.error("failedRecordSave \(recordID.recordName, privacy: .public) abandonné (erreur définitive \(error.code.rawValue, privacy: .public))")
        }
    }

    private func handleFailedDelete(recordID: CKRecord.ID, error: CKError, syncEngine: CKSyncEngine) {
        cloudSyncLogger.error("failedRecordDelete \(recordID.recordName, privacy: .public) : \(String(describing: error), privacy: .public)")
        switch error.code {
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            // Déjà absent du serveur : le but de la suppression est atteint.
            serverSystemFields[recordID] = nil

        case .networkFailure, .networkUnavailable, .serviceUnavailable, .zoneBusy,
             .requestRateLimited, .notAuthenticated, .accountTemporarilyUnavailable,
             .operationCancelled, .batchRequestFailed:
            syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])

        default:
            cloudSyncLogger.error("failedRecordDelete \(recordID.recordName, privacy: .public) abandonné (erreur définitive \(error.code.rawValue, privacy: .public))")
        }
    }

    private func rememberSystemFields(of record: CKRecord) {
        serverSystemFields[record.recordID] = Self.encodedSystemFields(of: record)
    }

    private nonisolated static func encodedSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private nonisolated static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// Nombre de disques traités par lot. À l'origine fixé à 1 (voir commentaire historique
    /// ci-dessous pour le raisonnement) : observé comme beaucoup trop lent pour une poussée
    /// initiale un peu conséquente (~150 disques ⇒ plus d'une minute, chaque disque attendant son
    /// propre aller-retour réseau de récupération de la version serveur avant d'être sauvé, l'un
    /// après l'autre). Toujours largement sous la limite d'opération CloudKit (400 disques), donc
    /// encore raisonnablement isolant : un conflit dans un lot de `batchSize` ne fait échouer que
    /// ce lot, pas l'ensemble de la poussée ni les lots suivants.
    private static let batchSize = 25

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === self.syncEngine else { return nil }
        // Plusieurs disques par lot plutôt qu'un seul (voir `batchSize`) : CloudKit envoie
        // toujours chaque lot comme une opération réseau atomique par zone, donc un conflit sur
        // l'un des disques du lot peut encore faire échouer les autres disques DU MÊME LOT (déjà
        // observé par le passé avec un lot "tout en un seul bloc") — mais CKSyncEngine rappelle
        // cette méthode autant de fois que nécessaire tant qu'un lot non-nil est renvoyé, donc les
        // lots suivants restent traités indépendamment les uns des autres.
        // Uniquement les changements de la zone du compte actif : les payloads sont reconstruits
        // ci-dessous depuis les stores locaux, qui ne contiennent que les données du compte actif
        // (vidés après déconnexion). Envoyer un changement resté en attente pour la zone d'un autre
        // compte y écrirait donc des données vides ou celles du mauvais compte — écrasant par
        // exemple sur iCloud les tags du compte précédent, puis sur tous ses autres appareils.
        // Ces changements restent en attente et partiront, avec les bonnes données, quand leur
        // compte redeviendra actif.
        let changes = Array(pendingChangesForActiveZone(syncEngine)
            .filter { context.options.scope.contains($0) }
            .prefix(Self.batchSize))
        guard !changes.isEmpty else { return nil }

        // Précalculé en synchrone, pour tous les disques du lot d'un coup : seule la récupération
        // de la version serveur ci-dessous a réellement besoin d'être refaite par disque.
        // Capturé en `let` (immuable) par le closure ci-dessous, qui tourne hors de l'acteur
        // principal (`@Sendable`) : une capture par référence mutable (`var`) y serait interdite.
        let payloadsByRecordID: [CKRecord.ID: (kind: SyncedRecordKind, payload: Data)] = changes.reduce(into: [:]) { result, change in
            guard case .saveRecord(let recordID) = change else { return }
            guard let kind = SyncedRecordKind.from(recordName: recordID.recordName),
                  let payload = payloadData(for: kind) else { return }
            result[recordID] = (kind, payload)
        }

        // `.deleteRecord` : CKSyncEngine gère la suppression sans consulter `recordProvider` — il
        // suffit de lui transmettre le changement tel quel au sein du même lot.
        // Métadonnées système (identité/version) de la dernière version serveur connue, capturées
        // en `Data` (Sendable) pour le closure ci-dessous.
        let systemFieldsByRecordID = serverSystemFields.filter { payloadsByRecordID[$0.key] != nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            guard let (kind, payload) = payloadsByRecordID[recordID] else { return nil }

            // Repart de la dernière version serveur connue (voir `serverSystemFields`), mais
            // UNIQUEMENT pour ses métadonnées système — jamais pour fusionner son contenu.
            // Fusionner (union) le contenu serveur avec l'état local ici referait exactement le
            // bug déjà corrigé côté réception : si l'utilisateur vient de retirer un tag
            // localement, le serveur a encore l'ancienne liste (le retrait n'a pas encore été
            // poussé) — une union des deux ferait "ressusciter" le tag qu'on vient de retirer. Le
            // contenu envoyé est donc toujours l'état local actuel tel quel.
            //
            // Plus de `database.record(for:)` réseau par disque (25 allers-retours par lot) : si
            // ces métadonnées sont absentes ou périmées, CloudKit refuse la sauvegarde avec
            // `.serverRecordChanged` en renvoyant la version serveur, que `handleEvent` mémorise
            // avant de remettre le changement en attente — d'où au pire un aller-retour de plus.
            let record = systemFieldsByRecordID[recordID].flatMap(Self.record(fromSystemFields:))
                ?? CKRecord(recordType: kind.recordType, recordID: recordID)
            record[Self.payloadField] = payload as CKRecordValue
            return record
        }
    }
}
