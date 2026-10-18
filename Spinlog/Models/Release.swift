import Foundation

struct ReleaseArtist: Codable, Sendable, Identifiable {
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

extension ReleaseArtist {
    init(name: String, id: Int = 0) {
        self.init(id: id, name: name, anv: nil, join: nil, role: nil, tracks: nil, resourceURL: nil)
    }
}

struct ReleaseLabel: Codable, Sendable, Identifiable {
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

struct ReleaseFormat: Codable, Sendable {
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

    /// Identifiant de vidéo YouTube extrait de l'URL Discogs (formats `youtu.be/{id}` et
    /// `youtube.com/watch?v={id}`), utilisé à la fois pour la miniature et la lecture intégrée.
    var youTubeVideoID: String? {
        guard let components = URLComponents(string: uri),
              let host = components.host, host.contains("youtu") else { return nil }
        let videoId: String?
        if host.contains("youtu.be") {
            videoId = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            videoId = components.queryItems?.first { $0.name == "v" }?.value
        }
        guard let videoId, !videoId.isEmpty else { return nil }
        return videoId
    }

    /// Miniature YouTube reconstruite à partir de l'identifiant de vidéo dans l'URL,
    /// l'API Discogs ne renvoyant pas d'image de miniature pour ses vidéos.
    var thumbnailURL: URL? {
        guard let youTubeVideoID else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(youTubeVideoID)/hqdefault.jpg")
    }

    var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        return duration.formattedAsMinutesSeconds
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
    let uri: String?
    /// Dossier Discogs de l'exemplaire d'origine (absent quand cette `Release` vient d'une
    /// simple recherche/fiche API, pas d'un exemplaire réellement possédé) — voir
    /// `ShelfPlacementService`, qui s'en sert pour restreindre "où ranger" au même dossier.
    /// La clé `folder_id` n'apparaît jamais dans la réponse `GET /releases/{id}` (notion propre
    /// à un exemplaire de collection, pas à une release) : `decodeIfPresent` (implicite pour tout
    /// type optionnel via la synthèse `Decodable`) donne alors simplement `nil`.
    let folderId: Int?

    private enum CodingKeys: String, CodingKey {
        case id, title, year, country, released, notes, genres, styles
        case artists, extraartists, labels, companies, identifiers, formats, images, tracklist, community, videos
        case numForSale = "num_for_sale"
        case lowestPrice = "lowest_price"
        case masterId = "master_id"
        case resourceURL = "resource_url"
        case uri
        case folderId = "folder_id"
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

    /// Forme canonique des noms d'artistes (nom brut, virgule systématique), identique à
    /// `BasicInformation.artistNames` : sert de clé de tri (ex. surcharges de tri par artiste)
    /// afin de rester cohérente quelle que soit la source (`CollectionItem` ou `Release` complet).
    /// `artistNames` reste réservé à l'affichage (ANV, jointure Discogs `join`).
    var sortArtistNames: String {
        (artists ?? []).map(\.name).joined(separator: ", ")
    }

    var discogsWebURL: URL? {
        if let uri, let url = URL(string: uri) {
            return url
        }
        return DiscogsConstants.websiteURL.appendingPathComponent("release/\(id)")
    }

    var primaryImageURL: String? {
        images?.first?.uri
    }

    /// Date de sortie de ce pressage précis (peut différer de `year`, l'année de sortie
    /// originale de l'œuvre), formatée pour l'affichage.
    var formattedReleasedDate: String? {
        guard let released, !released.isEmpty else { return nil }
        let formatter = DateFormatter()
        // Format fixe (dates Discogs) : locale POSIX, sans quoi un calendrier non grégorien
        // (bouddhiste, japonais…) réglé sur l'appareil fausse l'analyse.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: released) {
                let style: Date.FormatStyle = pattern == "yyyy"
                    ? .dateTime.year()
                    : (pattern == "yyyy-MM" ? .dateTime.month(.wide).year() : .dateTime.weekday(.wide).month(.wide).day().year())
                // Langue de l'appareil (le français était forcé, y compris dans l'interface anglaise).
                return date.formatted(style)
            }
        }
        return released
    }
}

extension Release {
    init(from item: CollectionItem) {
        let info = item.basicInformation
        var imgs: [DiscogsImage] = []
        if let cover = info.coverImage, !cover.isEmpty {
            imgs.append(DiscogsImage(type: "primary", uri: cover, uri150: info.thumb ?? cover))
        } else if let thumb = info.thumb, !thumb.isEmpty {
            imgs.append(DiscogsImage(type: "primary", uri: thumb, uri150: thumb))
        }

        self.init(
            id: item.releaseId,
            title: info.title,
            year: info.year,
            country: nil,
            released: nil,
            notes: nil,
            genres: info.genres,
            styles: info.styles,
            artists: info.artists,
            extraartists: nil,
            labels: info.labels,
            companies: nil,
            identifiers: nil,
            formats: info.formats,
            images: imgs,
            tracklist: nil,
            community: nil,
            videos: nil,
            numForSale: nil,
            lowestPrice: nil,
            masterId: info.masterId,
            resourceURL: info.resourceURL,
            uri: nil,
            folderId: item.folderId
        )
    }

    init(from info: BasicInformation) {
        var imgs: [DiscogsImage] = []
        if let cover = info.coverImage, !cover.isEmpty {
            imgs.append(DiscogsImage(type: "primary", uri: cover, uri150: info.thumb ?? cover))
        } else if let thumb = info.thumb, !thumb.isEmpty {
            imgs.append(DiscogsImage(type: "primary", uri: thumb, uri150: thumb))
        }

        self.init(
            id: info.id,
            title: info.title,
            year: info.year,
            country: nil,
            released: nil,
            notes: nil,
            genres: info.genres,
            styles: info.styles,
            artists: info.artists,
            extraartists: nil,
            labels: info.labels,
            companies: nil,
            identifiers: nil,
            formats: info.formats,
            images: imgs,
            tracklist: nil,
            community: nil,
            videos: nil,
            numForSale: nil,
            lowestPrice: nil,
            masterId: info.masterId,
            resourceURL: info.resourceURL,
            uri: nil,
            folderId: nil
        )
    }
}
