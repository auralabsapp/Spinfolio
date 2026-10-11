import Foundation
import MusicKit
import OSLog

private let logger = Logger(subsystem: "com.auralabs.Spinlog", category: "AppleMusicArtistArtwork")

/// Les 4 sections de discographie qu'Apple Music distingue nativement pour un artiste —
/// contrairement à Discogs, qui ne donne aucun moyen fiable de séparer un album studio d'un
/// single/EP/live/compilation (voir la vue "full-albums" vs "compilation-albums" etc. de
/// l'API Apple Music). Les valeurs brutes sont les noms exacts des vues Apple Music
/// (`/v1/catalog/{storefront}/artists/{id}/view/{rawValue}`).
enum DiscographySection: String, CaseIterable, Identifiable {
    case albums = "full-albums"
    case singlesAndEPs = "singles"
    case liveAlbums = "live-albums"
    case compilations = "compilation-albums"

    var id: String { rawValue }
}

/// Résumé minimal d'un album Apple Music tel que renvoyé par les vues de discographie d'un
/// artiste — juste de quoi rapprocher par titre avec la collection locale, pour départager des
/// homonymes (voir `bestCandidate`).
struct AppleMusicAlbumSummary: Identifiable, Sendable {
    let id: String
    let name: String
    let artistName: String
    let releaseDate: String?
    let artworkURL: URL?
}

/// Récupère des informations sur un artiste depuis le catalogue Apple Music (MusicKit) : sa photo
/// (classement "Artistes les plus écoutés" des Stats, en-tête de `ArtistDetailView`), son nom et
/// sa biographie (`ArtistDetailView`). En cas de refus de permission, d'absence de résultat ou
/// d'erreur réseau, les méthodes renvoient `nil` sans lever d'erreur : à l'appelant de choisir
/// l'état à afficher (simple absence de vignette ou de biographie).
@MainActor
final class AppleMusicArtistArtworkService {
    static let shared = AppleMusicArtistArtworkService()

    /// Artiste Apple Music retenu pour un nom donné (clé : `normalizeKey`). Seules les réponses
    /// définitives sont mémorisées — trouvé, ou aucun homonyme exact au catalogue. Une erreur
    /// réseau ou une autorisation refusée n'est jamais mise en cache, pour qu'un nouvel essai
    /// reste possible pendant la session.
    private var artistCache: [String: MusicKit.Artist?] = [:]
    /// Homonymes exacts trouvés au catalogue pour un nom (même clé que `artistCache`).
    private var candidatesCache: [String: [MusicKit.Artist]] = [:]
    /// Noms pour lesquels le choix entre plusieurs homonymes a déjà été fait à partir des
    /// albums de l'utilisateur (voir `prepareArtist`) : ce choix ne doit plus être remplacé.
    private var disambiguatedKeys: Set<String> = []
    /// Les caches suivants sont indexés par identifiant d'artiste Apple Music, pas par nom : si
    /// la résolution d'un nom change (homonyme mieux choisi), ils restent valables d'office.
    private var albumsCache: [String: [AppleMusicAlbumSummary]] = [:]
    private var editorialNotesCache: [String: String?] = [:]
    private var hasRequestedAuthorization = false

    private init() {}

    /// À appeler avant les autres méthodes quand on connaît des titres d'albums de l'artiste
    /// (sa collection/wantlist locale) : s'il existe plusieurs artistes Apple Music portant
    /// exactement ce nom (ex. plusieurs groupes « Ghost »), retient celui dont la discographie
    /// recoupe le mieux ces titres, au lieu du premier résultat de recherche.
    func prepareArtist(named artistName: String, knownAlbumTitles: Set<String>) async {
        _ = await resolvedArtist(for: artistName, knownAlbumTitles: knownAlbumTitles)
    }

    /// Nom de l'artiste tel qu'écrit au catalogue Apple Music (casse, accents, ponctuation
    /// d'origine), `nil` si l'artiste n'y est pas trouvé.
    func catalogName(for artistName: String) async -> String? {
        await resolvedArtist(for: artistName)?.name
    }

    /// Page de l'artiste sur Apple Music (music.apple.com) : s'ouvre dans l'app Musique et sert
    /// de lien de partage. `nil` si l'artiste n'y est pas trouvé.
    func catalogURL(for artistName: String) async -> URL? {
        await resolvedArtist(for: artistName)?.url
    }

    /// `size` : dimension (largeur = hauteur) demandée à Apple Music, en points. Par défaut une
    /// petite vignette (classement Stats) ; `ArtistDetailView` demande une taille plus grande
    /// pour son en-tête. Pas de cache dédié : l'URL se déduit sans réseau de l'artiste résolu.
    func artworkURL(for artistName: String, size: Int = 160) async -> URL? {
        await resolvedArtist(for: artistName)?.artwork?.url(width: size, height: size)
    }

    /// Plafond de sécurité de la pagination : au-delà, la liste est tronquée plutôt que de
    /// multiplier les requêtes pour un artiste au catalogue démesuré (rééditions, compilations).
    private static let maxAlbumsPerSection = 500

    /// Toutes les pages de la vue de discographie (100 albums par page, en suivant le lien
    /// `next` de la réponse) : une seule page tronquait les artistes très prolifiques.
    private func fetchAlbums(artistID: MusicItemID, section: DiscographySection, artworkSize: Int) async throws -> [AppleMusicAlbumSummary] {
        let key = "\(artistID.rawValue)_\(section.rawValue)_\(artworkSize)"
        if let cached = albumsCache[key] {
            return cached
        }
        let countryCode = try await MusicDataRequest.currentCountryCode
        var nextPath: String? = "/v1/catalog/\(countryCode)/artists/\(artistID.rawValue)/view/\(section.rawValue)?limit=100"
        var albums: [AppleMusicAlbumSummary] = []
        while let path = nextPath, albums.count < Self.maxAlbumsPerSection {
            guard let url = URL(string: "https://api.music.apple.com" + path) else {
                throw URLError(.badURL)
            }
            let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
            let decoded = try JSONDecoder().decode(AlbumsViewResponse.self, from: response.data)
            albums += decoded.data.map { item -> AppleMusicAlbumSummary in
                AppleMusicAlbumSummary(
                    id: item.id,
                    name: item.attributes.name,
                    artistName: item.attributes.artistName,
                    releaseDate: item.attributes.releaseDate,
                    artworkURL: item.attributes.artwork.flatMap { Self.artworkURL(fromTemplate: $0.url, size: artworkSize) }
                )
            }
            nextPath = decoded.next
        }
        albumsCache[key] = albums
        return albums
    }

    /// Note éditoriale Apple Music sur cet artiste (biographie courte rédigée par Apple), quand
    /// elle existe — contrairement aux vues de discographie, ce n'est exposé par aucune propriété
    /// typée de `MusicKit.Artist`, d'où l'appel `MusicDataRequest` brut vers la fiche catalogue de
    /// l'artiste. `nil` si l'artiste n'est pas trouvé, n'a pas de note éditoriale, ou en cas
    /// d'erreur : l'appelant n'affiche alors simplement pas de biographie.
    func editorialNotes(for artistName: String) async -> String? {
        guard let artist = await resolvedArtist(for: artistName) else { return nil }
        let key = artist.id.rawValue
        if let cached = editorialNotesCache[key] {
            return cached
        }
        do {
            let countryCode = try await MusicDataRequest.currentCountryCode
            guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(countryCode)/artists/\(artist.id.rawValue)") else {
                return nil
            }
            let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
            let decoded = try JSONDecoder().decode(ArtistResourceResponse.self, from: response.data)
            let notes = decoded.data.first?.attributes.editorialNotes
            let text = notes?.standard ?? notes?.short
            // Mémorisé même si `nil` : l'absence de note éditoriale est une réponse définitive.
            editorialNotesCache[key] = text
            return text
        } catch {
            logger.error("Récupération de la biographie échouée pour \(artistName, privacy: .public) : \(error, privacy: .public)")
            return nil
        }
    }

    /// Retire les suffixes d'homonymie de Discogs (« Ghost (32) » → « Ghost ») : ils n'existent
    /// pas côté Apple Music et faussaient la recherche d'artiste.
    static func strippingDiscogsDisambiguation(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(\d+\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Forme comparable d'un nom d'artiste entre Discogs et Apple Music : sans suffixe
    /// d'homonymie, accents, casse, article « The » initial ni ponctuation, avec « & » = « and ».
    static func comparableArtistName(_ name: String) -> String {
        var result = strippingDiscogsDisambiguation(name)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
        if result.hasPrefix("the ") {
            result.removeFirst(4)
        }
        return String(result.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Mots qui signalent une simple variante d'édition d'un même album, pas un autre album.
    private static let editionKeywords = "deluxe|remaster\\w*|edition|expanded|anniversary|version|explicit|clean|bonus|mono|stereo|reissue|single|ep"

    /// Normalise un titre pour rapprocher les éditions d'un même album, entre Discogs et Apple
    /// Music comme au sein d'Apple Music (Deluxe, Explicit, remasterisée…) : accents, casse,
    /// ponctuation, « & » = « and », article « The » initial, et mentions d'édition entre
    /// parenthèses/crochets (« (Remastered) », « [Deluxe Edition] ») ou après un tiret
    /// (« - Single », « - 20th Anniversary Edition »). Les autres parenthèses sont conservées :
    /// « Weezer (Blue Album) » et « Weezer (Green Album) » restent deux albums distincts.
    static func normalizeTitle(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = folded
            .replacingOccurrences(
                of: "\\s*[\\(\\[][^\\)\\]]*\\b(\(editionKeywords))\\b[^\\)\\]]*[\\)\\]]",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\s+[-–—]\\s+[^-–—]*\\b(\(editionKeywords))\\b[^-–—]*$",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&", with: " and ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("the ") {
            result.removeFirst(4)
        }
        let key = String(result.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        // Titre réduit à rien (ex. « (Deluxe) ») : on garde au moins sa forme brute comparable.
        return key.isEmpty ? String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }) : key
    }

    /// Les gabarits d'URL d'artwork Apple Music contiennent des espaces réservés littéraux
    /// `{w}`/`{h}` à remplacer par une taille en pixels avant usage.
    private static func artworkURL(fromTemplate template: String, size: Int) -> URL? {
        let resolved = template
            .replacingOccurrences(of: "{w}", with: String(size))
            .replacingOccurrences(of: "{h}", with: String(size))
        return URL(string: resolved)
    }

    private static func normalizeKey(_ name: String) -> String {
        comparableArtistName(name)
    }

    /// Artiste Apple Music correspondant à un nom Discogs. Ne retient que les résultats dont le
    /// nom correspond exactement (forme comparable) : prendre le premier résultat de recherche,
    /// même approchant, affichait parfois la photo, la bio et la discographie d'un autre artiste.
    /// En cas d'homonymes exacts, `knownAlbumTitles` (titres normalisés, voir `normalizeTitle`)
    /// permet de départager ; sans ces indices, le premier homonyme est retenu.
    private func resolvedArtist(for artistName: String, knownAlbumTitles: Set<String> = []) async -> MusicKit.Artist? {
        let key = Self.normalizeKey(artistName)
        guard !key.isEmpty else { return nil }
        if let cached = artistCache[key] {
            // Choix déjà définitif : départagé avec des indices, sans indice à exploiter, ou
            // sans homonyme à départager.
            if knownAlbumTitles.isEmpty || disambiguatedKeys.contains(key) || (candidatesCache[key]?.count ?? 0) <= 1 {
                return cached
            }
        }
        guard await isAuthorized() else { return nil }
        guard let candidates = await exactNameCandidates(for: artistName, key: key) else { return nil }

        let chosen: MusicKit.Artist?
        if candidates.count > 1, !knownAlbumTitles.isEmpty {
            chosen = await bestCandidate(among: candidates, knownAlbumTitles: knownAlbumTitles)
            disambiguatedKeys.insert(key)
        } else {
            chosen = candidates.first
        }
        artistCache[key] = chosen
        return chosen
    }

    /// `nil` en cas d'erreur (non mémorisé) ; tableau vide si aucun artiste du catalogue ne
    /// porte exactement ce nom (mémorisé : réponse définitive).
    private func exactNameCandidates(for artistName: String, key: String) async -> [MusicKit.Artist]? {
        if let cached = candidatesCache[key] {
            return cached
        }
        do {
            // Qualifié explicitement : le modèle `Artist` de l'app (Discogs, `Models/Artist.swift`)
            // porte le même nom que `MusicKit.Artist` et masque ce dernier par défaut dans ce module.
            var request = MusicCatalogSearchRequest(
                term: Self.strippingDiscogsDisambiguation(artistName),
                types: [MusicKit.Artist.self]
            )
            request.limit = 10
            let response = try await request.response()
            let candidates = response.artists.filter { Self.comparableArtistName($0.name) == key }
            candidatesCache[key] = Array(candidates)
            return Array(candidates)
        } catch {
            logger.error("Recherche MusicKit échouée pour \(artistName, privacy: .public) : \(error, privacy: .public)")
            return nil
        }
    }

    /// Homonyme dont les albums recoupent le plus les titres connus de l'utilisateur. Limité aux
    /// 4 premiers candidats (une requête chacun) ; à égalité, l'ordre de pertinence de la
    /// recherche Apple Music l'emporte.
    private func bestCandidate(among candidates: [MusicKit.Artist], knownAlbumTitles: Set<String>) async -> MusicKit.Artist? {
        var best: (artist: MusicKit.Artist, score: Int)?
        for candidate in candidates.prefix(4) {
            let titles = (try? await fetchAlbums(artistID: candidate.id, section: .albums, artworkSize: 300)) ?? []
            let score = titles.filter { knownAlbumTitles.contains(Self.normalizeTitle($0.name)) }.count
            if score > (best?.score ?? -1) {
                best = (candidate, score)
            }
        }
        return best?.artist ?? candidates.first
    }

    /// Accès au catalogue Apple Music, vu par l'appelant.
    enum Access {
        case authorized
        /// Refusé par l'utilisateur ou restreint (contrôle parental) : seuls les Réglages
        /// iOS permettent de changer d'avis, l'invite système ne se représente plus.
        case denied
    }

    /// Demande l'autorisation si elle n'a encore jamais été demandée (une seule invite par
    /// lancement d'app, pas à chaque ligne de classement), puis renvoie l'accès actuel. Le
    /// refus n'est pas mémorisé : un accès accordé ensuite dans les Réglages est pris en compte
    /// dès l'appel suivant, sans relancer l'app.
    func ensureAccess() async -> Access {
        await isAuthorized() ? .authorized : .denied
    }

    private func isAuthorized() async -> Bool {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            guard !hasRequestedAuthorization else { return false }
            hasRequestedAuthorization = true
            return await MusicAuthorization.request() == .authorized
        default:
            return false
        }
    }
}

/// Réponse brute (JSON:API) des vues de discographie d'artiste de l'API Apple Music — pas de
/// wrapper MusicKit typé pour ces vues, d'où l'appel via `MusicDataRequest` et ce décodage minimal.
private struct AlbumsViewResponse: Decodable {
    struct Item: Decodable {
        struct Attributes: Decodable {
            struct Artwork: Decodable {
                let url: String
            }
            let name: String
            let artistName: String
            let releaseDate: String?
            let artwork: Artwork?
        }
        let id: String
        let attributes: Attributes
    }
    let data: [Item]
    /// Chemin de la page suivante (ex. `/v1/catalog/fr/artists/…/view/full-albums?offset=100`),
    /// absent sur la dernière page.
    let next: String?
}

/// Réponse brute (JSON:API) de la fiche catalogue d'un artiste — seule `editorialNotes` nous
/// intéresse ici, pas besoin du wrapper MusicKit typé pour ça.
private struct ArtistResourceResponse: Decodable {
    struct Item: Decodable {
        struct Attributes: Decodable {
            struct EditorialNotes: Decodable {
                let standard: String?
                let short: String?
            }
            let editorialNotes: EditorialNotes?
        }
        let attributes: Attributes
    }
    let data: [Item]
}
