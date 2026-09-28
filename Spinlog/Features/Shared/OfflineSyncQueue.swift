import Foundation
import Observation

enum ActionType: String, Codable, Sendable {
    case addToCollection
    case removeFromCollection
    case addToWantlist
    case removeFromWantlist
}

struct PendingAction: Identifiable, Codable, Sendable {
    let id: UUID
    let type: ActionType
    let releaseId: Int
    let folderId: Int?
    let instanceId: Int?
    let date: Date
    var retryCount: Int

    init(
        id: UUID = UUID(),
        type: ActionType,
        releaseId: Int,
        folderId: Int? = nil,
        instanceId: Int? = nil,
        date: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.type = type
        self.releaseId = releaseId
        self.folderId = folderId
        self.instanceId = instanceId
        self.date = date
        self.retryCount = retryCount
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
    }

    // MARK: - Gestion de la file

    func enqueue(_ action: PendingAction) {
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
        guard let username = DiscogsAuthManager.shared.username,
              let credentials = DiscogsAuthManager.shared.credentials else { return }

        isProcessing = true
        defer { isProcessing = false }

        while !pendingActions.isEmpty && NetworkMonitor.shared.isConnected {
            let action = pendingActions[0]

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
                if !pendingActions.isEmpty && pendingActions[0].id == action.id {
                    pendingActions.removeFirst()
                    persistActions()
                }
            } catch {
                // Gestion du Rate Limiting HTTP 429
                let errorString = error.localizedDescription
                if errorString.contains("429") || (error as? DiscogsError) == .rateLimited {
                    // Backoff de sécurité avant de réessayer
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }

                // Incrémenter les tentatives ou déclarer l'échec définitif
                var updatedAction = action
                updatedAction.retryCount += 1

                if updatedAction.retryCount >= 3 {
                    // Échec définitif : suppression de la file et notification de l'utilisateur
                    if !pendingActions.isEmpty && pendingActions[0].id == action.id {
                        pendingActions.removeFirst()
                        persistActions()
                    }
                    lastErrorNotification = "Échec définitif de synchronisation : \(actionDescription(for: action)) (\(error.localizedDescription))"
                } else {
                    // Mise à jour de l'action avec nouveau compteur
                    if !pendingActions.isEmpty && pendingActions[0].id == action.id {
                        pendingActions[0] = updatedAction
                        persistActions()
                    }
                    // Pause temporaire avant la prochaine tentative
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private func executeAction(
        _ action: PendingAction,
        username: String,
        credentials: DiscogsCredentials
    ) async throws {
        switch action.type {
        case .addToCollection:
            let folderId = action.folderId ?? 1 // Dossier "Uncategorized" par défaut si absent
            _ = try await DiscogsAPIClient.shared.addToCollection(
                username: username,
                folderId: folderId,
                releaseId: action.releaseId,
                credentials: credentials
            )

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
        }
    }

    private func actionDescription(for action: PendingAction) -> String {
        switch action.type {
        case .addToCollection: return "Ajout à la collection (release \(action.releaseId))"
        case .removeFromCollection: return "Suppression de la collection (release \(action.releaseId))"
        case .addToWantlist: return "Ajout à la wantlist (release \(action.releaseId))"
        case .removeFromWantlist: return "Suppression de la wantlist (release \(action.releaseId))"
        }
    }
}
