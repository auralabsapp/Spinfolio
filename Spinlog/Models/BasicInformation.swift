import Foundation

/// Résumé d'une release tel qu'inclus dans les entrées de collection et de wantlist
/// (évite un aller-retour réseau supplémentaire pour afficher une liste).
struct BasicInformation: Codable, Sendable {
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
    let masterId: Int?

    private enum CodingKeys: String, CodingKey {
        case id, title, year, thumb
        case coverImage = "cover_image"
        case genres, styles, artists, labels, formats
        case resourceURL = "resource_url"
        case masterId = "master_id"
    }

    init(
        id: Int,
        title: String,
        year: Int?,
        thumb: String?,
        coverImage: String?,
        genres: [String]?,
        styles: [String]?,
        artists: [ReleaseArtist]?,
        labels: [ReleaseLabel]?,
        formats: [ReleaseFormat]?,
        resourceURL: String,
        masterId: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.thumb = thumb
        self.coverImage = coverImage
        self.genres = genres
        self.styles = styles
        self.artists = artists
        self.labels = labels
        self.formats = formats
        self.resourceURL = resourceURL
        self.masterId = masterId
    }

    nonisolated var artistNames: String {
        (artists ?? []).map(\.name).joined(separator: ", ")
    }
}

extension Release {
    var basicInformation: BasicInformation {
        BasicInformation(
            id: id,
            title: title,
            year: year,
            thumb: primaryImageURL,
            coverImage: primaryImageURL,
            genres: genres,
            styles: styles,
            artists: artists,
            labels: labels,
            formats: formats,
            resourceURL: resourceURL,
            masterId: masterId
        )
    }
}
