import Foundation

/// Les deux parcours de grades : la taille de la collection (disques distincts) et le nombre
/// d'écoutes sur platine (le journal d'écoute, jamais Apple Music).
nonisolated enum GradeTrack: String, CaseIterable, Codable, Sendable, Identifiable {
    case collection
    case listening

    var id: String { rawValue }

    /// Seuils croissants : franchir le n-ième donne le grade d'indice n. Espacement de plus en plus
    /// large, pour que les premiers grades arrivent vite (encouragement) et les derniers se méritent.
    var thresholds: [Int] {
        switch self {
        case .collection: [1, 10, 50, 100, 250, 500, 1_000]
        case .listening: [1, 10, 50, 100, 250, 500, 1_000]
        }
    }
}

/// Un grade franchi : parcours, indice du palier et date de franchissement. Le tout est ce qui est
/// mémorisé et synchronisé (jamais le nombre lui-même, qui peut redescendre sans rien retirer).
nonisolated struct GradeUnlock: Codable, Hashable, Sendable {
    let track: GradeTrack
    let tier: Int
    let date: Date
}

/// Règles pures des grades : tout ce qui se décide sans état ni interface, pour être testé seul.
nonisolated enum GradeRules {
    /// Durée pendant laquelle un grade tout juste obtenu décide du parcours ouvert dans « Mes grades ».
    static let recentUnlockWindow: TimeInterval = 3 * 24 * 3600

    /// Parcours à montrer à l'ouverture de « Mes grades » : celui du grade obtenu le plus récemment
    /// s'il date de moins de `recentUnlockWindow` (on arrive de la célébration, ou juste après),
    /// sinon Collection.
    static func trackToShow(unlocks: [GradeUnlock], now: Date) -> GradeTrack {
        guard let latest = unlocks.max(by: { $0.date < $1.date }),
              now.timeIntervalSince(latest.date) < recentUnlockWindow else { return .collection }
        return latest.track
    }

    /// Nombre de paliers atteints pour ce nombre (0 = aucun). Un nombre négatif ou nul n'en atteint aucun.
    static func reachedTierCount(count: Int, track: GradeTrack) -> Int {
        track.thresholds.filter { count >= $0 }.count
    }

    /// Seuil du palier suivant le nombre de paliers déjà acquis, ou `nil` au dernier grade.
    static func nextThreshold(acquiredTiers: Int, track: GradeTrack) -> Int? {
        let thresholds = track.thresholds
        return acquiredTiers < thresholds.count ? thresholds[acquiredTiers] : nil
    }

    /// Progression (0…1) entre le dernier seuil acquis et le suivant ; 1 au dernier grade.
    static func progress(count: Int, acquiredTiers: Int, track: GradeTrack) -> Double {
        guard let next = nextThreshold(acquiredTiers: acquiredTiers, track: track) else { return 1 }
        let previous = acquiredTiers > 0 ? track.thresholds[acquiredTiers - 1] : 0
        let span = max(1, next - previous)
        return min(1, max(0, Double(count - previous) / Double(span)))
    }

    /// Fusionne deux jeux de grades (appareil local et iCloud) : on garde tous les paliers connus
    /// d'un côté ou de l'autre, avec la date la plus ancienne. Un grade ne se perd donc jamais et
    /// l'ordre de fusion est sans importance (commutative, idempotente).
    static func merge(_ lhs: [GradeUnlock], _ rhs: [GradeUnlock]) -> [GradeUnlock] {
        var earliest: [Key: Date] = [:]
        for unlock in lhs + rhs {
            let key = Key(track: unlock.track, tier: unlock.tier)
            if let known = earliest[key], known <= unlock.date { continue }
            earliest[key] = unlock.date
        }
        return normalized(earliest.map { GradeUnlock(track: $0.key.track, tier: $0.key.tier, date: $0.value) })
    }

    /// Résultat de la fusion d'un enregistrement iCloud avec les grades de l'appareil.
    struct RemoteMerge: Equatable {
        let unlocks: [GradeUnlock]
        let welcomeDecided: Bool
        /// L'appareil a changé (à enregistrer).
        let changesLocal: Bool
        /// L'appareil en sait plus que iCloud (à renvoyer). Évalué même si rien ne change en local :
        /// auparavant, un grade connu du seul appareil n'était jamais renvoyé dans ce cas.
        let needsResend: Bool
    }

    static func mergeRemote(
        local: [GradeUnlock],
        localWelcomeDecided: Bool,
        remote: [GradeUnlock],
        remoteWelcomeDecided: Bool
    ) -> RemoteMerge {
        let normalizedRemote = normalized(remote)
        let merged = merge(local, normalizedRemote)
        let mergedWelcome = localWelcomeDecided || remoteWelcomeDecided
        return RemoteMerge(
            unlocks: merged,
            welcomeDecided: mergedWelcome,
            changesLocal: merged != local || mergedWelcome != localWelcomeDecided,
            needsResend: merged != normalizedRemote || mergedWelcome != remoteWelcomeDecided
        )
    }

    /// Ajoute les paliers manquants sous le plus haut acquis de chaque parcours (même date que ce
    /// dernier) : avoir le grade 4 suppose avoir franchi 1, 2 et 3, même si un enregistrement distant
    /// n'en portait qu'un. Résultat trié, donc comparable.
    static func normalized(_ unlocks: [GradeUnlock]) -> [GradeUnlock] {
        var byTrack: [GradeTrack: [Int: Date]] = [:]
        for unlock in unlocks {
            byTrack[unlock.track, default: [:]][unlock.tier] = unlock.date
        }
        var result: [GradeUnlock] = []
        for (track, tiers) in byTrack {
            guard let highest = tiers.keys.max() else { continue }
            for tier in 0...highest {
                let date = tiers[tier] ?? tiers[highest] ?? Date()
                result.append(GradeUnlock(track: track, tier: tier, date: date))
            }
        }
        return result.sorted { ($0.track.rawValue, $0.tier) < ($1.track.rawValue, $1.tier) }
    }

    /// Franchissements à enregistrer pour ce nombre : les paliers atteints qui ne sont pas encore
    /// acquis, datés de `date` sauf si `historicalDates` connaît la vraie date du palier. Vide si
    /// rien de nouveau.
    static func newUnlocks(
        count: Int,
        track: GradeTrack,
        existing: [GradeUnlock],
        date: Date,
        historicalDates: [Int: Date] = [:]
    ) -> [GradeUnlock] {
        let reached = reachedTierCount(count: count, track: track)
        let known = Set(existing.filter { $0.track == track }.map(\.tier))
        return (0..<reached).filter { !known.contains($0) }.map {
            GradeUnlock(track: track, tier: $0, date: historicalDates[$0] ?? date)
        }
    }

    /// Date réelle à laquelle chaque palier a été franchi, d'après les dates des événements (date
    /// d'ajout de chaque disque distinct, ou horodatage de chaque écoute) : le N-ième événement dans
    /// l'ordre chronologique est celui qui franchit le palier de seuil N. Jamais dans le futur
    /// (`now` plafonne une date d'ajout aberrante). Un palier qu'aucun événement n'atteint est absent.
    static func historicalDates(eventDates: [Date], track: GradeTrack, now: Date) -> [Int: Date] {
        let sorted = eventDates.sorted()
        var result: [Int: Date] = [:]
        for (tier, threshold) in track.thresholds.enumerated() where sorted.count >= threshold {
            result[tier] = min(sorted[threshold - 1], now)
        }
        return result
    }

    /// Faut-il fêter ce franchissement ? Non si le nombre a fait un saut trop grand depuis la dernière
    /// valeur connue (synchro en masse, import, premier lancement) : un grade « tombé d'un coup » ne
    /// se célèbre pas, il s'enregistre en silence. `previousCount` à `nil` : première évaluation.
    static func shouldCelebrate(previousCount: Int?, newCount: Int, track: GradeTrack) -> Bool {
        guard let previousCount, newCount > previousCount else { return false }
        return newCount - previousCount <= maxCelebratedJump(for: track)
    }

    static func maxCelebratedJump(for track: GradeTrack) -> Int {
        switch track {
        case .collection: 30
        case .listening: 10
        }
    }

    /// Grade à présenter à l'accueil : le plus haut indice acquis parmi les parcours, la collection
    /// l'emportant à égalité. `nil` si aucun grade n'est acquis.
    static func welcomeTarget(unlocks: [GradeUnlock]) -> (track: GradeTrack, tier: Int)? {
        var best: (track: GradeTrack, tier: Int)?
        for track in GradeTrack.allCases {
            guard let tier = unlocks.filter({ $0.track == track }).map(\.tier).max() else { continue }
            if tier > (best?.tier ?? Int.min) { best = (track, tier) }
        }
        return best
    }

    private struct Key: Hashable {
        let track: GradeTrack
        let tier: Int
    }
}
