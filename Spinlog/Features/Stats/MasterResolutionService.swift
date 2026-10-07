import Foundation

/// Service d'arrière-plan dédié à la résolution progressive des années de sortie originales
/// des albums de la collection via l'API Masters de Discogs (`GET /masters/{id}`).
///
/// Caractéristiques :
/// - Cadencement sécurisé (1 requête toutes les 1,5s) pour ne pas saturer le quota de 60 req/min.
/// - Persistance pérenne dans SwiftData (`MasterRecord`) sans expiration TTL.
/// - File unique et dédupliquée, partagée par tous les appelants : un nouvel appel AJOUTE ses
///   masters à la file au lieu d'annuler la résolution en cours. Auparavant, chaque appel annulait
///   et relançait tout (en commençant par une pause de 1,5s) : `CollectionViewModel`, qui appelle ce
///   service à chaque page chargée pendant sa synchro de fond (environ une par seconde), empêchait
///   ainsi toute résolution d'aboutir — et figeait la progression affichée par l'écran Stats.
/// - Notification de chaque appelant via son propre callback (progression rapportée à ses
///   masters à lui), en plus de `.masterYearResolved` posté par `LocalDataStore.saveMasterYear`.
actor MasterResolutionService {
    static let shared = MasterResolutionService()

    /// Un appelant qui suit la résolution d'un ensemble de masters.
    private struct Subscriber {
        var remaining: Set<Int>
        let total: Int
        var resolved: Int
        let onProgress: @MainActor (Int, Int, Int, Int) -> Void
    }

    /// Masters en attente de résolution, dans l'ordre d'arrivée, sans doublon.
    private var pending: [Int] = []
    private var queued: Set<Int> = []
    private var subscribers: [String: Subscriber] = [:]
    private var worker: Task<Void, Never>?

    private init() {}

    /// Ajoute les masters manquants à la file de résolution (sans interrompre celle en cours).
    /// - Parameters:
    ///   - missingMasterIds: IDs de masters à résoudre (les doublons et ceux déjà en file sont ignorés).
    ///   - subscriberKey: identifie l'appelant. Un nouvel appel avec la même clé remplace le suivi
    ///     précédent (ex: l'écran Stats qui recalcule sa liste), sans retirer de masters de la file.
    ///   - onProgress: Callback sur MainActor appelé après chaque résolution d'un master de CET
    ///     appel (résolus, total, masterId, originalYear).
    func resolveMasters(
        missingMasterIds: [Int],
        subscriberKey: String = UUID().uuidString,
        onProgress: @escaping @MainActor (Int, Int, Int, Int) -> Void
    ) {
        let ids = Set(missingMasterIds)
        guard !ids.isEmpty else { return }

        subscribers[subscriberKey] = Subscriber(remaining: ids, total: ids.count, resolved: 0, onProgress: onProgress)
        for masterId in missingMasterIds where queued.insert(masterId).inserted {
            pending.append(masterId)
        }
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task {
            await runQueue()
        }
    }

    private func runQueue() async {
        while !Task.isCancelled, !pending.isEmpty {
            let masterId = pending.removeFirst()
            queued.remove(masterId)

            var year = 0
            do {
                // Cadencement de 1,5 seconde entre chaque requête pour respecter la limite
                try await Task.sleep(for: .seconds(1.5))
                let credentials = await MainActor.run { DiscogsAuthManager.shared.credentials }
                let master = try await DiscogsAPIClient.shared.masterRelease(id: masterId, credentials: credentials)
                year = max(master.year ?? 0, 0)
                // Persiste le résultat de façon pérenne (0 si Discogs n'a pas d'année : évite de
                // re-requêter ce master à chaque fois).
                let resolvedYear = year
                await MainActor.run {
                    LocalDataStore.shared.saveMasterYear(resolvedYear, for: masterId)
                }
            } catch is CancellationError {
                break
            } catch {
                // En cas d'erreur ponctuelle (404, réseau, etc.), on continue avec les suivants,
                // sans rien persister : ce master sera redemandé au prochain calcul.
            }
            await notifySubscribers(masterId: masterId, year: year)
        }
        worker = nil
        // Des masters ont pu être ajoutés pendant le dernier `await` après la sortie de boucle.
        if !pending.isEmpty && !Task.isCancelled {
            startWorkerIfNeeded()
        }
    }

    private func notifySubscribers(masterId: Int, year: Int) async {
        for key in Array(subscribers.keys) {
            guard var subscriber = subscribers[key], subscriber.remaining.remove(masterId) != nil else { continue }
            subscriber.resolved += 1
            let (resolved, total, onProgress) = (subscriber.resolved, subscriber.total, subscriber.onProgress)
            subscribers[key] = subscriber.remaining.isEmpty ? nil : subscriber
            await onProgress(resolved, total, masterId, year)
        }
    }

    func cancel() {
        worker?.cancel()
        worker = nil
        pending.removeAll()
        queued.removeAll()
        subscribers.removeAll()
    }
}
