import Foundation
import OSLog

/// Fait respecter le quota Discogs (60 requêtes/minute pour une IP authentifiée) en amont de
/// chaque appel, et garde trace des headers `X-Discogs-Ratelimit*` renvoyés par l'API pour
/// s'ajuster dynamiquement plutôt que de se fier uniquement à un compteur local.
///
/// `actor` plutôt que classe `@MainActor` : c'est un état partagé entre requêtes concurrentes
/// (recherche + collection + wantlist peuvent appeler l'API en même temps), donc il a besoin
/// de sa propre isolation pour sérialiser les décisions de throttle sans course de données.
actor DiscogsRateLimiter {
    static let shared = DiscogsRateLimiter()

    /// Visible dans Instruments (onglet "Points of Interest" / "os_signpost"), filtrable sur le
    /// sous-système/catégorie ci-dessous : un intervalle par requête, englobant l'attente
    /// éventuelle, avec la priorité en message — permet de vérifier visuellement que les requêtes
    /// `.background` attendent bien plus longtemps/souvent que les `.normal`, sans avoir à
    /// déduire quoi que ce soit du seul timing brut des requêtes réseau.
    private let signposter = OSSignposter(subsystem: "com.aurelienscarpa.Spinlog", category: "DiscogsRateLimiter")

    /// Priorité des requêtes émises par la tâche en cours (voir `DiscogsRequestPriority`).
    /// `TaskLocal` : la tâche de fond l'active une fois pour tout son travail, sans passer de
    /// paramètre à chaque endpoint.
    @TaskLocal static var priority: DiscogsRequestPriority = .normal

    private(set) var limit: Int?
    private(set) var remaining: Int?

    /// Horodatages (triés) des requêtes envoyées dans la dernière minute glissante, ainsi que des
    /// créneaux déjà réservés dans le futur par des requêtes en attente.
    private var recentRequestTimestamps: [Date] = []
    /// Marge de sécurité sous le plafond strict Discogs (60 req/min) pour absorber
    /// toute requête concurrente ou dérive d'horloge.
    private static let maxRequestsPerMinute = 50
    private static let rollingWindowSeconds: TimeInterval = 60
    /// Plafond dur sur l'attente, quelle que soit la cause (fenêtre glissante saturée, solde
    /// Discogs bas) : la réservation est anticipée (voir `waitForSlot`), donc une rafale de
    /// requêtes (plusieurs fiches release ouvertes coup sur coup, 3 requêtes chacune) peut faire
    /// composer les créneaux réservés sur plusieurs minutes. Mieux vaut risquer un 429 ponctuel
    /// (déjà géré par le retry sur `Retry-After` dans `DiscogsAPIClient`) que de laisser l'UI
    /// paraître bloquée indéfiniment.
    private static let maxQueueWaitSeconds: TimeInterval = 20

    /// Dernière requête de priorité normale (action de l'utilisateur, synchro de la collection,
    /// résolution des années…) : les requêtes de fond leur laissent la place.
    private var lastNormalRequestDate: Date?
    /// Dernier créneau accordé à une requête de fond.
    private var lastBackgroundSlot: Date?
    /// Une requête de fond ne part qu'après ce délai sans requête normale…
    private static let backgroundQuietPeriod: TimeInterval = 8
    /// …si moins de requêtes que ce plafond sont parties dans la dernière minute (la moitié du
    /// quota reste ainsi toujours disponible pour l'utilisateur)…
    private static let backgroundMaxRequestsPerMinute = 25
    /// …et au plus une toutes les 3 secondes (20 par minute).
    private static let backgroundMinSpacing: TimeInterval = 3

    /// Point d'entrée du client : attend un créneau selon la priorité de la tâche courante.
    func waitForSlot(priority: DiscogsRequestPriority) async throws {
        let priorityLabel: String
        switch priority {
        case .normal: priorityLabel = "normal"
        case .background: priorityLabel = "background"
        }
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(
            "Discogs rate limit wait", id: signpostID, "priority: \(priorityLabel, privacy: .public)"
        )
        defer { signposter.endInterval("Discogs rate limit wait", state) }

        switch priority {
        case .normal:
            lastNormalRequestDate = Date()
            try await waitForSlot()
        case .background:
            try await waitForBackgroundSlot()
        }
    }

    /// Attend que l'app soit « au calme » côté Discogs (voir les constantes ci-dessus), puis
    /// prend un créneau ordinaire. Revérifié après chaque attente : une requête normale arrivée
    /// entre-temps repousse la requête de fond.
    private func waitForBackgroundSlot() async throws {
        while true {
            let now = Date()
            pruneOldTimestamps()
            let readyAt = Self.backgroundReadyDate(
                now: now,
                lastNormalRequest: lastNormalRequestDate,
                lastBackgroundSlot: lastBackgroundSlot,
                recentRequests: recentRequestTimestamps,
                remaining: remaining
            )
            let delay = readyAt.timeIntervalSince(now)
            if delay <= 0 { break }
            // Plafonné : on redescend boucler plutôt que de dormir d'une traite sur un délai
            // potentiellement très long (voir `maxQueueWaitSeconds`) — une requête normale
            // arrivée entre-temps doit pouvoir faire réévaluer `lastNormalRequestDate` à la
            // prochaine itération plutôt que rester figée dans un unique `Task.sleep`.
            try await Task.sleep(for: .seconds(min(delay, Self.maxQueueWaitSeconds)))
        }
        lastBackgroundSlot = Date()
        try await waitForSlot()
    }

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

        let (slot, remainingAfter) = Self.nextSlot(now: now, reservedSlots: recentRequestTimestamps, remaining: remaining)
        // Décompte local en attendant la réponse, qui fera foi (`recordResponse`).
        remaining = remainingAfter

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

    // MARK: - Calcul des créneaux (fonctions pures, testées dans `DiscogsRateLimiterTests`)

    /// Créneau de la prochaine requête normale, d'après les créneaux déjà réservés de la dernière
    /// minute (triés) et le solde annoncé par Discogs ; renvoie aussi le solde décompté localement.
    nonisolated static func nextSlot(now: Date, reservedSlots: [Date], remaining: Int?) -> (slot: Date, remaining: Int?) {
        var slot = now
        var remainingAfter = remaining
        // Fenêtre glissante : si le quota local est atteint, attendre que la requête la plus
        // ancienne parmi les `maxRequestsPerMinute` dernières sorte de la fenêtre.
        if reservedSlots.count >= maxRequestsPerMinute {
            let blocking = reservedSlots[reservedSlots.count - maxRequestsPerMinute]
            slot = max(slot, blocking.addingTimeInterval(rollingWindowSeconds + 0.5))
        }
        // Si Discogs annonce un solde restant critique, on espace les requêtes à partir de la
        // dernière déjà planifiée, pour laisser la fenêtre d'une minute se renouveler.
        if let remaining, remaining <= 5 {
            let spacing: TimeInterval = remaining <= 1 ? 10 : 2
            let lastScheduled = reservedSlots.last ?? now
            slot = max(slot, lastScheduled.addingTimeInterval(spacing))
            remainingAfter = remaining - 1
        }
        // Voir `maxQueueWaitSeconds` : évite qu'une rafale de requêtes ne fasse composer les
        // créneaux réservés sur plusieurs minutes.
        slot = min(slot, now.addingTimeInterval(maxQueueWaitSeconds))
        return (slot, remainingAfter)
    }

    /// Moment à partir duquel une requête de fond peut prendre un créneau.
    nonisolated static func backgroundReadyDate(
        now: Date,
        lastNormalRequest: Date?,
        lastBackgroundSlot: Date?,
        recentRequests: [Date],
        remaining: Int?
    ) -> Date {
        var readyAt = now
        if let lastNormalRequest {
            readyAt = max(readyAt, lastNormalRequest.addingTimeInterval(backgroundQuietPeriod))
        }
        if let lastBackgroundSlot {
            readyAt = max(readyAt, lastBackgroundSlot.addingTimeInterval(backgroundMinSpacing))
        }
        if recentRequests.count >= backgroundMaxRequestsPerMinute, let oldest = recentRequests.first {
            readyAt = max(readyAt, oldest.addingTimeInterval(rollingWindowSeconds + 0.5))
        }
        if let remaining, remaining <= 10 {
            // Solde Discogs bas : on le laisse se reconstituer pour l'utilisateur.
            readyAt = max(readyAt, now.addingTimeInterval(15))
        }
        return readyAt
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
        recentRequestTimestamps.removeAll { now.timeIntervalSince($0) > Self.rollingWindowSeconds }
    }
}

/// Priorité d'une requête Discogs : `.background` pour le travail que l'utilisateur n'attend pas
/// (classement des discographies en tâche de fond), qui cède systématiquement la place au reste.
enum DiscogsRequestPriority: Sendable {
    case normal
    case background
}
