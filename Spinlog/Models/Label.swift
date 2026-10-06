import Foundation

/// Fiche label, telle que renvoyée par `GET /labels/{id}`.
struct DiscogsLabel: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let profile: String?
    let images: [DiscogsImage]?
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id, name, profile, images
        case resourceURL = "resource_url"
    }

    var primaryImageURL: String? { images?.first?.uri }

    var discogsWebURL: URL? {
        URL(string: "https://www.discogs.com/label/\(id)")
    }
}
