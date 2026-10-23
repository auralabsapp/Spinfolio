import Foundation

/// Mouvement d'un support qui tourne sur la platine : il démarre en accélérant jusqu'à sa vitesse de
/// croisière, tourne, puis ralentit jusqu'à l'arrêt quand l'écoute s'arrête. La vitesse varie
/// linéairement pendant le démarrage et l'arrêt, donc l'angle suit une parabole, puis une droite.
/// Calculé en fonction du temps (pas d'état animé) : une vue `TimelineView` lit l'angle à chaque image.
nonisolated struct SpinProfile: Equatable, Sendable {
    /// Vitesse de croisière, en degrés par seconde (un 33 tours : 200°/s).
    let omega: Double
    /// Temps pour atteindre la vitesse de croisière, en secondes.
    var startupDuration: Double = 1.3
    /// Temps pour s'arrêter depuis la vitesse de croisière (moins si l'arrêt vient pendant le démarrage).
    var stopDuration: Double = 1.6
    let startTime: TimeInterval
    /// Instant où l'écoute s'arrête (`nil` tant qu'elle dure).
    var stopTime: TimeInterval?

    /// Angle cumulé en degrés à cet instant (jamais négatif, constant une fois arrêté).
    func angle(at time: TimeInterval) -> Double {
        let elapsed = time - startTime
        guard let stopTime, time >= stopTime else { return runningAngle(elapsed: elapsed) }

        let stopElapsed = stopTime - startTime
        let speedAtStop = omega * speedFactor(elapsed: stopElapsed)
        let angleAtStop = runningAngle(elapsed: stopElapsed)
        guard speedAtStop > 0 else { return angleAtStop }

        // Le temps de ralentissement est proportionnel à la vitesse atteinte.
        let duration = stopDuration * (speedAtStop / omega)
        let sinceStop = time - stopTime
        if sinceStop >= duration { return angleAtStop + speedAtStop * duration / 2 }
        return angleAtStop + speedAtStop * (sinceStop - sinceStop * sinceStop / (2 * duration))
    }

    /// Le support est définitivement immobile : la `TimelineView` peut s'arrêter de redessiner.
    func isSettled(at time: TimeInterval) -> Bool {
        guard let stopTime else { return false }
        return time >= stopTime + stopDuration
    }

    // MARK: - Détails

    /// Vitesse relative (0…1) après `elapsed` secondes de démarrage.
    private func speedFactor(elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        return min(1, elapsed / startupDuration)
    }

    /// Angle sans arrêt : parabole pendant le démarrage, puis tour à vitesse constante.
    private func runningAngle(elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        if elapsed < startupDuration {
            return omega * elapsed * elapsed / (2 * startupDuration)
        }
        return omega * (elapsed - startupDuration / 2)
    }
}
