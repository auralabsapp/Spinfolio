import Foundation

/// Service d'arrière-plan dédié à la résolution progressive des années de sortie originales
/// des albums de la collection via l'API Masters de Discogs (`GET /masters/{id}`).
///
/// Caractéristiques :
/// - Cadencement sécurisé (1 requête toutes les 1,5s) pour ne pas saturer le quota de 60 req/min.
/// - Persistance pérenne dans SwiftData (`MasterRecord`) sans expiration TTL.
/// - Déduplication des masters manquants.
/// - Notification au ViewModel via un callback ou NotificationCenter pour rafraîchir l'histogramme en direct.
actor MasterResolutionService {
    static let shared = MasterResolutionService()

    private var isResolving = false
    private var currentTask: Task<Void, Never>?

    private init() {}

    /// Résout en tâche de fond les masters manquants.
    /// - Parameters:
    ///   - missingMasterIds: Liste ordonnée et dédupliquée des IDs de masters à résoudre.
    ///   - onProgress: Callback sur MainActor appelé après chaque résolution (résolus, total, masterId, originalYear).
    func resolveMasters(
        missingMasterIds: [Int],
        onProgress: @escaping @MainActor (Int, Int, Int, Int) -> Void
    ) async {
        guard !missingMasterIds.isEmpty else { return }
        if isResolving {
            // Si une résolution est déjà en cours, on annule la précédente pour prendre en compte la nouvelle liste
            currentTask?.cancel()
        }

        isResolving = true
        let totalCount = missingMasterIds.count
        var resolvedCount = 0

        currentTask = Task {
            for masterId in missingMasterIds {
                if Task.isCancelled { break }

                do {
                    // Cadencement de 1,5 seconde entre chaque requête pour respecter la limite
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    if Task.isCancelled { break }

                    let credentials = await MainActor.run { DiscogsAuthManager.shared.credentials }
                    let master = try await DiscogsAPIClient.shared.masterRelease(id: masterId, credentials: credentials)

                    if let originalYear = master.year, originalYear > 0 {
                        // Persiste le résultat de façon pérenne
                        await MainActor.run {
                            LocalDataStore.shared.saveMasterYear(originalYear, for: masterId)
                        }
                        resolvedCount += 1
                        await onProgress(resolvedCount, totalCount, masterId, originalYear)
                    } else {
                        // Si le master n'a pas d'année définie sur Discogs, on enregistre 0 pour ne pas le re-requêter
                        await MainActor.run {
                            LocalDataStore.shared.saveMasterYear(0, for: masterId)
                        }
                        resolvedCount += 1
                        await onProgress(resolvedCount, totalCount, masterId, 0)
                    }
                } catch {
                    // En cas d'erreur ponctuelle (404, réseau, etc.), on continue avec les suivants
                    resolvedCount += 1
                    await onProgress(resolvedCount, totalCount, masterId, 0)
                }
            }
            self.finishResolving()
        }

        await currentTask?.value
    }

    private func finishResolving() {
        isResolving = false
        currentTask = nil
    }

    func cancel() {
        currentTask?.cancel()
        isResolving = false
        currentTask = nil
    }
}
