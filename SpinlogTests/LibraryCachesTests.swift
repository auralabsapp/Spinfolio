import Foundation
import Testing
@testable import Spinlog

/// Valeurs de la Collection mises en cache dans le view model plutôt que recalculées par `body` :
/// badges d'exemplaires et jetons de la barre de navigation rapide.
@MainActor
struct LibraryCachesTests {
    private func item(instanceId: Int, releaseId: Int, artist: String = "Artist") throws -> CollectionItem {
        let json: [String: Any] = [
            "id": releaseId, "instance_id": instanceId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": [
                "id": releaseId, "title": "Title", "resource_url": "",
                "artists": [["id": 1, "name": artist]]
            ] as [String: Any]
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func copyBadgesNumberCopiesInCollectionOrder() throws {
        let items = [
            try item(instanceId: 1, releaseId: 100),
            try item(instanceId: 2, releaseId: 200),
            try item(instanceId: 3, releaseId: 100),
            try item(instanceId: 4, releaseId: 100)
        ]
        let badges = CollectionDisplayState.copyBadges(for: items)
        #expect(badges[items[0].id] == "Ex. 1/3")
        #expect(badges[items[2].id] == "Ex. 2/3")
        #expect(badges[items[3].id] == "Ex. 3/3")
        // Disque possédé une seule fois : pas de badge.
        #expect(badges[items[1].id] == nil)
    }

    @Test func indexEntriesKeepFirstSectionOfEachToken() throws {
        let sections: [(key: String, items: [CollectionItem])] = [
            (key: "Abba", items: [try item(instanceId: 1, releaseId: 1, artist: "Abba")]),
            (key: "AC/DC", items: [try item(instanceId: 2, releaseId: 2, artist: "AC/DC")]),
            (key: "Beatles", items: [try item(instanceId: 3, releaseId: 3, artist: "Beatles")])
        ]
        let entries = libraryIndexEntries(for: sections, sort: .artist)
        #expect(entries.map(\.token) == ["A", "B"])
        #expect(entries.map(\.sectionKey) == ["Abba", "Beatles"])
    }
}
