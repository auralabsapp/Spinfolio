import Foundation

/// Cote estimée d'un exemplaire (suggestion de prix Discogs pour l'état déclaré).
/// `staleSince` n'est renseignée que pour une cote de plus de 6 h, servie depuis le cache faute
/// de réseau : les CGU de l'API Discogs interdisent d'afficher du Content de plus de 6 h comme
/// s'il était à jour, l'interface doit donc afficher sa date plutôt que « Cote actuelle ».
nonisolated struct MarketEstimate: Equatable, Sendable {
    let price: Double
    let currency: String
    let staleSince: Date?

    /// Règle de lecture du cache, extraite pour être testée sans `LocalDataStore` :
    /// - cote de moins de 6 h pour le même état → réutilisée telle quelle ;
    /// - pas de requête possible (hors ligne, pas de session) → dernière cote connue, datée si
    ///   elle a plus de 6 h (même si l'état a changé depuis : mieux qu'aucune cote hors ligne) ;
    /// - sinon `nil` : l'appelant doit interroger Discogs.
    static func fromCache(
        price: Double,
        currency: String,
        date: Date,
        cachedCondition: String?,
        requestedCondition: String?,
        canFetch: Bool,
        now: Date = Date()
    ) -> MarketEstimate? {
        let isFresh = now.timeIntervalSince(date) < DiscogsConstants.sixHoursTTL
        if isFresh, cachedCondition == requestedCondition {
            return MarketEstimate(price: price, currency: currency, staleSince: nil)
        }
        guard !canFetch else { return nil }
        return MarketEstimate(price: price, currency: currency, staleSince: isFresh ? nil : date)
    }
}
