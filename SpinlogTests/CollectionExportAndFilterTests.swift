import Foundation
import Testing
@testable import Spinlog

/// Export CSV de la collection et filtres format/recherche de la Collection et de la Wantlist.
@MainActor
struct CollectionExportAndFilterTests {
    private static var nextId = 11_000

    private func item(
        artist: String,
        title: String,
        folderId: Int = 1,
        format: (name: String, descriptions: [String])? = ("Vinyl", ["LP"]),
        notes: [(Int, String)] = []
    ) throws -> CollectionItem {
        Self.nextId += 1
        var info: [String: Any] = [
            "id": Self.nextId, "title": title, "resource_url": "",
            "artists": [["id": 1, "name": artist]]
        ]
        if let format { info["formats"] = [["name": format.name, "qty": "1", "descriptions": format.descriptions]] }
        let json: [String: Any] = [
            "id": Self.nextId, "instance_id": Self.nextId, "folder_id": folderId, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00", "basic_information": info,
            "notes": notes.map { ["field_id": $0.0, "value": $0.1] }
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func csvLines(_ items: [CollectionItem], fields: [CollectionField] = []) -> [String] {
        let folders = [CollectionFolder(id: 1, name: "Rock", count: 0), CollectionFolder(id: 2, name: "Jazz", count: 0)]
        return CollectionCSVExporter.generateCSV(items: items, folders: folders, fields: fields, tagStore: TagStore.shared)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }

    @Test func rowsAreSortedByFolderThenArtistThenTitle() throws {
        let lines = csvLines([
            try item(artist: "Zappa", title: "Hot Rats"),
            try item(artist: "Coltrane", title: "Blue Train", folderId: 2),
            try item(artist: "Air", title: "Talkie Walkie"),
            try item(artist: "Air", title: "Moon Safari")
        ])
        #expect(lines.count == 5)
        #expect(lines[1].hasPrefix("Jazz;Coltrane;Blue Train;"))
        #expect(lines[2].hasPrefix("Rock;Air;Moon Safari;"))
        #expect(lines[3].hasPrefix("Rock;Air;Talkie Walkie;"))
        #expect(lines[4].hasPrefix("Rock;Zappa;Hot Rats;"))
    }

    @Test func separatorsAndQuotesAreEscaped() throws {
        let lines = csvLines([try item(artist: "Earth, Wind & Fire", title: "Say \"Hey\"; Live")])
        #expect(lines[1].contains("\"Earth, Wind & Fire\""))
        #expect(lines[1].contains("\"Say \"\"Hey\"\"; Live\""))
    }

    @Test func customFieldsGetOneColumnEach() throws {
        let fields = [
            CollectionField(id: 1, name: "État", type: "dropdown", options: nil),
            CollectionField(id: 3, name: "Prix", type: "textarea", options: nil)
        ]
        let lines = csvLines([try item(artist: "Air", title: "Moon Safari", notes: [(3, "20 EUR"), (1, "VG+")])], fields: fields)
        let header = lines[0].components(separatedBy: ";")
        let row = lines[1].components(separatedBy: ";")
        let stateIndex = try #require(header.firstIndex(of: "État"))
        let priceIndex = try #require(header.firstIndex(of: "Prix"))
        #expect(row[stateIndex] == "VG+")
        #expect(row[priceIndex] == "20 EUR")
    }

    @Test func formatFilterMatchesNameOrDescription() throws {
        let lp = try item(artist: "Air", title: "Moon Safari")
        let cd = try item(artist: "Air", title: "Talkie Walkie", format: ("CD", ["Album"]))
        let none = try item(artist: "Air", title: "Pocket Symphony", format: nil)

        #expect(lp.matchesLibraryFilters(format: "vinyl", searchText: ""))
        #expect(lp.matchesLibraryFilters(format: "LP", searchText: ""))
        #expect(!cd.matchesLibraryFilters(format: "Vinyl", searchText: ""))
        #expect(!none.matchesLibraryFilters(format: "Vinyl", searchText: ""))
        #expect(none.matchesLibraryFilters(format: nil, searchText: ""))
    }

    @Test func searchMatchesTitleOrArtistIgnoringCase() throws {
        let record = try item(artist: "Daft Punk", title: "Discovery")
        #expect(record.matchesLibraryFilters(format: nil, searchText: "  discov "))
        #expect(record.matchesLibraryFilters(format: nil, searchText: "PUNK"))
        #expect(!record.matchesLibraryFilters(format: nil, searchText: "Homework"))
        #expect(!record.matchesLibraryFilters(format: "CD", searchText: "Daft"))
    }
}
