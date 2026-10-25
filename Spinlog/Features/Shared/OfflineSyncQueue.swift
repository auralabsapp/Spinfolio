import Foundation
import Observation

enum ActionType: String, Codable, Sendable {
    case addToCollection
    case removeFromCollection
    case addToWantlist
    case removeFromWantlist
    case updateCollectionField
    case moveCollectionInstance
}

nonisolated struct PendingAction: Identifiable, Codable, Sendable {
    let id: UUID
    let type: ActionType
    let releaseId: Int
    /// Dossier courant de l'exemplaire au moment de l'action (utilisé dans le chemin de la
    /// requête Discogs). Pour `.moveCollectionInstance`, c'est le dossier de départ.
    let folderId: Int?
    let instanceId: Int?
    let date: Date
    var retryCount: Int
    /// Identifiant du champ personnalisé Discogs modifié (seulement pour `.updateCollectionField`).
    let fieldId: Int?
    /// Nouvelle valeur du champ personnalisé (seulement pour `.updateCollectionField`).
    let value: String?
    /// Dossier de destination (seulement pour `.moveCollectionInstance`).
    let targetFolderId: Int?
    /// Compte Discogs auquel appartient l'action, renseigné par `OfflineSyncQueue.enqueue` : une
    /// action ne doit jamais être rejouée avec les identifiants d'un autre compte. `nil` pour les
    /// actions persistées par une version antérieure (rejouées sur le compte connecté, comme avant).
    var username: String?
    /// Exemplaires déjà rattachés à un autre ajout du même disque (seulement pour
    /// `.addToCollection`) : ils ne doivent pas être pris pour la trace de cet ajout-ci (voir
    /// `OfflineSyncQueue.matchingAlreadyAddedInstance`). `nil` pour les actions plus anciennes.
    var excludedInstanceIds: [Int]?

    /// Indique si l'action peut être rejouée pour le compte `username`.
    func belongs(to username: String) -> Bool {
        guard let owner = self.username else { return true }
        return owner.caseInsensitiveCompare(username) == .orderedSame
    }

    init(
        id: UUID = UUID(),
        type: ActionType,
        releaseId: Int,
        folderId: Int? = nil,
        instanceId: Int? = nil,
        date: Date = Date(),
        retryCount: Int = 0,
        fieldId: Int? = nil,
        value: String? = nil,
        targetFolderId: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.releaseId = releaseId
        self.folderId = folderId
        self.instanceId = instanceId
        self.date = date
        self.retryCount = retryCount
        self.fieldId = fieldId
        self.value = value
        self.targetFolderId = targetFolderId
    }
}

enum OfflineSyncError: LocalizedError {
    case ambiguousInstance

    var errorDescription: String? {
        switch self {
        case .ambiguousInstance:
            return String(localized: "plusieurs exemplaires de ce disque, supprime-le manuellement")
        }
    }
}

/// File d'attente des mutations hors ligne avec traitement séquentiel et respect strict
/// du rate-limiting de Discogs (1 appel/s min, backoff sur 429).
@Observable
@MainActor
final class OfflineSyncQueue {
    static let shared = OfflineSyncQueue()

    private(set) var pendingActions: [PendingAction] = []
    private(set) var isProcessing: Bool = false
    var lastErrorNotification: String?

    private let storageKey = "com.spinlog.offlinePendingActions"
    private var lastRequestTime: Date = .distantPast

    /// Nouvel essai programmé après une panne passagère (réseau instable, Discogs indisponible).
    private var retryTask: Task<Void, Never>?
    /// Pannes passagères successives, pour espacer les essais (30 s, 1 min, 2 min… jusqu'à 30 min).
    private var consecutiveTransientFailures = 0
    /// Au-delà, une action qui n'a jamais pu partir est abandonnée (avec un message) plutôt que
    /// rejouée indéfiniment sur une collection qui a pu changer entre-temps.
    nonisolated static let maxPendingAge: TimeInterval = 7 * 24 * 3600
    /// Refus définitifs (4xx) tolérés avant abandon : ils se reproduiront presque toujours.
    private static let maxDefinitiveFailures = 3

    private init() {
        loadPersistedActions()

        // Sans cet observateur, une file remplie hors ligne ne se relance qu'au prochain
        // `enqueue()` (s'il intervient alors qu'on est déjà reconnecté) : rien ne la reprenait
        // sinon au simple retour du réseau.
        NotificationCenter.default.addObserver(
            forName: .networkConnectionRestored,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.processQueue()
            }
        }
    }

    // MARK: - Gestion de la file

    /// Suppression des données du compte : ses actions en attente ne doivent plus partir.
    func removeActions(for username: String) {
        let before = pendingActions.count
        pendingActions.removeAll { $0.username?.caseInsensitiveCompare(username) == .orderedSame }
        if pendingActions.count != before {
            persistActions()
        }
    }

    func clearQueue() {
        pendingActions.removeAll()
        persistActions()
    }

    func enqueue(_ action: PendingAction) {
        var action = action
        if action.username == nil {
            action.username = DiscogsAuthManager.shared.username
        }
        pendingActions.append(action)
        persistActions()

        // Si le réseau est disponible, tenter la synchronisation
        if NetworkMonitor.shared.isConnected {
            Task { await processQueue() }
        }
    }

    private func persistActions() {
        if let data = try? JSONEncoder().encode(pendingActions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Tolérant aux données partiellement illisibles (voir `PersistedStoreDecoding`) : une action
    /// abîmée ne fait plus perdre toutes les autres actions en attente.
    private func loadPersistedActions() {
        pendingActions = PersistedStoreDecoding.decodeArray(PendingAction.self, forKey: storageKey) ?? []
    }

    // MARK: - Exécution de la file

    func processQueue() async {
        guard !isProcessing, !pendingActions.isEmpty, NetworkMonitor.shared.isConnected else { return }
        guard let (username, credentials) = DiscogsAuthManager.shared.session else { return }

        isProcessing = true
        // Rejoué silencieusement (retour réseau ou après un ajout hors ligne), jamais en réponse
        // directe à une action que l'utilisateur regarde activement — voir le même correctif sur
        // `CollectionViewModel.startBackgroundSync`.
        await DiscogsRateLimiter.$priority.withValue(.background) {
        defer { isProcessing = false }

        // Les actions d'un autre compte restent en file, intactes, jusqu'à ce que ce compte se
        // reconnecte : les rejouer ici les appliquerait à la collection du mauvais compte.
        // La session est revérifiée à chaque tour : après une déconnexion ou un changement de
        // compte, la boucle continuait sinon à envoyer avec les identifiants du compte quitté.
        while NetworkMonitor.shared.isConnected,
              DiscogsAuthManager.shared.username == username,
              let action = pendingActions.first(where: { $0.belongs(to: username) }) {

            // Respect impératif du rate-limiting Discogs (au moins 1,1s entre chaque requête)
            let elapsed = Date().timeIntervalSince(lastRequestTime)
            if elapsed < 1.1 {
                let delay = 1.1 - elapsed
                try? await Task.sleep(for: .seconds(delay))
            }

            do {
                lastRequestTime = Date()
                try await executeAction(action, username: username, credentials: credentials)

                // Succès : retirer de la file
                removeAction(id: action.id)
                consecutiveTransientFailures = 0
            } catch where error.isNotFound && (action.type == .removeFromCollection || action.type == .removeFromWantlist) {
                // Retrait d'un élément déjà absent sur Discogs : le but est atteint. Auparavant,
                // ce 404 était retenté trois fois puis signalé comme un échec définitif.
                removeAction(id: action.id)
            } catch {
                if Self.isRateLimited(error) {
                    // Backoff de sécurité avant de réessayer
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }

                if error.isTransientNetworkFailure {
                    // Panne passagère : l'action reste en file, intacte. Auparavant, ces erreurs
                    // comptaient comme des échecs ordinaires (3 essais à 2 s d'intervalle), si bien
                    // qu'une coupure réseau de quelques secondes suffisait à perdre l'action.
                    if Task.isCancelled || error.isCancellation { break }
                    if Self.hasExpired(action) {
                        removeAction(id: action.id)
                        lastErrorNotification = String(localized: "Échec définitif de synchronisation : \(actionDescription(for: action)) (\(error.localizedDescription))")
                        continue
                    }
                    consecutiveTransientFailures += 1
                    scheduleRetry()
                    break
                }

                // Refus définitif (4xx...) : quelques essais, puis abandon signalé à l'utilisateur.
                var updatedAction = action
                updatedAction.retryCount += 1

                if updatedAction.retryCount >= Self.maxDefinitiveFailures {
                    removeAction(id: action.id)
                    lastErrorNotification = String(localized: "Échec définitif de synchronisation : \(actionDescription(for: action)) (\(error.localizedDescription))")
                } else {
                    if let index = pendingActions.firstIndex(where: { $0.id == action.id }) {
                        pendingActions[index] = updatedAction
                        persistActions()
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        }
    }

    /// Délai avant le prochain essai : 30 s après la première panne passagère, puis doublé à
    /// chaque panne successive, plafonné à 30 min.
    nonisolated static func retryDelay(afterConsecutiveFailures failures: Int) -> TimeInterval {
        min(30 * pow(2, Double(max(0, failures - 1))), 1800)
    }

    /// Action jamais partie depuis plus de `maxPendingAge` : abandonnée plutôt que rejouée.
    nonisolated static func hasExpired(_ action: PendingAction, now: Date = Date()) -> Bool {
        now.timeIntervalSince(action.date) > maxPendingAge
    }

    private static func isRateLimited(_ error: Error) -> Bool {
        guard let apiError = error as? DiscogsAPIClient.APIError else {
            return error.localizedDescription.contains("429")
        }
        switch apiError {
        case .rateLimited: return true
        case .http(let status, _): return status == 429
        default: return false
        }
    }

    /// Reprend la file plus tard, avec un délai qui double à chaque panne passagère successive.
    /// Complète les reprises déjà déclenchées par le retour du réseau et le retour au premier plan.
    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = Self.retryDelay(afterConsecutiveFailures: consecutiveTransientFailures)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.processQueue()
        }
    }

    // MARK: - Exemplaires pas encore synchronisés

    /// Un exemplaire ajouté hors ligne n'existe pas encore sur Discogs : il porte l'identifiant
    /// temporaire négatif enregistré dans `instanceId` de son action `.addToCollection` (voir
    /// `ReleaseActions.addToCollection`). Le retirer revient donc à annuler cet ajout en
    /// attente — auparavant, un retrait de cet identifiant inexistant était mis en file, échouait,
    /// et l'ajout initial finissait quand même par être envoyé.
    /// - Returns: `true` si un ajout en attente a été trouvé et annulé.
    @discardableResult
    func cancelPendingAdd(temporaryInstanceId: Int) -> Bool {
        guard temporaryInstanceId < 0,
              let action = pendingActions.first(where: { $0.type == .addToCollection && $0.instanceId == temporaryInstanceId }) else {
            return false
        }
        removeAction(id: action.id)
        return true
    }

    /// Change le dossier de destination d'un ajout encore en attente (déplacement d'un exemplaire
    /// ajouté hors ligne), plutôt que de mettre en file un déplacement d'un identifiant inexistant.
    /// - Returns: `true` si un ajout en attente a été trouvé et modifié.
    @discardableResult
    func retargetPendingAdd(temporaryInstanceId: Int, toFolderId: Int) -> Bool {
        guard temporaryInstanceId < 0,
              let index = pendingActions.firstIndex(where: { $0.type == .addToCollection && $0.instanceId == temporaryInstanceId }) else {
            return false
        }
        let action = pendingActions[index]
        var retargeted = PendingAction(
            id: action.id,
            type: action.type,
            releaseId: action.releaseId,
            folderId: toFolderId,
            instanceId: action.instanceId,
            date: action.date,
            retryCount: action.retryCount
        )
        retargeted.username = action.username
        retargeted.excludedInstanceIds = action.excludedInstanceIds
        pendingActions[index] = retargeted
        persistActions()
        return true
    }

    /// Un dossier vient d'être supprimé et ses exemplaires déplacés vers `toFolderId` : les
    /// actions en attente qui le visaient (ajout dedans, déplacement vers lui, ou action sur un
    /// exemplaire qui s'y trouvait) visent désormais ce nouveau dossier, au lieu d'échouer sur un
    /// dossier inexistant puis d'être abandonnées.
    func retargetActions(fromFolderId: Int, toFolderId: Int) {
        let updated = Self.retargeted(pendingActions, fromFolderId: fromFolderId, toFolderId: toFolderId)
        guard updated.map(\.folderId) != pendingActions.map(\.folderId)
                || updated.map(\.targetFolderId) != pendingActions.map(\.targetFolderId) else { return }
        pendingActions = updated
        persistActions()
    }

    /// Dossiers supprimés sur discogs.com (absents de la liste reçue de Discogs) : les actions en
    /// attente du compte qui les visaient partent vers Uncategorized, où Discogs a déplacé leurs
    /// exemplaires, au lieu d'échouer puis d'être abandonnées.
    func retargetActionsForDeletedFolders(validFolderIds: Set<Int>, username: String) {
        let missing = Self.missingFolderIds(in: pendingActions.filter { $0.belongs(to: username) }, validFolderIds: validFolderIds)
        for folderId in missing {
            retargetActions(fromFolderId: folderId, toFolderId: DiscogsConstants.uncategorizedFolderId)
        }
    }

    /// Dossiers visés par ces actions qui n'existent plus. « All » (0) et Uncategorized (1),
    /// dossiers permanents de Discogs, ne sont jamais concernés.
    nonisolated static func missingFolderIds(in actions: [PendingAction], validFolderIds: Set<Int>) -> Set<Int> {
        let permanent: Set<Int> = [DiscogsConstants.allFolderId, DiscogsConstants.uncategorizedFolderId]
        let targeted = actions.flatMap { [$0.folderId, $0.targetFolderId].compactMap { $0 } }
        return Set(targeted).subtracting(validFolderIds).subtracting(permanent)
    }

    nonisolated static func retargeted(_ actions: [PendingAction], fromFolderId: Int, toFolderId: Int) -> [PendingAction] {
        actions.map { action in
            guard action.folderId == fromFolderId || action.targetFolderId == fromFolderId else { return action }
            var updated = PendingAction(
                id: action.id,
                type: action.type,
                releaseId: action.releaseId,
                folderId: action.folderId == fromFolderId ? toFolderId : action.folderId,
                instanceId: action.instanceId,
                date: action.date,
                retryCount: action.retryCount,
                fieldId: action.fieldId,
                value: action.value,
                targetFolderId: action.targetFolderId == fromFolderId ? toFolderId : action.targetFolderId
            )
            updated.username = action.username
            updated.excludedInstanceIds = action.excludedInstanceIds
            return updated
        }
    }

    private func removeAction(id: UUID) {
        guard let index = pendingActions.firstIndex(where: { $0.id == id }) else { return }
        pendingActions.remove(at: index)
        persistActions()
    }

    private func executeAction(
        _ action: PendingAction,
        username: String,
        credentials: DiscogsCredentials
    ) async throws {
        switch action.type {
        case .addToCollection:
            // `targetFolderId` : écrit par d'anciennes versions de `WantlistViewModel` à la place
            // de `folderId`, ce qui envoyait le disque dans "Uncategorized".
            let folderId = action.folderId ?? action.targetFolderId ?? DiscogsConstants.uncategorizedFolderId
            // Un ajout n'est pas idempotent chez Discogs : si un premier envoi a abouti sans que la
            // réponse ne revienne (délai dépassé, coupure), le rejouer créerait un doublon. On
            // vérifie donc d'abord qu'aucun exemplaire n'a déjà été créé depuis la mise en file.
            let existing: [CollectionItem]
            do {
                existing = try await DiscogsAPIClient.shared.collectionInstances(
                    username: username, releaseId: action.releaseId, credentials: credentials
                ).releases
            } catch where error.isNotFound {
                // Disque absent de la collection : rien n'a encore été ajouté.
                existing = []
            }
            let instanceId: Int
            if let alreadyAdded = Self.matchingAlreadyAddedInstance(in: existing, for: action) {
                instanceId = alreadyAdded
            } else {
                instanceId = try await DiscogsAPIClient.shared.addToCollection(
                    username: username,
                    folderId: folderId,
                    releaseId: action.releaseId,
                    credentials: credentials
                ).instanceId
            }
            excludeInstanceFromOtherAdds(instanceId, releaseId: action.releaseId, exceptActionId: action.id)
            // Exemplaire créé hors ligne : ses tags étaient rattachés à l'identifiant temporaire,
            // on les reporte sur l'identifiant définitif (sinon ils étaient perdus à la synchro).
            if let temporaryInstanceId = action.instanceId, temporaryInstanceId < 0 {
                TagStore.shared.remapInstanceId(from: temporaryInstanceId, to: instanceId)
            }

        case .removeFromCollection:
            if let instanceId = action.instanceId {
                try await DiscogsAPIClient.shared.removeFromCollection(
                    username: username,
                    folderId: action.folderId ?? 0,
                    releaseId: action.releaseId,
                    instanceId: instanceId,
                    credentials: credentials
                )
            } else {
                // Si instanceId non renseigné, récupérer l'instance existante d'abord
                let instances = try await DiscogsAPIClient.shared.collectionInstances(
                    username: username,
                    releaseId: action.releaseId,
                    credentials: credentials
                )
                // Plusieurs exemplaires : impossible de savoir lequel supprimer, on échoue plutôt
                // que de retirer arbitrairement le premier (potentiellement le mauvais).
                guard instances.releases.count <= 1 else {
                    throw OfflineSyncError.ambiguousInstance
                }
                if let instance = instances.releases.first {
                    try await DiscogsAPIClient.shared.removeFromCollection(
                        username: username,
                        folderId: action.folderId ?? instance.folderId,
                        releaseId: action.releaseId,
                        instanceId: instance.instanceId,
                        credentials: credentials
                    )
                }
            }

        case .addToWantlist:
            _ = try await DiscogsAPIClient.shared.addToWantlist(
                username: username,
                releaseId: action.releaseId,
                credentials: credentials
            )

        case .removeFromWantlist:
            try await DiscogsAPIClient.shared.removeFromWantlist(
                username: username,
                releaseId: action.releaseId,
                credentials: credentials
            )

        case .updateCollectionField:
            guard let instanceId = action.instanceId, let fieldId = action.fieldId, let value = action.value else { return }
            try await DiscogsAPIClient.shared.updateCollectionField(
                username: username,
                folderId: action.folderId ?? DiscogsConstants.uncategorizedFolderId,
                releaseId: action.releaseId,
                instanceId: instanceId,
                fieldId: fieldId,
                value: value,
                credentials: credentials
            )

        case .moveCollectionInstance:
            guard let instanceId = action.instanceId, let targetFolderId = action.targetFolderId else { return }
            try await DiscogsAPIClient.shared.moveCollectionInstance(
                username: username,
                folderId: action.folderId ?? DiscogsConstants.uncategorizedFolderId,
                releaseId: action.releaseId,
                instanceId: instanceId,
                toFolderId: targetFolderId,
                credentials: credentials
            )
        }
    }

    /// Tolérance sur l'horloge de l'appareil par rapport à celle de Discogs.
    nonisolated static let addedInstanceClockTolerance: TimeInterval = 120

    /// Exemplaire déjà créé par un précédent envoi de cet ajout : ajouté sur Discogs après la mise
    /// en file (à la tolérance d'horloge près) et pas déjà rattaché à un autre ajout du même disque.
    nonisolated static func matchingAlreadyAddedInstance(in instances: [CollectionItem], for action: PendingAction) -> Int? {
        let excluded = Set(action.excludedInstanceIds ?? [])
        let threshold = action.date.addingTimeInterval(-addedInstanceClockTolerance)
        return instances
            .filter { !excluded.contains($0.instanceId) }
            .filter { ($0.dateAddedDate ?? .distantPast) >= threshold }
            .min { ($0.dateAddedDate ?? .distantPast) < ($1.dateAddedDate ?? .distantPast) }?
            .instanceId
    }

    /// L'exemplaire vient d'être rattaché à un ajout : les autres ajouts en attente du même disque
    /// (deux exemplaires ajoutés volontairement hors ligne) ne doivent pas le prendre pour le leur.
    private func excludeInstanceFromOtherAdds(_ instanceId: Int, releaseId: Int, exceptActionId: UUID) {
        var changed = false
        for index in pendingActions.indices
        where pendingActions[index].type == .addToCollection
            && pendingActions[index].releaseId == releaseId
            && pendingActions[index].id != exceptActionId {
            pendingActions[index].excludedInstanceIds = (pendingActions[index].excludedInstanceIds ?? []) + [instanceId]
            changed = true
        }
        if changed {
            persistActions()
        }
    }

    private func actionDescription(for action: PendingAction) -> String {
        switch action.type {
        case .addToCollection: return String(localized: "Ajout à la collection (release \(String(action.releaseId)))")
        case .removeFromCollection: return String(localized: "Suppression de la collection (release \(String(action.releaseId)))")
        case .addToWantlist: return String(localized: "Ajout à la wantlist (release \(String(action.releaseId)))")
        case .removeFromWantlist: return String(localized: "Suppression de la wantlist (release \(String(action.releaseId)))")
        case .updateCollectionField: return String(localized: "Modification d'un champ personnalisé (release \(String(action.releaseId)))")
        case .moveCollectionInstance: return String(localized: "Changement de dossier (release \(String(action.releaseId)))")
        }
    }
}
