import Foundation
import Testing
@testable import Spinlog

/// Saisie rapide du prix d'achat et de l'état après un scan par lot.
@MainActor
struct BatchCompletionTests {
    @Test func priceAcceptsCommaOrDotAndBuildsTheDiscogsValue() {
        let expected = PurchasePriceParser.canonicalString(amount: 12.5, currency: "EUR")
        #expect(BatchCompletion.canonicalPrice(amountText: "12,5", currency: "EUR") == expected)
        #expect(BatchCompletion.canonicalPrice(amountText: " 12.5 ", currency: "EUR") == expected)
    }

    @Test func emptyUnreadableOrNegativePriceIsIgnored() {
        #expect(BatchCompletion.canonicalPrice(amountText: "", currency: "EUR") == nil)
        #expect(BatchCompletion.canonicalPrice(amountText: "   ", currency: "EUR") == nil)
        #expect(BatchCompletion.canonicalPrice(amountText: "douze", currency: "EUR") == nil)
        #expect(BatchCompletion.canonicalPrice(amountText: "-3", currency: "EUR") == nil)
        #expect(BatchCompletion.canonicalPrice(amountText: "0", currency: "EUR") != nil)
    }

    @Test func onlyConfiguredAndFilledFieldsAreWritten() {
        let both = BatchCompletion.values(priceFieldId: 5, mediaConditionFieldId: 1, amountText: "20", currency: "EUR", condition: "Near Mint (NM or M-)")
        #expect(both.map(\.fieldId) == [5, 1])
        #expect(both.last?.value == "Near Mint (NM or M-)")

        let conditionOnly = BatchCompletion.values(priceFieldId: 5, mediaConditionFieldId: 1, amountText: "", currency: "EUR", condition: "VG+")
        #expect(conditionOnly.map(\.fieldId) == [1])

        let priceNotConfigured = BatchCompletion.values(priceFieldId: nil, mediaConditionFieldId: 1, amountText: "20", currency: "EUR", condition: "")
        #expect(priceNotConfigured.isEmpty)

        let nothing = BatchCompletion.values(priceFieldId: 5, mediaConditionFieldId: 1, amountText: "", currency: "EUR", condition: "  ")
        #expect(nothing.isEmpty)
    }

    @Test func onlyFieldsChosenInSettingsAreOffered() {
        let user = "batch-completion-\(UUID().uuidString)"
        defer { CollectionPreferencesStore.clearAccountData(for: user) }
        #expect(BatchCompletion.configuredFields(for: user).isEmpty)

        CollectionPreferencesStore.setMediaConditionFieldId(1, for: user)
        #expect(BatchCompletion.configuredFields(for: user) == [.mediaCondition])

        CollectionPreferencesStore.setPurchasePriceFieldId(5, for: user)
        #expect(BatchCompletion.configuredFields(for: user) == [.purchasePrice, .mediaCondition])
    }

    @Test func savingNothingWritesNothing() async throws {
        let json: [String: Any] = [
            "id": 31_001, "instance_id": 31_001, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": ["id": 31_001, "title": "Disque", "resource_url": ""]
        ]
        let item = try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
        guard case .saved = await BatchCompletion.save([], on: item, username: "x") else {
            Issue.record("Une saisie vide doit être acquittée sans écriture")
            return
        }
    }
}
