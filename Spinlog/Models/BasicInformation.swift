import Foundation

/// Résumé d'une release tel qu'inclus dans les entrées de collection et de wantlist
/// (évite un aller-retour réseau supplémentaire pour afficher une liste).
struct BasicInformation: Decodable, Sendable {
    let id: Int
    let title: String
    let year: Int?
    let thumb: String?
    let coverImage: String?
    let genres: [String]?
    let styles: [String]?
    let artists: [ReleaseArtist]?
    let labels: [ReleaseLabel]?
    let formats: [ReleaseFormat]?
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id, title, year, thumb
        case coverImage = "cover_image"
        case genres, styles, artists, labels, formats
        case resourceURL = "resource_url"
    }

    var artistNames: String {
        (artists ?? []).map(\.name).joined(separator: ", ")
    }
}
