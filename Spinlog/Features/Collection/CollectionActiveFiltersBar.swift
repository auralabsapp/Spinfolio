import SwiftUI

/// Bandeau des filtres actifs de la Collection : tags, support et champs à compléter, avec
/// « Tout effacer ». Regroupe les trois appels de `CollectionView` (liste, mosaïque, écran sans
/// résultat) pour que le jeu de filtres n'ait qu'un seul point d'extension.
struct CollectionActiveFiltersBar: View {
    let display: CollectionDisplayState

    var body: some View {
        LibraryActiveFiltersBar(
            selectedTags: Bindable(display).selectedTags,
            selectedFormat: Bindable(display).selectedFormat,
            selectedMissingFields: Bindable(display).missingFields,
            onClearAll: display.clearFilters
        )
    }
}
