import Foundation
import Testing
@testable import Spinlog

/// Résumé du suivi de plus-value affiché par la page « Comment ça fonctionne ? ».
@MainActor
struct PurchasePriceSetupTests {
    @Test func gainNeedsAtLeastOnePrice() {
        let empty = PurchasePriceSetup(pricedCopies: 0, gradedCopies: 3, hasPriceField: false, hasConditionField: false, currency: "EUR")
        #expect(!empty.hasData)
        let priced = PurchasePriceSetup(pricedCopies: 1, gradedCopies: 0, hasPriceField: false, hasConditionField: false, currency: "EUR")
        #expect(priced.hasData)
    }

    @Test func discogsIsOnlyLinkedWhenAFieldIsAssociated() {
        let none = PurchasePriceSetup(pricedCopies: 2, gradedCopies: 2, hasPriceField: false, hasConditionField: false, currency: "EUR")
        #expect(!none.isLinkedToDiscogs)
        let priceOnly = PurchasePriceSetup(pricedCopies: 2, gradedCopies: 2, hasPriceField: true, hasConditionField: false, currency: "EUR")
        #expect(priceOnly.isLinkedToDiscogs)
    }

    @Test func countsComeFromTheLocalData() throws {
        let suite = "PurchasePriceSetupTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = CopyDetailsStore(defaults: defaults)
        store.setActiveUsername("alice")
        store.setPurchasePrice((10, "EUR"), for: 1)
        store.setPurchasePrice((12, "USD"), for: 2)
        store.setMediaCondition(.good, for: 2)
        store.setMediaCondition(.mint, for: 3)

        let setup = PurchasePriceSetup.load(for: "alice", store: store)
        #expect(setup.pricedCopies == 2)
        #expect(setup.gradedCopies == 2)
    }

    @Test func signedOutAccountHasNothingConfigured() {
        let setup = PurchasePriceSetup.load(for: nil)
        #expect(!setup.hasData)
        #expect(!setup.hasPriceField)
        #expect(!setup.hasConditionField)
        #expect(setup.currency == "EUR")
    }
}
