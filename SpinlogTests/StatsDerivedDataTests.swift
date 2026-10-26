import Foundation
import Testing
@testable import Spinlog

/// Années originales, classements d'écoute et report des changements de collection dans Stats.
@MainActor
struct StatsDerivedDataTests {
    private func item(_ instanceId: Int, release: Int, master: Int? = nil, year: Int? = nil, artist: String = "A") throws -> CollectionItem {
        var info: [String: Any] = ["id": release, "title": "T\(release)", "resource_url": "", "artists": [["id": 1, "name": artist]]]
        if let master { info["master_id"] = master }
        if let year { info["year"] = year }
        let json: [String: Any] = [
            "id": release, "instance_id": instanceId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00", "basic_information": info
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func originalYearPrefersTheMasterYear() throws {
        let items = [
            try item(1, release: 1, master: 100, year: 2015),
            try item(2, release: 2, master: 200, year: 1999),
            try item(3, release: 3, year: 1975),
            try item(4, release: 4, year: 3000)
        ]
        let years = StatsViewModel.originalYears(of: items, masterYears: [100: 1969])
        #expect(years.map(\.year) == [1999, 1975, 1969])
        #expect(StatsViewModel.missingMasterIds(in: items, masterYears: [100: 1969]) == [200])
        #expect(StatsViewModel.masterResolutionProgress(of: items, masterYears: [100: 1969]) == 0.75)
        #expect(StatsViewModel.decades(of: years).map(\.decade) == [1990, 1970, 1960])
    }

    @Test func rankingsNeedEnoughListens() throws {
        let record = try item(1, release: 1, artist: "Air (2)")
        let releases = [1: record]
        let now = Date()
        let few = (0..<2).map { _ in ListeningSession(releaseId: 1, timestamp: now) }
        #expect(StatsViewModel.listeningRankings(sessions: few, releases: releases, now: now).topAlbums.isEmpty)

        let many = (0..<StatsViewModel.minimumListeningSessionsForRanking).map { _ in ListeningSession(releaseId: 1, timestamp: now) }
        let rankings = StatsViewModel.listeningRankings(sessions: many, releases: releases, now: now)
        #expect(rankings.topAlbums.first?.playCount == many.count)
        #expect(rankings.topArtists.first?.name == "Air")
        #expect(rankings.monthlyPodium.count == 1)
    }

    @Test func listensOfRecordsNoLongerOwnedAreIgnored() {
        let sessions = [ListeningSession(releaseId: 99)]
        #expect(StatsViewModel.rankedAlbums(sessions: sessions, releases: [:]).isEmpty)
    }

    @Test func removalUpdatesTotalAndRemembersTheCopy() throws {
        let first = try item(1, release: 1)
        let second = try item(2, release: 2)
        let state = StatsCollectionChanges.State(allItems: [first, second], recentAdditions: [first, second], totalCount: 2, locallyRemovedInstanceIds: [])
        let after = StatsCollectionChanges.removing(releaseId: 1, instanceId: 1, from: state)
        #expect(after.allItems.map(\.instanceId) == [2])
        #expect(after.totalCount == 1)
        #expect(after.locallyRemovedInstanceIds == [1])
        #expect(after.allItemsChanged)
    }

    @Test func additionIsIgnoredByTheFullListBeforeItLoads() throws {
        let state = StatsCollectionChanges.State(allItems: [], recentAdditions: [], totalCount: nil, locallyRemovedInstanceIds: [7])
        let after = StatsCollectionChanges.adding(try item(7, release: 7), to: state)
        #expect(after.allItems.isEmpty)
        #expect(!after.allItemsChanged)
        #expect(after.recentAdditions.count == 1)
        #expect(after.locallyRemovedInstanceIds.isEmpty)
    }

    @Test func styleBreakdownCountsEachStyleOnce() throws {
        let info: [String: Any] = ["id": 1, "title": "T", "resource_url": "", "artists": [["id": 1, "name": "A"]], "styles": ["House", " ", "Disco"]]
        let json: [String: Any] = ["id": 1, "instance_id": 1, "folder_id": 1, "rating": 0, "date_added": "2024-01-15T10:00:00-07:00", "basic_information": info]
        let record = try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
        let breakdown = StatsViewModel.styleBreakdown(of: [record, record])
        #expect(breakdown.map(\.name) == ["Disco", "House"])
        #expect(breakdown.map(\.count) == [2, 2])
    }
}
