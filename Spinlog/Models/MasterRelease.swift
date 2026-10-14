import Foundation

/// Fiche "master" (regroupe toutes les versions/pressages d'une même œuvre),
/// telle que renvoyée par `GET /masters/{id}`.
struct MasterRelease: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let year: Int?
    let genres: [String]?
    let styles: [String]?
    let artists: [ReleaseArtist]?
    let images: [DiscogsImage]?
    let tracklist: [Track]?
    let mainRelease: Int?
    let versionsURL: String?
    let numForSale: Int?
    let lowestPrice: Double?
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id, title, year, genres, styles, artists, images, tracklist
        case mainRelease = "main_release"
        case versionsURL = "versions_url"
        case numForSale = "num_for_sale"
        case lowestPrice = "lowest_price"
        case resourceURL = "resource_url"
    }

    var artistNames: String {
        (artists ?? []).map(\.name).joined(separator: ", ")
    }

    var primaryImageURL: String? {
        images?.first?.uri
    }

    var discogsWebURL: URL? {
        DiscogsConstants.websiteURL.appendingPathComponent("master/\(id)")
    }
}

/// Un pressage/édition d'un master, tel que listé par `GET /masters/{id}/versions`.
struct MasterVersion: Decodable, Identifiable, Sendable {
    let id: Int
    let label: String?
    let catno: String?
    let format: String?
    let country: String?
    let released: String?
    let thumb: String?
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id, label, catno, format, country, released, thumb
        case resourceURL = "resource_url"
    }
}

struct MasterVersionsResponse: Decodable {
    let pagination: Pagination
    let versions: [MasterVersion]
}
