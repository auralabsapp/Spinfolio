import Foundation

/// Geste discret qui affiche ou masque le diagnostic d'abonnement : 7 touchers rapprochés sur la
/// ligne « Version » de « À propos ». Règle pure, testée dans `SubscriptionDiagnosticUnlockTests`.
nonisolated struct SubscriptionDiagnosticUnlock {
    static let defaultsKey = "com.spinlog.subscriptionDiagnosticUnlocked"
    static let requiredTaps = 7
    /// Au-delà de cet écart entre deux touchers, le décompte repart de zéro.
    static let maximumInterval: TimeInterval = 1.0

    private var count = 0
    private var lastTap: Date?

    /// Enregistre un toucher ; `true` au 7e toucher rapproché (le décompte repart ensuite de zéro).
    mutating func registerTap(at date: Date = Date()) -> Bool {
        if let lastTap, date.timeIntervalSince(lastTap) <= Self.maximumInterval {
            count += 1
        } else {
            count = 1
        }
        lastTap = date
        guard count >= Self.requiredTaps else { return false }
        count = 0
        lastTap = nil
        return true
    }
}
