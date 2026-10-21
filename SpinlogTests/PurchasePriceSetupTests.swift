import Foundation
import Testing
@testable import Spinlog

/// État de la configuration du suivi de plus-value affiché par la page « Comment ça fonctionne ? ».
@MainActor
struct PurchasePriceSetupTests {
    @Test func gainNeedsThePriceField() {
        let setup = PurchasePriceSetup(purchasePriceFieldId: nil, mediaConditionFieldId: 7, currency: "EUR")
        #expect(!setup.hasPriceField)
        #expect(!setup.isComplete)
    }

    /// Sans champ d'état, la cote retombe sur la moyenne : moins précise, mais le prix suffit.
    @Test func missingConditionFieldKeepsGainPossibleButIncomplete() {
        let setup = PurchasePriceSetup(purchasePriceFieldId: 3, mediaConditionFieldId: nil, currency: "EUR")
        #expect(setup.hasPriceField)
        #expect(!setup.hasConditionField)
        #expect(!setup.isComplete)
    }

    @Test func bothFieldsMakeTheSetupComplete() {
        let setup = PurchasePriceSetup(purchasePriceFieldId: 3, mediaConditionFieldId: 7, currency: "USD")
        #expect(setup.isComplete)
    }

    @Test func signedOutAccountHasNothingConfigured() {
        let setup = PurchasePriceSetup.load(for: nil)
        #expect(!setup.hasPriceField)
        #expect(!setup.hasConditionField)
        #expect(setup.currency == "EUR")
    }
}
