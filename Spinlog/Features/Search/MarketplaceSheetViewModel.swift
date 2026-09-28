import Foundation

@Observable
@MainActor
final class MarketplaceSheetViewModel {
    private(set) var stats: MarketplaceStats?
    private(set) var suggestions: [String: MarketplacePrice] = [:]
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    /// Ordonne les états connus dans l'ordre canonique Discogs, puis ajoute à la fin
    /// d'éventuelles clés inattendues renvoyées par l'API.
    var orderedSuggestions: [(String, MarketplacePrice)] {
        let known = MediaCondition.allCases.map(\.rawValue)
        var result: [(String, MarketplacePrice)] = []
        for condition in known {
            if let price = suggestions[condition] {
                result.append((condition, price))
            }
        }
        for (key, price) in suggestions where !known.contains(key) {
            result.append((key, price))
        }
        return result
    }

    func load(releaseId: Int) async {
        isLoading = true
        errorMessage = nil
        do {
            stats = try await DiscogsAPIClient.shared.marketplaceStats(
                releaseId: releaseId, credentials: DiscogsAuthManager.shared.credentials
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        if let credentials = DiscogsAuthManager.shared.credentials,
           let result = try? await DiscogsAPIClient.shared.priceSuggestions(releaseId: releaseId, credentials: credentials) {
            suggestions = result
        }
        isLoading = false
    }
}
