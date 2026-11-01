import Foundation
import Testing
@testable import Spinlog

/// Saisie rapide du prix d'achat et de l'état après un ajout.
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

    @Test func priceIsReadWithItsOwnCurrency() {
        let price = BatchCompletion.parsedPrice(amountText: "24,99", currency: "USD")
        #expect(price?.amount == 24.99)
        #expect(price?.currency == "USD")
        #expect(BatchCompletion.parsedPrice(amountText: "", currency: "EUR") == nil)
        #expect(BatchCompletion.parsedPrice(amountText: "-1", currency: "EUR") == nil)
    }

    @Test func theQuickEntryIsOfferedUnlessTurnedOff() {
        let user = "batch-completion-\(UUID().uuidString)"
        defer { CollectionPreferencesStore.clearAccountData(for: user) }
        #expect(BatchCompletion.isOffered(for: user))

        CollectionPreferencesStore.setOffersCompletionAfterAdd(false, for: user)
        #expect(!BatchCompletion.isOffered(for: user))

        CollectionPreferencesStore.setOffersCompletionAfterAdd(true, for: user)
        #expect(BatchCompletion.isOffered(for: user))
    }

    @Test func savingNothingWritesNothing() async throws {
        let json: [String: Any] = [
            "id": 31_001, "instance_id": 31_001, "folder_id": 1, "rating": 0,
            "date_added": "2024-01-15T10:00:00-07:00",
            "basic_information": ["id": 31_001, "title": "Album", "resource_url": ""]
        ]
        let item = try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
        guard case .saved = await BatchCompletion.save(price: nil, condition: nil, on: item, username: "x") else {
            Issue.record("Une saisie vide doit être acquittée sans écriture")
            return
        }
    }
}
