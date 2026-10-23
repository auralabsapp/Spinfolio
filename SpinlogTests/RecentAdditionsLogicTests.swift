import Testing
@testable import Spinlog

/// Mise à jour locale de « Derniers ajouts » après un ajout, un retrait ou un déplacement.
@MainActor
struct RecentAdditionsLogicTests {
    private func item(release: Int, instance: Int, added: String) -> CollectionItem {
        CollectionItem(
            releaseId: release, folderId: 1, rating: 0, dateAdded: added,
            basicInformation: BasicInformation(
                id: release, title: "T\(release)", year: nil, thumb: nil, coverImage: nil, genres: nil,
                styles: nil, artists: nil, labels: nil, formats: nil, resourceURL: ""
            ),
            instanceId: instance
        )
    }

    @Test func removalByInstanceKeepsOtherCopiesOfTheSameRelease() {
        let items = [item(release: 1, instance: 10, added: "2026-01-02"), item(release: 1, instance: 11, added: "2026-01-01")]
        let result = RecentAdditionsLogic.removing(releaseId: 1, instanceId: 10, from: items)
        #expect(result.map(\.instanceId) == [11])
    }

    @Test func removalWithoutInstanceDropsEveryCopyOfTheRelease() {
        let items = [item(release: 1, instance: 10, added: "2026-01-02"), item(release: 2, instance: 20, added: "2026-01-01")]
        let result = RecentAdditionsLogic.removing(releaseId: 1, instanceId: nil, from: items)
        #expect(result.map(\.instanceId) == [20])
    }

    @Test func insertionPutsTheNewestFirstAndNeverDuplicates() {
        let existing = item(release: 1, instance: 10, added: "2026-01-01")
        let added = item(release: 2, instance: 20, added: "2026-01-02")
        let once = RecentAdditionsLogic.inserting(added, into: [existing])
        #expect(once.map(\.instanceId) == [20, 10])
        #expect(RecentAdditionsLogic.inserting(added, into: once).count == 2)
    }

    @Test func insertionRespectsTheLimit() {
        let full = (1...RecentAdditionsLogic.limit).map { item(release: $0, instance: $0, added: "2026-01-01") }
        let result = RecentAdditionsLogic.inserting(item(release: 99, instance: 99, added: "2026-02-01"), into: full)
        #expect(result.count == RecentAdditionsLogic.limit)
        #expect(result.first?.instanceId == 99)
    }

    @Test func refillTakesTheNewestKnownItemsNotAlreadyListed() {
        let recents = [item(release: 1, instance: 1, added: "2026-03-01")]
        let all = recents + [item(release: 2, instance: 2, added: "2026-02-01"), item(release: 3, instance: 3, added: "2026-01-01")]
        let result = RecentAdditionsLogic.refilled(recents, from: all)
        #expect(result.map(\.instanceId) == [1, 2, 3])
    }

    @Test func replacingSwapsOnlyTheMovedInstance() {
        let items = [item(release: 1, instance: 10, added: "2026-01-02"), item(release: 2, instance: 20, added: "2026-01-01")]
        let moved = item(release: 1, instance: 99, added: "2026-01-02")
        let result = RecentAdditionsLogic.replacing(oldInstanceId: 10, with: moved, in: items)
        #expect(result.map(\.instanceId) == [99, 20])
    }
}
