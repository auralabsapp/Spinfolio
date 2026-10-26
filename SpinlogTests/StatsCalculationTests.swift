import Foundation
import Testing
@testable import Spinlog

/// Calculs de l'onglet Stats sortis du view model : total investi par devise et répartition
/// par genre.
@MainActor
struct StatsCalculationTests {
    private static var nextId = 9_000

    private func item(genres: [String]? = nil, purchasePrice: String? = nil, fieldId: Int = 4) throws -> CollectionItem {
        Self.nextId += 1
        var info: [String: Any] = [
            "id": Self.nextId, "title": "Title", "resource_url": "",
            "artists": [["id": 1, "name": "Artist"]]
        ]
        if let genres { info["genres"] = genres }
        var json: [String: Any] = [
            "id": Self.nextId, "instance_id": Self.nextId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00", "basic_information": info
        ]
        if let purchasePrice { json["notes"] = [["field_id": fieldId, "value": purchasePrice]] }
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func purchasePricesAreSummedPerCurrency() throws {
        let items = [
            try item(purchasePrice: "20 EUR"),
            try item(purchasePrice: "12.50"),
            try item(purchasePrice: "$30.00"),
            try item(purchasePrice: "   "),
            try item(purchasePrice: "10 EUR", fieldId: 99),
            try item()
        ]
        let sums = StatsViewModel.purchaseAmountsByCurrency(of: items, fieldId: 4, defaultCurrency: "EUR")
        #expect(sums["EUR"] == 32.5)
        #expect(sums["USD"] == 30)
        #expect(sums.count == 2)
    }

    @Test func genresBeyondFiveAreGroupedInOthers() throws {
        var items: [CollectionItem] = []
        // Rock 7, Jazz 6, Pop 5, Funk 4, Soul 3, Blues 2, Reggae 1 : 7 genres → 5 + « Autres ».
        for (genre, count) in [("Rock", 7), ("Jazz", 6), ("Pop", 5), ("Funk", 4), ("Soul", 3), ("Blues", 2), ("Reggae", 1)] {
            for _ in 0..<count { items.append(try item(genres: [genre])) }
        }
        let result = StatsViewModel.genreDistribution(of: items)
        #expect(result.entries.map(\.name) == ["Rock", "Jazz", "Pop", "Funk", "Soul", StatsViewModel.othersLabel])
        #expect(result.entries.last?.count == 3)
        #expect(result.others == ["Blues", "Reggae"])
        let total = result.entries.reduce(0) { $0 + $1.percentage }
        #expect(abs(total - 100) < 0.001)
    }

    @Test func recordWithoutGenreCountsAsUnspecified() throws {
        let result = StatsViewModel.genreDistribution(of: [try item(genres: [" "]), try item(genres: ["Rock"])])
        #expect(result.entries.map(\.name).sorted() == [StatsViewModel.unspecifiedLabel, "Rock"].sorted())
        #expect(result.others.isEmpty)
    }

    @Test func emptyCollectionHasNoDistribution() {
        let result = StatsViewModel.genreDistribution(of: [])
        #expect(result.entries.isEmpty)
    }

    @Test func topSlicesKeepFiveAndGroupTheRestWhenThereAreMoreThanSix() {
        let six = StatsViewModel.topSlices(["A": 6, "B": 5, "C": 4, "D": 3, "E": 2, "F": 1])
        #expect(six.slices.count == 6)
        #expect(six.others.isEmpty)

        let seven = StatsViewModel.topSlices(["A": 6, "B": 5, "C": 4, "D": 3, "E": 2, "F": 1, "G": 1])
        #expect(seven.slices.map(\.name) == ["A", "B", "C", "D", "E", StatsViewModel.othersLabel])
        #expect(seven.others == ["F", "G"])
    }

    @Test func artistRankingGroupsDisambiguatedNames() throws {
        func record(_ artist: String) throws -> CollectionItem {
            Self.nextId += 1
            let json: [String: Any] = [
                "id": Self.nextId, "instance_id": Self.nextId, "folder_id": 1, "rating": 0,
                "date_added": "2024-01-15T10:00:00-07:00",
                "basic_information": [
                    "id": Self.nextId, "title": "Title", "resource_url": "",
                    "artists": [["id": 1, "name": artist]]
                ] as [String: Any]
            ]
            return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let ranking = StatsViewModel.artistRanking(of: [
            try record("Prince"), try record("Prince (2)"), try record("Air"), try record("Bowie")
        ])
        #expect(ranking.first?.name == "Prince")
        #expect(ranking.first?.count == 2)
        #expect(ranking.map(\.name) == ["Prince", "Air", "Bowie"])
    }

    @Test func dayStampFollowsTheGivenTimeZone() throws {
        // 23 h 30 UTC le 31 décembre : déjà le 1er janvier à Paris, encore le 31 à New York.
        let date = try #require(ISO8601DateFormatter().date(from: "2025-12-31T23:30:00Z"))
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        #expect(CollectionSnapshot.dayStamp(for: date, calendar: paris) == "2026-01-01")
        #expect(CollectionSnapshot.dayStamp(for: date, calendar: newYork) == "2025-12-31")
    }
}
