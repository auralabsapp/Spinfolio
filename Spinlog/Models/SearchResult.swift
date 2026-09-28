import Foundation

/// Un résultat de `GET /database/search`. Le catalogue Discogs mélange releases, masters,
/// artistes et labels dans une seule liste distinguée par `type`.
struct SearchResult: Decodable, Identifiable, Sendable {
    let id: Int
    let type: String
    let title: String
    let thumb: String?
    let coverImage: String?
    let year: String?
    let genre: [String]?
    let style: [String]?
    let format: [String]?
    let label: [String]?
    let country: String?
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id, type, title, thumb
        case coverImage = "cover_image"
        case year, genre, style, format, label, country
        case resourceURL = "resource_url"
    }

    var isRelease: Bool { type == "release" || type == "master" }
    var isArtist: Bool { type == "artist" }
    var isLabel: Bool { type == "label" }
}

struct SearchResponse: Decodable {
    let pagination: Pagination
    let results: [SearchResult]
}
