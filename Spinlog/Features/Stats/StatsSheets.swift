import SwiftUI

/// Marge basse de la page Stats tant qu'une feuille est ouverte, pour que le titre d'un graphique
/// puisse défiler jusqu'en haut de l'écran. Lit la sélection ici (et non dans le corps de
/// `StatsView`) : voir `StatsChartSelection`.
///
/// Le changement de marge n'est jamais animé : animé, il remettait en page toute la page (tous
/// les graphiques) à chaque image, pendant que les sélections se réinitialisaient et que la
/// feuille se fermait — ce qui rendait la désélection saccadée.
struct StatsSheetBottomInset: ViewModifier {
    let selection: StatsChartSelection

    func body(content: Content) -> some View {
        let inset: CGFloat = selection.needsBottomInset ? 420 : 0
        content
            .padding(.bottom, inset)
            .animation(nil, value: inset)
    }
}

/// Les quatre feuilles de disques de l'onglet Stats (année, genre, artiste, support/label).
///
/// Chacune remet à zéro ce qu'elle avait mis en avant dès qu'elle commence à se fermer
/// (`SheetWillDisappearObserver`) : l'élément ne passe à `nil` (et `onDismiss` n'arrive) qu'à la
/// fin de l'animation, conservés en filet de sécurité.
struct StatsSheetsModifier: ViewModifier {
    @Bindable var selection: StatsChartSelection

    func body(content: Content) -> some View {
        content
            // Nouvelle feuille ou dernière feuille refermée : l'état « en fermeture » ne vaut plus.
            .onChange(of: selection.hasOpenSheet) { _, _ in
                selection.isSheetClosing = false
            }
            .onChange(of: selection.yearData == nil) { _, isClosed in
                if isClosed { selection.resetHighlight(for: .year) }
            }
            .onChange(of: selection.genreData == nil) { _, isClosed in
                if isClosed { selection.resetHighlight(for: .genre) }
            }
            .onChange(of: selection.artistData == nil) { _, isClosed in
                if isClosed { selection.resetHighlight(for: .artist) }
            }
            .onChange(of: selection.mediaFormatData == nil) { _, isClosed in
                if isClosed { selection.resetHighlight(for: .mediaFormat) }
            }
            .sheet(item: $selection.yearData, onDismiss: { selection.resetHighlight(for: .year) }) { data in
                sheetContent(YearReleasesSheetView(data: data), kind: .year)
            }
            .sheet(item: $selection.genreData, onDismiss: { selection.resetHighlight(for: .genre) }) { data in
                sheetContent(GenreReleasesSheetView(data: data), kind: .genre)
            }
            .sheet(item: $selection.artistData, onDismiss: { selection.resetHighlight(for: .artist) }) { data in
                sheetContent(ArtistReleasesSheetView(data: data), kind: .artist)
            }
            .sheet(item: $selection.mediaFormatData, onDismiss: { selection.resetHighlight(for: .mediaFormat) }) { data in
                sheetContent(MediaFormatReleasesSheetView(data: data), kind: .mediaFormat)
            }
    }

    private func sheetContent(_ view: some View, kind: StatsSheetKind) -> some View {
        view
            .background(SheetWillDisappearObserver { selection.sheetWillClose(kind) })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}
