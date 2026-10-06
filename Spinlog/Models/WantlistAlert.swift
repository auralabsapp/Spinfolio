import Foundation

/// Modèle d'alerte de prix pour un disque en Wantlist.
struct WantlistAlert: Codable, Identifiable, Equatable, Sendable {
    let releaseId: Int
    var albumTitle: String
    var artistName: String
    var coverURL: String?
    /// Prix maximum souhaité par l'utilisateur
    var targetPrice: Double
    /// Devise du prix cible (ex: "EUR", "USD")
    var currency: String
    var createdAt: Date
    var lastCheckedAt: Date?
    /// Dernier prix ayant déjà déclenché une notification (évite de spammer si le prix ne baisse pas plus)
    var lastNotifiedPrice: Double?
    /// Dernier prix le plus bas constaté
    var currentLowestPrice: Double?
    /// Devise du dernier prix constaté
    var currentLowestPriceCurrency: String?
    /// Nombre d'exemplaires actuellement en vente
    var currentNumForSale: Int?

    var id: Int { releaseId }

    /// Indique si une offre à un prix inférieur ou égal au prix cible est actuellement disponible
    var isTriggered: Bool {
        guard let currentLowestPrice else { return false }
        return currentLowestPrice <= targetPrice
    }
}
