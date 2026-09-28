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

    /// Horodatages des requêtes envoyées dans la dernière minute glissante.
    private var recentRequestTimestamps: [Date] = []
    private let maxRequestsPerMinute = 60

    /// À appeler juste avant d'envoyer une requête : patiente si le quota local ou celui
    /// annoncé par Discogs (`X-Discogs-Ratelimit-Remaining`) est épuisé.
    func waitForSlot() async {
        // Si Discogs nous dit qu'il ne reste presque plus de requêtes ce cycle, on ralentit
        // proactivement même si notre propre compteur local ne sature pas encore.
        if let remaining, remaining <= 2 {
            try? await Task.sleep(for: .seconds(2))
        }

        pruneOldTimestamps()
        if recentRequestTimestamps.count >= maxRequestsPerMinute, let oldest = recentRequestTimestamps.first {
            let waitTime = 60 - Date().timeIntervalSince(oldest) + 0.2
            if waitTime > 0 {
                try? await Task.sleep(for: .seconds(waitTime))
            }
            pruneOldTimestamps()
        }
        recentRequestTimestamps.append(Date())
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
            return seconds
        }
        return 5
    }

    private func pruneOldTimestamps() {
        let now = Date()
        recentRequestTimestamps.removeAll { now.timeIntervalSince($0) > 60 }
    }
}
