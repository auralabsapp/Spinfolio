import Foundation

/// Fréquence du paywall présenté après la connexion : dès la première connexion, puis au plus une
/// fois par semaine. L'afficher à chaque ouverture lassait les utilisateurs gratuits (et un paywall
/// systématique est un motif courant de remarque en App Review) ; l'offre reste accessible à
/// tout moment depuis Réglages et les fonctions Premium verrouillées.
enum LaunchPaywallSchedule {
    private static let lastShownKey = "launchPaywallLastShownAt"
    private static let minimumInterval: TimeInterval = 7 * 24 * 3600

    /// Règle de présentation : seulement une fois connecté (compte ou démo), sans abonnement réel,
    /// et si la dernière présentation remonte à plus d'une semaine.
    /// `hasSubscription` : accès Premium hors aperçu de la démo (`PremiumStore.hasAccessOutsideDemo`).
    static func shouldPresent(
        isAuthenticated: Bool,
        hasSubscription: Bool,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        isAuthenticated && !hasSubscription && isDue(now: now, defaults: defaults)
    }

    static func isDue(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        let lastShown = defaults.double(forKey: lastShownKey)
        guard lastShown > 0 else { return true }
        return now.timeIntervalSince1970 - lastShown >= minimumInterval
    }

    static func markShown(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: lastShownKey)
    }
}
