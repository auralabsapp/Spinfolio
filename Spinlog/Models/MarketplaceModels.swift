import Foundation

/// Prix marketplace avec sa devise (`GET /marketplace/stats/{id}` et `/price_suggestions/{id}`
/// renvoient chacun leur propre devise, pas nécessairement la même que celle du compte).
struct MarketplacePrice: Decodable, Sendable {
    let currency: String
    let value: Double

    var formatted: String {
        value.formatted(.currency(code: currency))
    }
}

/// Réponse de `GET /marketplace/stats/{release_id}`.
struct MarketplaceStats: Decodable, Sendable {
    let lowestPrice: MarketplacePrice?
    let numForSale: Int?
    let blockedFromSale: Bool?

    private enum CodingKeys: String, CodingKey {
        case lowestPrice = "lowest_price"
        case numForSale = "num_for_sale"
        case blockedFromSale = "blocked_from_sale"
    }
}

/// Ordre canonique des états de disque Discogs, pour afficher les estimations de
/// `GET /marketplace/price_suggestions/{release_id}` dans un ordre cohérent (le moins bon état
/// vers le meilleur — endpoint qui renvoie un objet libre, une entrée par état présent).
enum MediaCondition: String, CaseIterable {
    case mint = "Mint (M)"
    case nearMint = "Near Mint (NM or M-)"
    case veryGoodPlus = "Very Good Plus (VG+)"
    case veryGood = "Very Good (VG)"
    case goodPlus = "Good Plus (G+)"
    case good = "Good (G)"
    case fair = "Fair (F)"
    case poor = "Poor (P)"
}
