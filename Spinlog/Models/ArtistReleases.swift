import Foundation

/// Réponse paginée de `GET /artists/{id}/releases` : toutes les sorties liées à un artiste,
/// y compris ses apparitions secondaires (voir `DiscogsDiscography.mainWorks`).
struct ArtistReleasesResponse: Decodable, Sendable {
    let pagination: Pagination
    let releases: [ArtistReleaseItem]
}

/// Une entrée de la discographie Discogs d'un artiste : soit un master (l'œuvre, qui regroupe
/// toutes ses éditions), soit une release isolée.
struct ArtistReleaseItem: Decodable, Sendable, Identifiable, Equatable {
    enum Kind: String, Sendable {
        case master
        case release
    }

    /// Identifiant du master ou de la release, selon `type`.
    let discogsId: Int
    let type: String
    let title: String
    let year: Int?
    let thumb: String?
    /// Rôle de l'artiste sur cette sortie : « Main » pour ses propres disques ; « Appearance »,
    /// « TrackAppearance », « Producer »… pour les participations.
    let role: String?
    /// Master de rattachement d'une release, le cas échéant. Discogs regroupe en principe déjà
    /// les releases d'un master sous celui-ci, mais une release qui le renseigne malgré tout
    /// est une réédition à écarter (voir `DiscogsDiscography.mainWorks`).
    let masterId: Int?
    /// Format résumé d'une release (« CD, Single, Promo ») ; absent pour un master.
    let format: String?
    /// Pressage principal d'un master : seul moyen de connaître son format (voir
    /// `DiscogsDiscography.category(fromFormatTokens:)`), les masters n'en ayant aucun.
    let mainRelease: Int?

    var kind: Kind? { Kind(rawValue: type) }

    /// Unique entre masters et releases : un master et une release peuvent partager un même
    /// identifiant numérique.
    var id: String { "\(type)-\(discogsId)" }

    private enum CodingKeys: String, CodingKey {
        case discogsId = "id"
        case type, title, year, thumb, role, format
        case masterId = "master_id"
        case mainRelease = "main_release"
    }

    init(
        discogsId: Int,
        type: String,
        title: String,
        year: Int?,
        thumb: String?,
        role: String?,
        masterId: Int?,
        format: String? = nil,
        mainRelease: Int? = nil
    ) {
        self.discogsId = discogsId
        self.type = type
        self.title = title
        self.year = year
        self.thumb = thumb
        self.role = role
        self.masterId = masterId
        self.format = format
        self.mainRelease = mainRelease
    }
}

/// Sections de la discographie Discogs, calquées sur celles du site discogs.com. L'API ne les
/// expose pas : elles se déduisent des formats du pressage (voir
/// `DiscogsDiscography.category(fromFormatTokens:)`). Pas de section « Live » : Discogs ne
/// la signale dans aucun format. Valeurs brutes persistées (cache des classements) : ne pas
/// les renommer.
enum DiscogsWorkCategory: String, CaseIterable, Identifiable, Sendable {
    case albums
    case singlesAndEPs
    case compilations
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: String(localized: "Albums")
        case .singlesAndEPs: String(localized: "Singles & EP")
        case .compilations: String(localized: "Compilations")
        case .other: String(localized: "Autres")
        }
    }
}

/// Règles de synthèse de la discographie Discogs d'un artiste. Fonctions pures, sans état :
/// testées dans `SpinlogTests`.
enum DiscogsDiscography {
    /// Ne garde que les œuvres propres à l'artiste, sans doublons de rééditions, de la plus
    /// récente à la plus ancienne :
    /// 1. rôle principal uniquement (`role == "Main"`) : écarte compilations multi-artistes,
    ///    apparitions et crédits de production ;
    /// 2. tous les masters, et les releases seulement si elles n'ont pas de master (sorties
    ///    autoproduites, singles orphelins) ;
    /// 3. tri par année décroissante, années inconnues (absentes ou à 0) en fin de liste ; à
    ///    année égale, l'ordre d'origine est conservé.
    static func mainWorks(from items: [ArtistReleaseItem]) -> [ArtistReleaseItem] {
        var seen = Set<String>()
        let kept = items.filter { item in
            guard item.role == "Main", seen.insert(item.id).inserted else { return false }
            switch item.kind {
            case .master: return true
            case .release: return item.masterId == nil
            case nil: return false
            }
        }
        return kept.enumerated()
            .sorted { lhs, rhs in
                let leftYear = knownYear(lhs.element)
                let rightYear = knownYear(rhs.element)
                switch (leftYear, rightYear) {
                case let (left?, right?) where left != right:
                    return left > right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    /// Section d'une œuvre d'après les formats de l'un de ses pressages : noms et descriptions
    /// Discogs (« Vinyl », « LP », « Album », « 7" », « Single »…). Par ordre de priorité :
    /// une compilation reste une compilation même en LP ; un album se reconnaît à « Album »,
    /// « LP » ou « Mini-Album » ; un single ou un EP à « Single », « EP », « Maxi-Single » ou
    /// au format 7" ; le reste (vidéos, cassettes promo sans précision…) va dans « Autres ».
    static func category(fromFormatTokens tokens: [String]) -> DiscogsWorkCategory {
        let normalized = Set(tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        // Les formats résumés de la liste abrègent certaines descriptions : « Comp »
        // (Compilation), « Maxi » (Maxi-Single).
        if !normalized.isDisjoint(with: ["compilation", "comp"]) {
            return .compilations
        }
        if !normalized.isDisjoint(with: ["album", "lp", "mini-album"]) {
            return .albums
        }
        if !normalized.isDisjoint(with: ["single", "ep", "maxi-single", "maxi", "7\""]) {
            return .singlesAndEPs
        }
        return .other
    }

    /// Même règle à partir du format résumé d'une release (« CD, Single, Promo »).
    static func category(fromFormatSummary summary: String) -> DiscogsWorkCategory {
        category(fromFormatTokens: summary.components(separatedBy: ","))
    }

    /// Même règle à partir des formats détaillés d'une release.
    static func category(fromFormats formats: [ReleaseFormat]) -> DiscogsWorkCategory {
        category(fromFormatTokens: formats.flatMap { [$0.name] + ($0.descriptions ?? []) })
    }

    private static func knownYear(_ item: ArtistReleaseItem) -> Int? {
        guard let year = item.year, year > 0 else { return nil }
        return year
    }
}
