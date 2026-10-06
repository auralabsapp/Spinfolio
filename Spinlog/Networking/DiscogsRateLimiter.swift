import Foundation

/// Fait respecter le quota Discogs (60 requêtes/minute pour une IP authentifiée) en amont de
/// chaque appel, et garde trace des headers `X-Discogs-Ratelimit*` renvoyés par l'API pour
/// s'ajuster dynamiquement plutôt que de se fier uniquement à un compteur local.
///
/// `actor` plutôt que classe `@MainActor` : c'est un état partagé entre requêtes concurrentes
/// (recherche + collection + wantlist peuvent appeler l'API en même temps), donc il a besoin
/// de sa propre isolation pour sérialiser les décisions de throttle sans course de données.
actor DiscogsRateLimiter {
    static let shared = DiscogsRateLimiter()

    private(set) var limit: Int?
    private(set) var remaining: Int?

    /// Horodatages (triés) des requêtes envoyées dans la dernière minute glissante, ainsi que des
    /// créneaux déjà réservés dans le futur par des requêtes en attente.
    private var recentRequestTimestamps: [Date] = []
    /// Marge de sécurité sous le plafond strict Discogs (60 req/min) pour absorber
    /// toute requête concurrente ou dérive d'horloge.
    private let maxRequestsPerMinute = 50
    private let rollingWindowSeconds: TimeInterval = 60

    /// À appeler juste avant d'envoyer une requête : patiente si le quota local ou celui
    /// annoncé par Discogs (`X-Discogs-Ratelimit-Remaining`) est épuisé.
    ///
    /// Le créneau est calculé et réservé de façon synchrone, AVANT toute attente : un `actor` est
    /// réentrant pendant un `await`, donc l'ancienne version (attendre, puis compter) laissait
    /// plusieurs requêtes concurrentes lire le même compteur, dormir la même durée et repartir
    /// toutes ensemble, en dépassant le quota. Ici, chaque appel voit les réservations des
    /// précédents et prend le créneau suivant.
    /// - Throws: `CancellationError` si la tâche appelante est annulée pendant l'attente (la
    ///   réservation est alors libérée et la requête n'est pas envoyée).
    func waitForSlot() async throws {
        let now = Date()
        pruneOldTimestamps()

        var slot = now
        // Fenêtre glissante : si le quota local est atteint, attendre que la requête la plus
        // ancienne parmi les `maxRequestsPerMinute` dernières sorte de la fenêtre.
        if recentRequestTimestamps.count >= maxRequestsPerMinute {
            let blocking = recentRequestTimestamps[recentRequestTimestamps.count - maxRequestsPerMinute]
            slot = max(slot, blocking.addingTimeInterval(rollingWindowSeconds + 0.5))
        }
        // Si Discogs annonce un solde restant critique, on espace les requêtes à partir de la
        // dernière déjà planifiée, pour laisser la fenêtre d'une minute se renouveler.
        if let remaining, remaining <= 5 {
            let spacing: TimeInterval = remaining <= 1 ? 10 : 2
            let lastScheduled = recentRequestTimestamps.last ?? now
            slot = max(slot, lastScheduled.addingTimeInterval(spacing))
            // Décompte local en attendant la réponse, qui fera foi (`recordResponse`).
            self.remaining = remaining - 1
        }

        reserve(slot)
        let delay = slot.timeIntervalSince(now)
        guard delay > 0 else { return }
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            release(slot)
            throw error
        }
    }

    private func reserve(_ slot: Date) {
        let index = recentRequestTimestamps.firstIndex(where: { $0 > slot }) ?? recentRequestTimestamps.endIndex
        recentRequestTimestamps.insert(slot, at: index)
    }

    private func release(_ slot: Date) {
        if let index = recentRequestTimestamps.firstIndex(of: slot) {
            recentRequestTimestamps.remove(at: index)
        }
    }

    /// Met à jour l'état à partir des headers de la réponse.
    func recordResponse(_ response: HTTPURLResponse) {
        if let value = response.value(forHTTPHeaderField: "X-Discogs-Ratelimit"), let intValue = Int(value) {
            limit = intValue
        }
        if let value = response.value(forHTTPHeaderField: "X-Discogs-Ratelimit-Remaining"), let intValue = Int(value) {
            remaining = intValue
        }
    }

    /// Délai à attendre avant de réessayer après un 429, d'après `Retry-After` si présent.
    func retryDelay(after response: HTTPURLResponse) -> Double {
        if let value = response.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(value) {
            return max(seconds, 2)
        }
        return 12
    }

    private func pruneOldTimestamps() {
        let now = Date()
        recentRequestTimestamps.removeAll { now.timeIntervalSince($0) > rollingWindowSeconds }
    }
}
