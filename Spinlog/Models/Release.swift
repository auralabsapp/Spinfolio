import Foundation

struct ReleaseArtist: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    /// Variante du nom utilisée spécifiquement sur ce pressage (souvent identique à `name`).
    let anv: String?
    /// Comment enchaîner ce nom avec le suivant dans une liste d'artistes (ex: "&", "Featuring").
    let join: String?
    let role: String?
    /// Pour un crédit : à quels titres précis il s'applique (ex: "A1 à A5"). Absent si global.
    let tracks: String?
    let resourceURL: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, anv, join, role, tracks
        case resourceURL = "resource_url"
    }

    var displayName: String {
        guard let anv, !anv.isEmpty else { return name }
        return anv
    }
}

struct ReleaseLabel: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let catno: String?
    let resourceURL: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, catno
        case resourceURL = "resource_url"
    }
}

/// Société liée à la fabrication/diffusion (pressage, distribution, mastering...),
/// distincte de `ReleaseLabel` (le label musical à proprement parler).
struct ReleaseCompany: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let entityTypeName: String?
    let resourceURL: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case entityTypeName = "entity_type_name"
        case resourceURL = "resource_url"
    }
}

/// Identifiant du pressage : code-barres, numéro de matrice/runout, société de gestion
/// des droits, etc.
struct ReleaseIdentifier: Decodable, Sendable, Identifiable {
    let type: String
    let value: String
    let description: String?

    var id: String { type + value }
}

struct ReleaseFormat: Decodable, Sendable {
    let name: String
    let qty: String?
    /// Précision libre en plus de `descriptions` (ex: "Gatefold", "Clear Vinyl").
    let text: String?
    let descriptions: [String]?
}

struct Track: Decodable, Sendable, Identifiable {
    let position: String
    let title: String
    let duration: String?
    /// "heading" pour un simple intitulé de section (ex: "Côté A") sans piste jouable.
    let typeName: String?
    /// Crédits spécifiques à ce titre (ex: featuring sur une seule chanson).
    let extraartists: [ReleaseArtist]?
    /// Pistes imbriquées (ex: medleys).
    let subTracks: [Track]?

    var id: String { position + title }
    var isHeading: Bool { typeName == "heading" }

    private enum CodingKeys: String, CodingKey {
        case position, title, duration, extraartists
        case typeName = "type_"
        case subTracks = "sub_tracks"
    }
}

struct Rating: Decodable, Sendable {
    let average: Double
    let count: Int
}

struct Community: Decodable, Sendable {
    let have: Int
    let want: Int
    let rating: Rating?
}

/// Vidéo associée à une release (généralement un lien YouTube), telle que renvoyée par l'API.
struct ReleaseVideo: Decodable, Sendable, Identifiable {
    let uri: String
    let title: String
    let description: String?
    let duration: Int?

    var id: String { uri }

    /// Miniature YouTube reconstruite à partir de l'identifiant de vidéo dans l'URL,
    /// l'API Discogs ne renvoyant pas d'image de miniature pour ses vidéos.
    var thumbnailURL: URL? {
        guard let components = URLComponents(string: uri),
              let host = components.host, host.contains("youtu") else { return nil }
        let videoId: String?
        if host.contains("youtu.be") {
            videoId = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            videoId = components.queryItems?.first { $0.name == "v" }?.value
        }
        guard let videoId, !videoId.isEmpty else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg")
    }

    var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        return String(format: "%d:%02d", duration / 60, duration % 60)
    }
}

/// Fiche complète d'une release, telle que renvoyée par `GET /releases/{id}`.
struct Release: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let year: Int?
    let country: String?
    let released: String?
    let notes: String?
    let genres: [String]?
    let styles: [String]?
    let artists: [ReleaseArtist]?
    let extraartists: [ReleaseArtist]?
    let labels: [ReleaseLabel]?
    let companies: [ReleaseCompany]?
    let identifiers: [ReleaseIdentifier]?
    let formats: [ReleaseFormat]?
    let images: [DiscogsImage]?
    let tracklist: [Track]?
    let community: Community?
    let videos: [ReleaseVideo]?
    let numForSale: Int?
    let lowestPrice: Double?
    let masterId: Int?
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id, title, year, country, released, notes, genres, styles
        case artists, extraartists, labels, companies, identifiers, formats, images, tracklist, community, videos
        case numForSale = "num_for_sale"
        case lowestPrice = "lowest_price"
        case masterId = "master_id"
        case resourceURL = "resource_url"
    }

    /// Enchaîne les noms d'artistes avec leur séparateur Discogs (`join`, ex: "&", "Featuring")
    /// plutôt qu'une simple virgule systématique.
    var artistNames: String {
        guard let artists, !artists.isEmpty else { return "" }
        var result = ""
        for (index, artist) in artists.enumerated() {
            result += artist.displayName
            if index < artists.count - 1 {
                let join = artist.join?.trimmingCharacters(in: .whitespaces) ?? ""
                result += join.isEmpty ? ", " : " \(join) "
            }
        }
        return result
    }

    var primaryImageURL: String? {
        images?.first?.uri
    }

    /// Date de sortie de ce pressage précis (peut différer de `year`, l'année de sortie
    /// originale de l'œuvre), formatée pour l'affichage.
    var formattedReleasedDate: String? {
        guard let released, !released.isEmpty else { return nil }
        let formatter = DateFormatter()
        for pattern in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: released) {
                let style: Date.FormatStyle = pattern == "yyyy"
                    ? .dateTime.year()
                    : (pattern == "yyyy-MM" ? .dateTime.month(.wide).year() : .dateTime.weekday(.wide).month(.wide).day().year())
                return date.formatted(style.locale(Locale(identifier: "fr_FR")))
            }
        }
        return released
    }
}
