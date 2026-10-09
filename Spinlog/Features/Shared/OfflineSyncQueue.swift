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

struct PendingAction: Identifiable, Codable, Sendable {
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

    private func loadPersistedActions() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PendingAction].self, from: data) {
            pendingActions = decoded
        }
    }

    // MARK: - Exécution de la file

    func processQueue() async {
        guard !isProcessing, !pendingActions.isEmpty, NetworkMonitor.shared.isConnected else { return }
        guard let (username, credentials) = DiscogsAuthManager.shared.session else { return }

        isProcessing = true
        defer { isProcessing = false }

        // Les actions d'un autre compte restent en file, intactes, jusqu'à ce que ce compte se
        // reconnecte : les rejouer ici les appliquerait à la collection du mauvais compte.
        while NetworkMonitor.shared.isConnected,
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
            } catch where error.isNotFound && (action.type == .removeFromCollection || action.type == .removeFromWantlist) {
                // Retrait d'un élément déjà absent sur Discogs : le but est atteint. Auparavant,
                // ce 404 était retenté trois fois puis signalé comme un échec définitif.
                removeAction(id: action.id)
            } catch {
                // Gestion du Rate Limiting HTTP 429
                let errorString = error.localizedDescription
                let isRateLimited: Bool
                if let apiError = error as? DiscogsAPIClient.APIError {
                    switch apiError {
                    case .rateLimited: isRateLimited = true
                    case .http(let status, _): isRateLimited = (status == 429)
                    default: isRateLimited = false
                    }
                } else {
                    isRateLimited = errorString.contains("429")
                }

                if isRateLimited {
                    // Backoff de sécurité avant de réessayer
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }

                // Incrémenter les tentatives ou déclarer l'échec définitif
                var updatedAction = action
                updatedAction.retryCount += 1

                if updatedAction.retryCount >= 3 {
                    // Échec définitif : suppression de la file et notification de l'utilisateur
                    removeAction(id: action.id)
                    lastErrorNotification = String(localized: "Échec définitif de synchronisation : \(actionDescription(for: action)) (\(error.localizedDescription))")
                } else {
                    // Mise à jour de l'action avec nouveau compteur
                    if let index = pendingActions.firstIndex(where: { $0.id == action.id }) {
                        pendingActions[index] = updatedAction
                        persistActions()
                    }
                    // Pause temporaire avant la prochaine tentative
                    try? await Task.sleep(for: .seconds(2))
                }
            }
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
        pendingActions[index] = retargeted
        persistActions()
        return true
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
            let response = try await DiscogsAPIClient.shared.addToCollection(
                username: username,
                folderId: folderId,
                releaseId: action.releaseId,
                credentials: credentials
            )
            // Exemplaire créé hors ligne : ses tags étaient rattachés à l'identifiant temporaire,
            // on les reporte sur l'identifiant définitif (sinon ils étaient perdus à la synchro).
            if let temporaryInstanceId = action.instanceId, temporaryInstanceId < 0 {
                TagStore.shared.remapInstanceId(from: temporaryInstanceId, to: response.instanceId)
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
