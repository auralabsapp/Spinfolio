import SwiftUI

/// Sélection d'un camembert : part mise en avant, et position angulaire fournie par
/// `chartAngleSelection`.
@Observable
@MainActor
final class StatsPieSelection {
    var name: String?
    var angle: Double?
}

enum StatsSheetKind {
    case year
    case genre
    case artist
    case mediaFormat
}

/// La feuille « support » est partagée (part Support, part Label, puces de style et de taille de
/// vinyle) : à sa fermeture, seule la part qui l'a ouverte directement est remise à zéro. Les
/// puces de détail la laissent sélectionnée, comme son détail reste affiché.
enum MediaSheetOwner {
    case none
    case mediaFormat
    case label
}

/// Sélections et feuilles de TOUS les graphiques de l'onglet Stats (histogrammes, camemberts,
/// classement des artistes).
///
/// Volontairement un objet `@Observable` lu uniquement par les graphiques concernés et par les
/// modificateurs de `StatsSheets.swift`, plutôt que des `@State` de `StatsView` : l'écran Stats
/// est un seul `body` qui contient tous les graphiques, et chaque changement d'un `@State` le
/// ré-évaluait en entier. Résultat : estompage des barres et retour à la normale à la fermeture
/// d'une feuille en retard. Ici, seul le graphique touché est redessiné.
@Observable
@MainActor
final class StatsChartSelection {
    // Histogrammes par année
    var originalYear: String?
    var additionsYear: String?

    // Classement des artistes (barres horizontales)
    var topArtist: String?

    // Camemberts
    let genre = StatsPieSelection()
    let mediaFormat = StatsPieSelection()
    let label = StatsPieSelection()

    // Feuilles de disques (une seule à la fois)
    var yearData: YearReleasesSheetData?
    var genreData: GenreReleasesSheetData?
    var artistData: ArtistReleasesSheetData?
    var mediaFormatData: MediaFormatReleasesSheetData?
    var mediaFormatSheetOwner: MediaSheetOwner = .none

    /// Une feuille a commencé à se fermer (voir `SheetWillDisappearObserver`) : la marge basse
    /// de la page se retire et les sélections se remettent à zéro tout de suite, pendant
    /// l'animation, pas une fois la feuille partie.
    var isSheetClosing = false

    var hasOpenSheet: Bool {
        yearData != nil || genreData != nil || artistData != nil || mediaFormatData != nil
    }

    var needsBottomInset: Bool {
        hasOpenSheet && !isSheetClosing
    }

    private func isOpen(_ kind: StatsSheetKind) -> Bool {
        switch kind {
        case .year: yearData != nil
        case .genre: genreData != nil
        case .artist: artistData != nil
        case .mediaFormat: mediaFormatData != nil
        }
    }

    /// Aucune barre d'histogramme mise en avant (la feuille, elle, se ferme par son propre
    /// `yearData = nil`). Sans effet si rien n'est sélectionné : évite un second redessin quand le
    /// toucher de désélection et la fermeture de la feuille appellent tous deux cette méthode.
    func resetBars() {
        guard originalYear != nil || additionsYear != nil else { return }
        withAnimation(.chartSelection) {
            originalYear = nil
            additionsYear = nil
        }
    }

    /// Désélection d'une barre par un second toucher : les barres d'abord (animation brève), puis
    /// la feuille, dans une transaction séparée, pour que sa fermeture n'embarque pas l'animation.
    func deselect() {
        resetBars()
        yearData = nil
    }

    /// Désélection d'une barre du classement des artistes par un second toucher (même principe
    /// que `deselect()` pour les histogrammes).
    func deselectArtist() {
        resetHighlight(for: .artist)
        artistData = nil
    }

    /// Remet à zéro ce que la feuille `kind` avait mis en avant.
    func resetHighlight(for kind: StatsSheetKind) {
        switch kind {
        case .year:
            resetBars()
        case .genre:
            guard genre.name != nil else { return }
            withAnimation(.chartSelection) { genre.name = nil }
        case .artist:
            guard topArtist != nil else { return }
            withAnimation(.chartSelection) { topArtist = nil }
        case .mediaFormat:
            let owner = mediaFormatSheetOwner
            mediaFormatSheetOwner = .none
            switch owner {
            case .mediaFormat where mediaFormat.name != nil:
                withAnimation(.chartSelection) { mediaFormat.name = nil }
            case .label where label.name != nil:
                withAnimation(.chartSelection) { label.name = nil }
            default:
                break
            }
        }
    }

    /// Début de fermeture d'une feuille par glissé ou croix (le `Binding` ne passe à `nil` qu'à
    /// la fin de l'animation). Sans effet si la feuille est déjà fermée par le code.
    func sheetWillClose(_ kind: StatsSheetKind) {
        guard isOpen(kind) else { return }
        isSheetClosing = true
        resetHighlight(for: kind)
    }
}
