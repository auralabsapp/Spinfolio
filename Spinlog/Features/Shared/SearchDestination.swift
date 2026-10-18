import Foundation

/// Cible de navigation identifiée par un résultat de recherche (release/master/artiste/label).
/// Vivait auparavant dans `Features/Search/SearchResultRow.swift` : plusieurs fichiers `Design/`
/// génériques (`LibraryListView`, `LibraryMosaicView`, `LibraryCarouselView`, `ArtistNameLinks`)
/// devaient l'importer depuis un fichier de ligne d'un écran précis plutôt que d'un type partagé
/// neutre — déplacé ici, aux côtés de `SearchDestinationNavigation.swift` qui l'exploite déjà.
enum SearchDestination: Hashable {
    case release(id: Int, coverURL: String?)
    case master(Int)
    case artist(Int)
    case label(Int)

    static func release(_ id: Int, coverURL: String? = nil) -> SearchDestination {
        .release(id: id, coverURL: coverURL)
    }

    init(from result: SearchResult) {
        switch result.type {
        case "master": self = .master(result.id)
        case "artist": self = .artist(result.id)
        case "label": self = .label(result.id)
        default: self = .release(result.id, coverURL: result.thumb ?? result.coverImage)
        }
    }
}
