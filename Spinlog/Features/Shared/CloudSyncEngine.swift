import Foundation
import CloudKit
import Observation
import OSLog
import UIKit

nonisolated let cloudSyncLogger = Logger(subsystem: "com.auralabs.Spinlog", category: "CloudSyncEngine")

/// Synchronise les tags, le journal d'écoute, les alertes wantlist et certaines préférences via iCloud (base privée
/// CloudKit) entre les appareils d'un même compte premium. Une zone `CKRecordZone` dédiée par
/// compte Discogs (`account-<username>`) isole les données de chaque compte à l'intérieur d'une
/// seule base privée, comme `TagStore` le fait déjà localement avec ses clés `UserDefaults`
/// préfixées par compte.
///
/// Entièrement gaté par `PremiumStore.shared.isPremium` (et l'interrupteur `isUserEnabled`) : côté non-premium, aucun appel réseau
/// n'est fait et aucune donnée ne quitte l'appareil. En cas de désabonnement, les zones et
/// enregistrements déjà présents sur iCloud ne sont jamais supprimés — seul le push/pull depuis
/// cet appareil s'arrête, pour permettre une reprise sans perte en cas de réabonnement.
@Observable
@MainActor
final class CloudSyncEngine: CKSyncEngineDelegate {
    static let shared = CloudSyncEngine()

    var syncEngine: CKSyncEngine?
    private(set) var activeUsername: String?
    /// Coalesce plusieurs signalements rapprochés (ex: la poussée initiale de nombreux exemplaires
    /// tagués) en un seul envoi réseau, plutôt que de lancer un `sendChanges()` concurrent par
    /// appel — inutile et potentiellement instable sur le même moteur.
    private var pendingSendTask: Task<Void, Never>?
    /// `true` uniquement pendant le tout premier `fetchChanges()` réussi pour le compte actif sur
    /// cet appareil — voir `apply(remoteRecord:allowMerge:)`.
    var isFirstHydrateForActiveAccount = false
    /// `true` pendant toute la réapplication d'un lot de changements distants (`handleEvent`,
    /// cas `.fetchedRecordZoneChanges`). `TagStore`/`LocalDataStore` ne doivent jamais redéclencher
    /// un envoi (`markDirty`/`markDeleted`) pendant cette fenêtre : ils ne le font aujourd'hui que
    /// par discipline (leurs méthodes `applyRemote*` sont des chemins de code dédiés, distincts de
    /// leurs méthodes d'écriture normales), sans garde-fou explicite. Ce flag rend cet invariant
    /// vérifiable au lieu de reposer uniquement sur cette convention — un futur appel égaré vers une
    /// méthode d'écriture normale depuis le chemin "distant" échoue bruyamment (assertion en debug)
    /// plutôt que de rouvrir silencieusement une boucle d'envoi vers iCloud.
    var isApplyingRemoteChange = false
    /// Mis à `true` par `handleEvent` dès qu'un enregistrement individuel échoue pendant l'envoi
    /// en cours (ex: `CKError.zoneBusy`/`.requestRateLimited` après une rafale de changements) —
    /// consulté par `scheduleSend()` pour appliquer le même délai qu'un échec global, qui sinon ne
    /// couvre que l'échec de `sendChanges()` lui-même, pas celui de disques individuels à
    /// l'intérieur d'un envoi par ailleurs "réussi".
    var hadRecordLevelFailureInLastSend = false
    /// Métadonnées système (`encodeSystemFields`) de la dernière version serveur connue de chaque
    /// enregistrement, alimentées par les récupérations, les envois réussis et les conflits
    /// `.serverRecordChanged`. Utilisées par `nextRecordZoneChangeBatch` pour repartir de la bonne
    /// version sans la redemander au serveur. En mémoire seulement : après un relancement, le
    /// premier envoi d'un enregistrement existant peut provoquer un conflit, résolu au tour suivant.
    var serverSystemFields: [CKRecord.ID: Data] = [:]

    private let container = CKContainer.default()
    static let stateStorageKey = "com.spinlog.cloudSyncEngineState"
    nonisolated static let payloadField = "payload"
    static let hydratedFlagKeyPrefix = "com.spinlog.cloudSync.hydrated_"
    static let initialPushDoneKeyPrefix = "com.spinlog.cloudSync.initialPushDone_"
    nonisolated static let userEnabledKey = "com.spinlog.cloudSync.userEnabled"

    /// Interrupteur « Synchronisation iCloud » de Réglages, propre à cet appareil (activé par
    /// défaut). Couper la synchro arrête seulement les échanges depuis cet appareil : rien n'est
    /// effacé, ni en local ni sur iCloud.
    private(set) var isUserEnabled = CloudSyncEngine.isUserEnabled(in: .standard)

    /// Absent des réglages (installation neuve, version précédente) = activé, comme avant
    /// l'existence de l'interrupteur.
    nonisolated static func isUserEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: userEnabledKey) as? Bool ?? true
    }

    /// Le moteur ne tourne qu'avec le Premium ET l'interrupteur activé.
    nonisolated static func shouldRun(isPremium: Bool, isUserEnabled: Bool) -> Bool {
        isPremium && isUserEnabled
    }

    private var shouldRun: Bool {
        Self.shouldRun(isPremium: PremiumStore.shared.isPremium, isUserEnabled: isUserEnabled)
    }

    /// Les modifications faites pendant la coupure n'ont jamais été signalées au moteur (aucun
    /// `markDirty` sans moteur actif) : à la réactivation, on oublie la réconciliation initiale
    /// pour que tout soit à nouveau fusionné avec iCloud et repoussé, sinon elles resteraient
    /// sur cet appareil.
    func setUserEnabled(_ enabled: Bool) {
        guard enabled != isUserEnabled else { return }
        isUserEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.userEnabledKey)
        cloudSyncLogger.log("setUserEnabled(\(enabled, privacy: .public))")
        if enabled {
            forgetSyncProgressForAllAccounts()
            if shouldRun {
                start()
            }
        } else {
            stop()
        }
    }

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

        if shouldRun {
            start()
        }
    }

    /// Statut Premium hors démo au dernier changement, pour repérer le passage au Premium.
    private var hadAccessOutsideDemo = PremiumStore.shared.hasAccessOutsideDemo

    /// Passer Premium (abonnement ou réabonnement) réactive la synchro, même coupée à la main
    /// auparavant. L'aperçu de la démo ne compte pas : la démo n'est jamais synchronisée.
    nonisolated static func shouldAutoEnable(hadAccess: Bool, hasAccess: Bool) -> Bool {
        !hadAccess && hasAccess
    }

    private func premiumStatusChanged() {
        let hasAccess = PremiumStore.shared.hasAccessOutsideDemo
        if Self.shouldAutoEnable(hadAccess: hadAccessOutsideDemo, hasAccess: hasAccess) {
            cloudSyncLogger.log("premiumStatusChanged() — passage au Premium, synchro réactivée")
            isUserEnabled = true
            UserDefaults.standard.set(true, forKey: Self.userEnabledKey)
            // Comme pour une réactivation manuelle (`setUserEnabled`) : rien de ce qui a été
            // modifié sans Premium n'a été envoyé, d'où une fusion complète avec iCloud.
            forgetSyncProgressForAllAccounts()
        }
        hadAccessOutsideDemo = hasAccess
        if shouldRun {
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
    func resetForNewICloudAccount() {
        cloudSyncLogger.log("resetForNewICloudAccount()")
        stop()
        UserDefaults.standard.removeObject(forKey: Self.stateStorageKey)
        serverSystemFields = [:]
        forgetSyncProgressForAllAccounts()
        if shouldRun {
            start()
        }
    }

    /// Oublie, pour tous les comptes Discogs, que la réconciliation et la poussée initiales ont
    /// été faites : elles sont propres à un compte iCloud donné.
    func forgetSyncProgressForAllAccounts() {
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

    func zoneID(for username: String) -> CKRecordZone.ID {
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
        CloudSyncModificationLog.clearAll(for: normalized)

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
        CloudSyncModificationLog.recordLocalModification(kind.recordName, username: activeUsername)
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
    func scheduleSend() {
        guard pendingSendTask == nil, let syncEngine else { return }
        // Détachée (voir `detachedOnMainActor`) : lancée aussi depuis `handleEvent`, via
        // `hydrateActiveZone`.
        pendingSendTask = detachedOnMainActor { [self] in
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
    func pendingChangesForActiveZone(_ syncEngine: CKSyncEngine) -> [CKSyncEngine.PendingRecordZoneChange] {
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

}
