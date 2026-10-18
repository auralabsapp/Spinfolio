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
    /// Référence catalogue (ex. "XYZ-001"), souvent le meilleur repère pour distinguer deux
    /// pressages Discogs partageant le même code-barres.
    let catno: String?
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id, type, title, thumb
        case coverImage = "cover_image"
        case year, genre, style, format, label, country, catno
        case resourceURL = "resource_url"
    }

    init(
        id: Int,
        type: String,
        title: String,
        thumb: String? = nil,
        coverImage: String? = nil,
        year: String? = nil,
        genre: [String]? = nil,
        style: [String]? = nil,
        format: [String]? = nil,
        label: [String]? = nil,
        country: String? = nil,
        catno: String? = nil,
        resourceURL: String = ""
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.thumb = thumb
        self.coverImage = coverImage
        self.year = year
        self.genre = genre
        self.style = style
        self.format = format
        self.label = label
        self.country = country
        self.catno = catno
        self.resourceURL = resourceURL
    }

    init(from basicInfo: BasicInformation) {
        let artistNames = basicInfo.artistNames
        let fullTitle = artistNames.isEmpty ? basicInfo.title : "\(artistNames) - \(basicInfo.title)"
        self.init(
            id: basicInfo.id,
            type: "release",
            title: fullTitle,
            thumb: basicInfo.thumb,
            coverImage: basicInfo.coverImage,
            year: basicInfo.year.map(String.init),
            genre: basicInfo.genres,
            style: basicInfo.styles,
            format: basicInfo.formats?.map(\.name),
            label: basicInfo.labels?.map(\.name),
            country: nil,
            resourceURL: basicInfo.resourceURL
        )
    }

    var isRelease: Bool { type == "release" || type == "master" }
}

struct SearchResponse: Decodable {
    let pagination: Pagination
    let results: [SearchResult]
}
