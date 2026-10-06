import Foundation

/// Prix marketplace avec sa devise (`GET /marketplace/stats/{id}` et `/price_suggestions/{id}`
/// renvoient chacun leur propre devise, pas nécessairement la même que celle du compte).
struct MarketplacePrice: Codable, Sendable {
    let currency: String
    let value: Double

    var formatted: String {
        value.formatted(.currency(code: currency))
    }

    private enum CodingKeys: String, CodingKey {
        case currency, value
    }

    init(currency: String, value: Double) {
        self.currency = currency
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.currency = try container.decode(String.self, forKey: .currency)
        if let d = try? container.decode(Double.self, forKey: .value) {
            self.value = d
        } else if let s = try? container.decode(String.self, forKey: .value), let d = Double(s.replacingOccurrences(of: ",", with: ".")) {
            self.value = d
        } else if let i = try? container.decode(Int.self, forKey: .value) {
            self.value = Double(i)
        } else {
            self.value = 0.0
        }
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

/// Réponse de `GET /users/{username}/collection/value` : estimation globale de la collection
/// basée sur l'historique réel des ventes marketplace Discogs (pas juste les annonces en cours).
/// Chaque fourchette est une chaîne déjà formatée avec le symbole de devise par Discogs
/// (ex: "$960.00"), dans la devise configurée sur le compte de l'utilisateur.
struct CollectionValueResponse: Decodable, Sendable {
    let minimum: String
    let median: String
    let maximum: String
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

