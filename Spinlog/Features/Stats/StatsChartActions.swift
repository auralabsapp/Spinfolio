import SwiftUI

/// Ouverture des feuilles de disques depuis les graphiques de l'onglet Stats. Point commun : le
/// titre du graphique touché défile en haut de l'écran, pour qu'il reste entièrement visible
/// au-dessus de la feuille (la marge basse de la page, voir `StatsSheetBottomInset`, rend ce
/// défilement possible jusqu'en fin de page).
extension StatsView {
    /// Fait défiler le titre d'un graphique (`.id`) en haut de l'écran, une fois la feuille en
    /// train de s'ouvrir.
    func scrollToChartTitle(_ id: String, scrollProxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: AppTiming.scrollSettleDelay)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                scrollProxy.scrollTo(id, anchor: .top)
            }
        }
    }

    func openGenreSheet(_ genre: String, scrollProxy: ScrollViewProxy) {
        chartSelection.genreData = GenreReleasesSheetData(genre: genre, items: viewModel.items(forGenre: genre))
        scrollToChartTitle("genreTitle", scrollProxy: scrollProxy)
    }

    /// Les autres barres s'estompent tout de suite ; la liste des disques de l'artiste n'est
    /// calculée qu'ensuite, hors du fil principal, puis la feuille s'ouvre (même principe que les
    /// histogrammes par année).
    func selectArtist(_ artist: String, scrollProxy: ScrollViewProxy) {
        withAnimation(.chartSelection) { chartSelection.topArtist = artist }

        Task { @MainActor in
            let items = await viewModel.items(forArtist: artist)
            // Sélection abandonnée entre-temps (autre barre, désélection) : rien à ouvrir.
            guard chartSelection.topArtist == artist else { return }
            chartSelection.artistData = ArtistReleasesSheetData(artist: artist, items: items)
            scrollToChartTitle("topArtistsTitle", scrollProxy: scrollProxy)
        }
    }

    /// Feuille « support », partagée par plusieurs graphiques : `owner` désigne la part à remettre
    /// à zéro à sa fermeture (voir `MediaSheetOwner`), `titleID` le titre à faire défiler.
    func openMediaFormatSheet(
        title: String,
        items: [CollectionItem],
        owner: MediaSheetOwner,
        titleID: String,
        scrollProxy: ScrollViewProxy
    ) {
        chartSelection.mediaFormatSheetOwner = owner
        chartSelection.mediaFormatData = MediaFormatReleasesSheetData(title: title, items: items)
        scrollToChartTitle(titleID, scrollProxy: scrollProxy)
    }
}
