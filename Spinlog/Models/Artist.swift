import Foundation

/// Fiche artiste, telle que renvoyée par `GET /artists/{id}`.
struct Artist: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let profile: String?
    let images: [DiscogsImage]?
    let members: [ArtistMember]?
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id, name, profile, images, members
        case resourceURL = "resource_url"
    }

    var primaryImageURL: String? {
        images?.first?.uri
    }

    var discogsWebURL: URL? {
        DiscogsConstants.websiteURL.appendingPathComponent("artist/\(id)")
    }
}

struct ArtistMember: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let active: Bool?
}
