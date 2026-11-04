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

    /// Lecture tolérante : seul l'identifiant est indispensable. Un titre ou un lien manquant, une
    /// année reçue en texte, un artiste, label ou format atypique ne doivent pas faire perdre tout
    /// l'exemplaire (il disparaissait de la Collection et des Stats, alors que Discogs le compte).
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = container.lenientString(forKey: .title) ?? ""
        year = container.lenientInt(forKey: .year)
        thumb = container.lenientString(forKey: .thumb)
        coverImage = container.lenientString(forKey: .coverImage)
        genres = try? container.decodeIfPresent([String].self, forKey: .genres)
        styles = try? container.decodeIfPresent([String].self, forKey: .styles)
        artists = (try? container.decodeIfPresent(LossyArray<ReleaseArtist>.self, forKey: .artists))??.elements
        labels = (try? container.decodeIfPresent(LossyArray<ReleaseLabel>.self, forKey: .labels))??.elements
        formats = (try? container.decodeIfPresent(LossyArray<ReleaseFormat>.self, forKey: .formats))??.elements
        resourceURL = container.lenientString(forKey: .resourceURL) ?? ""
        masterId = container.lenientInt(forKey: .masterId)
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

/// Lectures tolérantes des champs Discogs, dont le type varie parfois d'un enregistrement à
/// l'autre (nombre reçu en texte et inversement, valeur nulle) : `nil` plutôt qu'une erreur.
extension KeyedDecodingContainer {
    nonisolated func lenientString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    nonisolated func lenientInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
