import Foundation

/// Estimation de la cote actuelle d'une release, à partir des suggestions de prix Discogs pour
/// l'état renseigné (ou de leur moyenne si l'état est inconnu ou non trouvé).
enum MarketEstimateService {
    /// Throttlé via `ReleasePriceSnapshot` : règle de lecture du cache dans
    /// `MarketEstimate.fromCache` (cote de moins de 6 h réutilisée, cote plus ancienne seulement
    /// hors ligne et alors datée, car les CGU de l'API Discogs interdisent d'afficher du Content
    /// de plus de 6 h comme à jour).
    static func estimate(releaseId: Int, condition: String?) async -> MarketEstimate? {
        // Démo : cote d'exemple, jamais enregistrée dans le cache des cotes (partagé entre
        // comptes), qui la resservirait sinon au vrai compte connecté ensuite.
        if DemoMode.isActive {
            return DemoServer.exampleMarketEstimate(releaseId: releaseId)
        }
        let localStore = LocalDataStore.shared
        let credentials = NetworkMonitor.shared.isConnected ? DiscogsAuthManager.shared.credentials : nil

        if let cached = localStore.latestReleasePriceSnapshot(releaseId: releaseId),
           let estimate = MarketEstimate.fromCache(
               price: cached.medianPrice,
               currency: cached.currency,
               date: cached.date,
               cachedCondition: cached.condition,
               requestedCondition: condition,
               canFetch: credentials != nil
           ) {
            return estimate
        }

        guard let credentials,
              let suggestions = try? await DiscogsAPIClient.shared.priceSuggestions(releaseId: releaseId, credentials: credentials),
              !suggestions.isEmpty else {
            return nil
        }

        let price: MarketplacePrice
        if let condition, let matched = suggestions[condition] {
            price = matched
        } else {
            // Moyenne des suggestions disponibles : Discogs renvoie systématiquement toutes les
            // suggestions d'une même release dans une seule et même devise.
            let currency = suggestions.values.first?.currency ?? "USD"
            let average = suggestions.values.map(\.value).reduce(0, +) / Double(suggestions.count)
            price = MarketplacePrice(currency: currency, value: average)
        }

        localStore.saveReleasePriceSnapshot(releaseId: releaseId, currency: price.currency, medianPrice: price.value, condition: condition)
        return MarketEstimate(price: price.value, currency: price.currency, staleSince: nil)
    }
}
