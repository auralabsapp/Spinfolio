import Foundation
import Testing
@testable import Spinlog

/// Tri et regroupement en sections de la Collection/Wantlist (`SortableLibraryItem`).
/// Les éléments sont construits à partir du JSON Discogs, comme dans l'app.
@MainActor
struct LibrarySortingTests {
    private static var nextInstanceId = 1_000

    private func item(
        artist: String = "Artist",
        title: String = "Title",
        year: Int? = 2000,
        format: String? = "Vinyl",
        label: String? = "Label",
        catno: String? = "CAT-1",
        rating: Int = 0,
        added: String = "2024-01-15T10:00:00-07:00"
    ) throws -> CollectionItem {
        Self.nextInstanceId += 1
        let releaseId = Self.nextInstanceId + 500_000
        var info: [String: Any] = [
            "id": releaseId, "title": title, "resource_url": "",
            "artists": [["id": 1, "name": artist]],
            "genres": ["Rock"]
        ]
        if let year { info["year"] = year }
        if let format { info["formats"] = [["name": format, "qty": "1"]] }
        if let label { info["labels"] = [["id": 1, "name": label, "catno": catno ?? ""]] }
        let json: [String: Any] = [
            "id": releaseId, "instance_id": Self.nextInstanceId, "folder_id": 1,
            "rating": rating, "date_added": added, "basic_information": info
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func sorted(_ items: [CollectionItem], by sort: CollectionSortOption, ascending: Bool? = nil) -> [String] {
        items.sorted { $0.isOrderedBefore($1, for: sort, ascending: ascending ?? sort.defaultAscending) }
            .map(\.basicInformation.title)
    }

    @Test func dateAddedAndRatingDefaultToDescending() {
        #expect(!CollectionSortOption.added.defaultAscending)
        #expect(!CollectionSortOption.rating.defaultAscending)
        #expect(CollectionSortOption.artist.defaultAscending)
        #expect(CollectionSortOption.year.defaultAscending)
    }

    @Test func artistSortUsesTitleToBreakTies() throws {
        let items = [
            try item(artist: "Miles Davis", title: "Kind of Blue"),
            try item(artist: "Air", title: "Moon Safari"),
            try item(artist: "Miles Davis", title: "Bitches Brew")
        ]
        #expect(sorted(items, by: .artist) == ["Moon Safari", "Bitches Brew", "Kind of Blue"])
        // Ordre inversé sur l'artiste, mais toujours alphabétique sur le titre à artiste égal.
        #expect(sorted(items, by: .artist, ascending: false) == ["Bitches Brew", "Kind of Blue", "Moon Safari"])
    }

    @Test func unknownYearsStayLastInBothDirections() throws {
        let items = [
            try item(title: "Sans année", year: nil),
            try item(title: "1977", year: 1977),
            try item(title: "Année zéro", year: 0),
            try item(title: "2015", year: 2015)
        ]
        let ascending = sorted(items, by: .year, ascending: true)
        let descending = sorted(items, by: .year, ascending: false)
        #expect(Array(ascending.prefix(2)) == ["1977", "2015"])
        #expect(Array(descending.prefix(2)) == ["2015", "1977"])
        #expect(Set(ascending.suffix(2)) == ["Sans année", "Année zéro"])
        #expect(Set(descending.suffix(2)) == ["Sans année", "Année zéro"])
    }

    @Test func newestAdditionsComeFirstByDefault() throws {
        let items = [
            try item(title: "Ancien", added: "2023-01-01T10:00:00-07:00"),
            try item(title: "Récent", added: "2025-06-01T10:00:00-07:00"),
            try item(title: "Moyen", added: "2024-03-01T10:00:00-07:00")
        ]
        #expect(sorted(items, by: .added) == ["Récent", "Moyen", "Ancien"])
    }

    @Test func missingFormatsSortAfterKnownOnes() throws {
        let items = [
            try item(title: "Sans support", format: nil),
            try item(title: "Vinyle", format: "Vinyl"),
            try item(title: "CD", format: "CD"),
            try item(title: "K7", format: "Cassette")
        ]
        #expect(sorted(items, by: .format) == ["K7", "CD", "Vinyle", "Sans support"])
    }

    @Test func sectionKeysFollowTheSortedField() throws {
        let record = try item(artist: "  Portishead ", title: "Dummy", year: 1994, format: "CD", label: "Go! Beat", catno: "828 553-2", rating: 5)
        #expect(record.sectionKey(for: .artist) == "Portishead")
        #expect(record.sectionKey(for: .title) == "Dummy")
        #expect(record.sectionKey(for: .year) == "1994")
        #expect(record.sectionKey(for: .format) == "CD")
        #expect(record.sectionKey(for: .label) == "Go! Beat")
        #expect(record.sectionKey(for: .catalogNumber) == "828 553-2")
        #expect(try item(year: 0).sectionKey(for: .year) == "?")
        #expect(try item(year: nil).sectionKey(for: .year) == "?")
    }

    @Test func indexTokensAreCompactForTheRail() throws {
        let record = try item(year: 1994, rating: 4, added: "2024-01-15T10:00:00-07:00")
        #expect(libraryIndexToken(for: (key: "1994", items: [record]), sort: .year) == "94")
        #expect(libraryIndexToken(for: (key: "?", items: [record]), sort: .year) == "?")
        #expect(libraryIndexToken(for: (key: "x", items: [record]), sort: .rating) == "4")
        #expect(libraryIndexToken(for: (key: "x", items: [try item(rating: 0)]), sort: .rating) == "–")
        #expect(libraryIndexToken(for: (key: "x", items: [record]), sort: .added) == "24")
    }

    @Test func availableFormatsAreUniqueAndSorted() throws {
        let items = [try item(format: "Vinyl"), try item(format: "CD"), try item(format: "Vinyl"), try item(format: nil)]
        #expect(items.availableLibraryFormats == ["CD", "Vinyl"])
    }
}
