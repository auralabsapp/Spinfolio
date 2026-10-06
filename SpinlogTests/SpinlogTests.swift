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

@MainActor
struct PurchasePriceParserTests {
    @Test(arguments: [
        ("25,50 €", 25.5, "EUR"),
        ("1.234,56 €", 1234.56, "EUR"),
        ("$1,234.56", 1234.56, "USD"),
        ("$960.00", 960.0, "USD"),
        ("USD 30", 30.0, "USD"),
        ("£12", 12.0, "GBP"),
        ("12.5", 12.5, "CHF")
    ])
    func parsesAmountAndCurrency(raw: String, amount: Double, currency: String) throws {
        let result = try #require(PurchasePriceParser.parse(raw, defaultCurrency: "CHF"))
        #expect(abs(result.amount - amount) < 0.001)
        #expect(result.currency == currency)
    }

    @Test(arguments: ["", "   ", "gratuit"])
    func rejectsInputWithoutAmount(raw: String) {
        #expect(PurchasePriceParser.parse(raw, defaultCurrency: "EUR") == nil)
    }

    @Test func canonicalStringUsesTwoDecimalsAndUppercasedCurrency() {
        #expect(PurchasePriceParser.canonicalString(amount: 25.5, currency: "eur") == "25.50 EUR")
    }
}

@MainActor
struct PendingActionOwnershipTests {
    @Test func legacyActionWithoutOwnerBelongsToAnyAccount() {
        let action = PendingAction(type: .addToWantlist, releaseId: 1)
        #expect(action.belongs(to: "alice"))
    }

    @Test func ownerComparisonIsCaseInsensitive() {
        var action = PendingAction(type: .addToWantlist, releaseId: 1)
        action.username = "Alice"
        #expect(action.belongs(to: "alice"))
        #expect(!action.belongs(to: "bob"))
    }

    @Test func ownerSurvivesPersistenceRoundTrip() throws {
        var action = PendingAction(type: .removeFromCollection, releaseId: 42, folderId: 1, instanceId: 7)
        action.username = "alice"

        let decoded = try JSONDecoder().decode(PendingAction.self, from: JSONEncoder().encode(action))

        #expect(decoded.username == "alice")
        #expect(decoded.instanceId == 7)
    }

    @Test func actionsPersistedBeforeOwnershipStillDecode() throws {
        // Format écrit par les versions antérieures, sans le champ `username`.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","type":"addToWantlist","releaseId":5,"date":0,"retryCount":0}
        """
        let decoded = try JSONDecoder().decode(PendingAction.self, from: Data(legacyJSON.utf8))

        #expect(decoded.username == nil)
        #expect(decoded.belongs(to: "anyone"))
    }
}
