import Foundation
import Testing
@testable import Spinlog

/// Statistiques : hauteur des classements d'écoute (5 lignes visibles, le reste en défilant).
@MainActor
struct StatsTests {
    @Test func showsExactlyFiveMeasuredRows() {
        // 20 lignes mesurées à 600 pt au total → 5 lignes = 150 pt, quelle que soit l'estimation.
        #expect(StatsView.cappedListHeight(contentHeight: 600, rowCount: 20, estimatedRowHeight: 56) == 150)
    }

    @Test func shortListShowsAllRows() {
        #expect(StatsView.cappedListHeight(contentHeight: 210, rowCount: 3, estimatedRowHeight: 56) == 210)
    }

    @Test func fallsBackToEstimateBeforeMeasurement() {
        #expect(StatsView.cappedListHeight(contentHeight: 0, rowCount: 12, estimatedRowHeight: 56) == 280)
        #expect(StatsView.cappedListHeight(contentHeight: 0, rowCount: 0, estimatedRowHeight: 56) == 0)
    }

    private static var nextId = 9_000

    private func item(title: String, added: String) throws -> CollectionItem {
        Self.nextId += 1
        let json: [String: Any] = [
            "id": Self.nextId, "instance_id": Self.nextId, "folder_id": 1, "rating": 0, "date_added": added,
            "basic_information": ["id": Self.nextId, "title": title, "resource_url": "", "artists": [["id": 1, "name": "A"]]]
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func itemsAddedInAYearAreFilteredThenSortedNewestFirst() throws {
        let items = [
            try item(title: "Vieux", added: "2023-03-01T10:00:00-07:00"),
            try item(title: "Beta", added: "2024-05-10T10:00:00-07:00"),
            try item(title: "Alpha", added: "2024-05-10T10:00:00-07:00"),
            try item(title: "Récent", added: "2024-11-02T10:00:00-07:00")
        ]
        let titles = StatsViewModel.itemsAdded(in: 2024, from: items).map(\.basicInformation.title)
        // Du plus récent au plus ancien ; à date égale, par titre ; l'année 2023 est exclue.
        #expect(titles == ["Récent", "Alpha", "Beta"])
        #expect(StatsViewModel.itemsAdded(in: 1999, from: items).isEmpty)
    }

    // MARK: - Sélection des graphiques (StatsChartSelection)

    @Test func closingTheMediaSheetResetsOnlyThePartThatOpenedIt() {
        let selection = StatsChartSelection()
        selection.mediaFormat.name = "Vinyles"
        selection.label.name = "Sub Pop"

        // Ouverte depuis le camembert Label : seule la part Label est remise à zéro.
        selection.mediaFormatSheetOwner = .label
        selection.mediaFormatData = MediaFormatReleasesSheetData(title: "Sub Pop", items: [])
        selection.sheetWillClose(.mediaFormat)
        #expect(selection.label.name == nil)
        #expect(selection.mediaFormat.name == "Vinyles")
        #expect(selection.mediaFormatSheetOwner == .none)
    }

    @Test func detailChipsKeepTheirPieSelected() {
        let selection = StatsChartSelection()
        selection.genre.name = "Rock"
        selection.mediaFormat.name = "Vinyles"
        // Puces de style ou de taille de vinyle : aucune part n'est remise à zéro.
        selection.mediaFormatSheetOwner = .none
        selection.mediaFormatData = MediaFormatReleasesSheetData(title: "Rock · Punk", items: [])
        selection.sheetWillClose(.mediaFormat)
        #expect(selection.genre.name == "Rock")
        #expect(selection.mediaFormat.name == "Vinyles")
    }

    @Test func closingTheGenreSheetClearsTheGenreAndTheInsetEarly() {
        let selection = StatsChartSelection()
        selection.genre.name = "Jazz"
        selection.genreData = GenreReleasesSheetData(genre: "Jazz", items: [])
        #expect(selection.needsBottomInset)

        selection.sheetWillClose(.genre)
        #expect(selection.genre.name == nil)
        // La marge se retire dès le début de la fermeture, la feuille étant encore « ouverte ».
        #expect(selection.hasOpenSheet && !selection.needsBottomInset)
    }

    @Test func closingSignalIsIgnoredWhenTheSheetIsAlreadyClosed() {
        let selection = StatsChartSelection()
        selection.originalYear = "1990"
        // Fermeture déjà faite par le code (second toucher) : rien à refaire, pas d'état résiduel.
        selection.sheetWillClose(.year)
        #expect(selection.originalYear == "1990")
        #expect(!selection.isSheetClosing)
    }

    @Test func deselectingAYearBarClearsBarsAndSheet() {
        let selection = StatsChartSelection()
        selection.additionsYear = "2024"
        selection.yearData = YearReleasesSheetData(year: 2024, items: [], type: "additions", title: "Ajoutés en 2024")
        selection.deselect()
        #expect(selection.additionsYear == nil && selection.yearData == nil)
        #expect(!selection.hasOpenSheet)
    }

    @Test func closingTheArtistSheetClearsTheHighlightedBar() {
        let selection = StatsChartSelection()
        selection.topArtist = "Air"
        selection.artistData = ArtistReleasesSheetData(artist: "Air", items: [])
        selection.sheetWillClose(.artist)
        #expect(selection.topArtist == nil)
        #expect(!selection.needsBottomInset)
    }

    @Test func deselectingAnArtistBarClearsBarAndSheet() {
        let selection = StatsChartSelection()
        selection.topArtist = "Air"
        selection.artistData = ArtistReleasesSheetData(artist: "Air", items: [])
        selection.deselectArtist()
        #expect(selection.topArtist == nil && selection.artistData == nil)
    }
}
