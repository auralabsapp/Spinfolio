import Foundation
import Testing
@testable import Spinlog

/// Ordre du meuble et recherche des voisins d'un disque (`ShelfPlacementService`), fonction Premium.
@MainActor
struct ShelfPlacementTests {
    private static var nextId = 7_000

    /// Artistes choisis parmi les formations connues : leur clé ne dépend pas du réglage
    /// « trier par nom de famille », lu ici dans le store partagé.
    private func release(
        artist: String,
        title: String = "Album",
        year: Int? = 2000,
        format: String = "Vinyl",
        descriptions: [String] = ["LP"]
    ) throws -> Release {
        Self.nextId += 1
        var info: [String: Any] = [
            "id": Self.nextId, "title": title, "resource_url": "",
            "artists": [["id": 1, "name": artist]],
            "formats": [["name": format, "qty": "1", "descriptions": descriptions]]
        ]
        if let year { info["year"] = year }
        let json: [String: Any] = [
            "id": Self.nextId, "instance_id": Self.nextId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00", "basic_information": info
        ]
        let item = try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
        return Release(from: item)
    }

    @Test func targetGoesBetweenItsAlphabeticalNeighbours() throws {
        let air = try release(artist: "Air")
        let cure = try release(artist: "The Cure")
        let zz = try release(artist: "ZZ Top")
        let target = try release(artist: "The Beatles")

        let neighbors = ShelfPlacementService.findNeighbors(
            for: target, in: [zz, cure, air], strategy: .artistThenTitle
        )
        #expect(neighbors.previous?.id == air.id)
        #expect(neighbors.next?.id == cure.id)
        #expect(neighbors.positionIndex == 2)
        #expect(neighbors.totalCount == 4)
    }

    @Test func otherShelvesAreNotNeighbours() throws {
        let cd = try release(artist: "Air", format: "CD", descriptions: ["Album"])
        let single = try release(artist: "Blondie", descriptions: ["7\"", "Single"])
        let lp = try release(artist: "The Cure")
        let target = try release(artist: "The Beatles")

        let neighbors = ShelfPlacementService.findNeighbors(
            for: target, in: [cd, single, lp], strategy: .artistThenTitle
        )
        #expect(neighbors.category == .vinyl12)
        #expect(neighbors.previous == nil)
        #expect(neighbors.next?.id == lp.id)
        #expect(neighbors.totalCount == 2)
    }

    @Test func targetAlreadyOnTheShelfIsNotCountedTwice() throws {
        let air = try release(artist: "Air")
        let target = try release(artist: "The Beatles")

        let neighbors = ShelfPlacementService.findNeighbors(
            for: target, in: [air, target, air], strategy: .artistThenTitle
        )
        #expect(neighbors.totalCount == 2)
        #expect(neighbors.previous?.id == air.id)
        #expect(neighbors.next == nil)
    }

    @Test func unknownYearGoesLastInChronologicalOrder() {
        let undated = ShelfPlacementService.compare(
            artistA: "Air", titleA: "A", yearA: nil, idA: 1,
            artistB: "Zz Top", titleB: "B", yearB: 1970, idB: 2,
            strategy: .chronologicalOnly
        )
        #expect(!undated)
        let older = ShelfPlacementService.compare(
            artistA: "Zz Top", titleA: "B", yearA: 1970, idA: 2,
            artistB: "Air", titleB: "A", yearB: 1998, idB: 1,
            strategy: .chronologicalOnly
        )
        #expect(older)
    }

    @Test func sameArtistIsOrderedByYearThenTitle() {
        let earlier = ShelfPlacementService.compare(
            artistA: "Air", titleA: "Talkie Walkie", yearA: 2004, idA: 1,
            artistB: "Air", titleB: "Moon Safari", yearB: 1998, idB: 2,
            strategy: .artistThenReleaseYear
        )
        #expect(!earlier)
        let byTitle = ShelfPlacementService.compare(
            artistA: "Air", titleA: "Moon Safari", yearA: 2004, idA: 1,
            artistB: "Air", titleB: "Talkie Walkie", yearB: 2004, idB: 2,
            strategy: .artistThenTitle
        )
        #expect(byTitle)
    }
}
