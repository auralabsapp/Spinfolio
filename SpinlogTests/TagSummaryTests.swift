import Foundation
import Testing
@testable import Spinlog

/// Liste et compteurs de tags mis en cache par `TagStore` (`TagSummary`).
struct TagSummaryTests {
    @Test func listsEveryTagOnceInAlphabeticalOrder() {
        let summary = TagSummary(
            instanceTags: [["Rock", "à écouter"], ["Rock"], ["Jazz"]],
            legacyTags: [["Ancien"]],
            standaloneTags: ["Zèbre", "Jazz"]
        )
        #expect(summary.allTags == ["à écouter", "Ancien", "Jazz", "Rock", "Zèbre"])
    }

    @Test func countsEachCopyOncePerTag() {
        let summary = TagSummary(
            instanceTags: [["Rock", "Rock"], ["Rock", "Jazz"], []],
            legacyTags: [],
            standaloneTags: []
        )
        #expect(summary.count(for: "Rock") == 2)
        #expect(summary.count(for: "Jazz") == 1)
    }

    @Test func fallsBackToLegacyReleaseTagsOnlyWhenNoCopyHasTheTag() {
        let summary = TagSummary(
            instanceTags: [["Rock"]],
            legacyTags: [["Rock"], ["Rock"], ["Ancien"]],
            standaloneTags: ["Vide"]
        )
        #expect(summary.count(for: "Rock") == 1)
        #expect(summary.count(for: "Ancien") == 1)
        #expect(summary.count(for: "Vide") == 0)
        #expect(summary.count(for: "Inconnu") == 0)
    }

    @Test func emptyStoreGivesEmptySummary() {
        let summary = TagSummary(instanceTags: [], legacyTags: [], standaloneTags: [])
        #expect(summary.allTags.isEmpty)
        #expect(summary.count(for: "Rock") == 0)
    }
}
