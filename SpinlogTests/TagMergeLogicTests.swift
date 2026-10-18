import Foundation
import Testing
@testable import Spinlog

@MainActor
struct TagMergeLogicTests {
    private func tag(_ name: String, _ secondsSinceReference: TimeInterval) -> SyncedTag {
        SyncedTag(name: name, addedAt: Date(timeIntervalSinceReferenceDate: secondsSinceReference))
    }

    @Test func unionIsCaseInsensitiveAndKeepsOldestDate() {
        let merged = TagMergeLogic.merge(
            local: [tag("Jazz", 200), tag("Live", 100)],
            remote: [tag("jazz", 50), tag("Promo", 300)]
        )

        #expect(merged.map(\.name) == ["jazz", "Live", "Promo"])
        #expect(merged.first?.addedAt == Date(timeIntervalSinceReferenceDate: 50))
    }

    @Test func emptySidesReturnTheOtherSide() {
        let tags = [tag("A", 1), tag("B", 2)]
        #expect(TagMergeLogic.merge(local: tags, remote: []) == tags)
        #expect(TagMergeLogic.merge(local: [], remote: tags) == tags)
    }

    @Test func truncationKeepsMostRecentTags() {
        let limit = TagConstants.maxTagsPerInstance
        let local = (0..<limit).map { tag("local\($0)", TimeInterval($0)) }
        let remote = [tag("newest", 10_000)]

        let merged = TagMergeLogic.merge(local: local, remote: remote)

        #expect(merged.count == limit)
        #expect(merged.last?.name == "newest")
        #expect(!merged.contains { $0.name == "local0" })
    }
}
