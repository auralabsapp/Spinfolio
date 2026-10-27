import Foundation

/// Ce que Réglages montre des outils d'achat selon ce que la personne possède : règles pures,
/// partagées par la page « À propos » et la recherche de Réglages, et testées.
nonisolated enum PremiumSettingsVisibility {
    /// « Gérer mon abonnement » : inutile pour qui n'a que l'achat à vie (rien à gérer). Reste visible
    /// si un abonnement est encore actif à côté, qu'Apple ne résilie pas après un achat à vie.
    static func showsSubscriptionManagement(hasLifetime: Bool, hasActiveSubscription: Bool) -> Bool {
        !hasLifetime || hasActiveSubscription
    }

    /// « Utiliser un code » : masqué pour qui a déjà Premium pour toujours, et pendant la démo (le
    /// Premium y est déjà offert, et la démo ne touche à aucun achat).
    static func showsCodeRedemption(hasLifetime: Bool, isDemoMode: Bool) -> Bool {
        !hasLifetime && !isDemoMode
    }
}
