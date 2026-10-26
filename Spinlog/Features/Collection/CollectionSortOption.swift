import Foundation

/// Options de tri de la collection. Quand l'API Discogs le permet, le tri se fait côté serveur
/// via `sort`/`sort_order` de `GET /collection/folders/{id}/releases` (valeurs acceptées :
/// `label, artist, title, catno, format, rating, added, year`). Discogs n'a pas de tri "genre" :
/// pour cette option, on garde l'ordre par défaut du serveur (`added`) et on ne fait que
/// regrouper l'affichage par genre, sur les éléments déjà chargés.
///
/// Réutilisé tel quel par l'onglet Wantlist (voir `SortableLibraryItem`) : les deux écrans
/// ont la même construction (tri, filtres, sections, barre d'index).
enum CollectionSortOption: String, CaseIterable, Identifiable, Codable {
    case artist = "Artiste"
    case title = "Album"
    case added = "Date d'ajout"
    case year = "Année"
    case genre = "Genre"
    case format = "Support"
    case label = "Label"
    case rating = "Note"
    case catalogNumber = "Référence"
    case shelf = "Meuble"

    var id: String { rawValue }

    /// Libellé affiché. `rawValue` (en français) reste la valeur persistée dans les préférences
    /// et ne doit pas changer ; l'afficher directement empêchait toute traduction.
    var title: String {
        switch self {
        case .artist: return String(localized: "Artiste")
        case .title: return String(localized: "Album")
        case .added: return String(localized: "Date d'ajout")
        case .year: return String(localized: "Année")
        case .genre: return String(localized: "Genre")
        case .format: return String(localized: "Support")
        case .label: return String(localized: "Label")
        case .rating: return String(localized: "Note")
        case .catalogNumber: return String(localized: "Référence")
        case .shelf: return String(localized: "Meuble")
        }
    }

    var systemImage: String {
        switch self {
        case .artist: return "person"
        case .title: return "opticaldisc"
        case .added: return "calendar.badge.clock"
        case .year: return "calendar"
        case .genre: return "guitars"
        case .format: return "square.stack.3d.up"
        case .label: return "building.2"
        case .rating: return "star"
        case .catalogNumber: return "number"
        case .shelf: return "books.vertical.fill"
        }
    }

    nonisolated var defaultAscending: Bool {
        switch self {
        case .added, .rating:
            return false
        default:
            return true
        }
    }

    /// `nil` pour `.genre` : pas de valeur `sort` Discogs correspondante, on n'envoie rien
    /// (le serveur retombe sur son tri par défaut).
    var apiSortValue: String? {
        switch self {
        case .artist: return "artist"
        case .title: return "title"
        case .added: return "added"
        case .year: return "year"
        case .genre: return nil
        case .format: return "format"
        case .label: return "label"
        case .rating: return "rating"
        case .catalogNumber: return "catno"
        case .shelf: return "artist"
        }
    }

    /// Les disques ajoutés récemment (ou les mieux notés) sont plus pertinents en premier ;
    /// le reste s'affiche A→Z (ou année croissante).
    var apiSortOrder: String {
        (self == .added || self == .rating) ? "desc" : "asc"
    }

    func apiSortOrder(ascending: Bool) -> String {
        ascending ? "asc" : "desc"
    }
}

/// Instantané immuable des réglages de rangement nécessaires au tri `.shelf`, capturé UNE SEULE
/// FOIS sur l'acteur principal avant un tri/groupement (voir `LibrarySectionsEngine.recompute`)
/// plutôt que relu à chaque comparaison individuelle : `compareShelf`/`sectionKey` lisaient
/// auparavant `ShelfPreferencesStore`/`LocalDataStore` via `MainActor.assumeIsolated` à chaque
/// appel (jusqu'à O(n log n) fois pendant le tri), ce qui forçait tout le calcul à rester
/// synchrone sur le thread principal et provoquait un gel mesuré de 700-900ms au lancement sur
/// une grande collection. `Sendable` : capturé sur l'acteur principal, puis transmis tel quel à
/// la tâche détachée qui effectue le tri/groupement réel.
struct ShelfSortContext: Sendable {
    let strategy: ShelfSortStrategy
    let ignoreArticles: Bool
    let sortByLastName: Bool
    let customOverrides: [String: String]
    let masterYears: [Int: Int]?
}

extension ShelfPreferencesStore {
    /// Voir `ShelfSortContext`.
    var shelfSortContext: ShelfSortContext {
        ShelfSortContext(
            strategy: sortStrategy,
            ignoreArticles: ignoreArticles,
            sortByLastName: sortByLastName,
            customOverrides: customArtistSortOverrides,
            masterYears: sortStrategy.usesMasterYear ? LocalDataStore.shared.getAllMasterYears() : nil
        )
    }
}
