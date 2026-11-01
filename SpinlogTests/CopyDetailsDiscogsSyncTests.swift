import Testing
import Foundation
@testable import Spinlog

@MainActor
struct CopyDetailsDiscogsSyncTests {
    private let priceField = 7
    private let conditionField = 8

    private func item(instanceId: Int, notes: [(Int, String)] = []) throws -> CollectionItem {
        let json: [String: Any] = [
            "id": instanceId + 1_000_000, "instance_id": instanceId, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": ["id": instanceId + 1_000_000, "title": "Album", "resource_url": "", "artists": [["id": 1, "name": "Artiste"]]],
            "notes": notes.map { ["field_id": $0.0, "value": $0.1] }
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func plan(_ items: [CollectionItem], _ local: [Int: CopyDetails]) -> CopyDetailsDiscogsSync.Plan {
        CopyDetailsDiscogsSync.plan(
            items: items, details: { local[$0] },
            priceFieldId: priceField, conditionFieldId: conditionField, defaultCurrency: "EUR"
        )
    }

    @Test func emptyFieldsAreFilledAndIdenticalValuesSkipped() throws {
        let items = [
            try item(instanceId: 1),
            try item(instanceId: 2, notes: [(priceField, "20.00 EUR"), (conditionField, "Mint (M)")])
        ]
        let local: [Int: CopyDetails] = [
            1: CopyDetails(purchaseAmount: 20, purchaseCurrency: "EUR", mediaCondition: .veryGood),
            2: CopyDetails(purchaseAmount: 20, purchaseCurrency: "EUR", mediaCondition: .mint)
        ]
        let result = plan(items, local)
        #expect(result.operations.count == 2)
        #expect(result.operations.allSatisfy { $0.instanceId == 1 })
        #expect(result.upToDate == 2)
    }

    @Test func aDifferentReadableValueIsReplacedButAnUnreadableOneIsKept() throws {
        let items = [
            try item(instanceId: 3, notes: [(priceField, "15 €"), (conditionField, "Neuf")])
        ]
        let local: [Int: CopyDetails] = [3: CopyDetails(purchaseAmount: 20, purchaseCurrency: "EUR", mediaCondition: .nearMint)]
        let result = plan(items, local)
        #expect(result.operations.map(\.fieldId) == [priceField])
        #expect(result.skippedUnreadable == 1)
    }

    @Test func aValueMissingInTheAppIsNeverSent() throws {
        let items = [try item(instanceId: 4, notes: [(priceField, "15 €")]), try item(instanceId: 5)]
        let result = plan(items, [4: CopyDetails(), 5: CopyDetails(mediaCondition: .good)])
        #expect(result.operations.map(\.instanceId) == [5])
        #expect(result.operations.first?.value == RecordGrade.good.discogsLabel)
    }

    @Test func sendingIsOffByDefaultOnAFreshStore() async throws {
        let suite = "CopyDetailsDiscogsSyncTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = CopyDetailsStore(defaults: defaults)
        store.setActiveUsername("sync-off-\(UUID().uuidString)")
        store.applyMapping(price: priceField, condition: conditionField)
        let element = try item(instanceId: 9)

        let outcome = await CopyDetailsWriter.setPurchasePrice((12, "EUR"), for: element, username: store.activeUsername ?? "", store: store)

        #expect(store.sendsToDiscogs == false)
        #expect(outcome == nil)
        #expect(store.purchasePrice(for: 9)?.amount == 12)
    }
}
