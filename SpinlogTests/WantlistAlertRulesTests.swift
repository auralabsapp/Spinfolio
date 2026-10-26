import Foundation
import Testing
@testable import Spinlog

/// Règle de déclenchement des alertes de prix (`WantlistAlertStore.priceDecision`).
struct WantlistAlertRulesTests {
    private typealias Decision = WantlistAlertStore.PriceDecision

    @Test func priceUnderTargetIsNotifiedTheFirstTime() {
        #expect(WantlistAlertStore.priceDecision(lowestPrice: 18, targetPrice: 20, lastNotifiedPrice: nil) == Decision.notify)
        #expect(WantlistAlertStore.priceDecision(lowestPrice: 20, targetPrice: 20, lastNotifiedPrice: nil) == Decision.notify)
    }

    @Test func samePriceOrHigherIsNotNotifiedTwice() {
        #expect(WantlistAlertStore.priceDecision(lowestPrice: 18, targetPrice: 20, lastNotifiedPrice: 18) == Decision.alreadyNotified)
        #expect(WantlistAlertStore.priceDecision(lowestPrice: 19, targetPrice: 20, lastNotifiedPrice: 18) == Decision.alreadyNotified)
    }

    @Test func furtherDropIsNotifiedAgain() {
        #expect(WantlistAlertStore.priceDecision(lowestPrice: 15, targetPrice: 20, lastNotifiedPrice: 18) == Decision.notify)
    }

    @Test func priceAboveTargetOrNothingForSaleRearmsTheAlert() {
        #expect(WantlistAlertStore.priceDecision(lowestPrice: 25, targetPrice: 20, lastNotifiedPrice: 18) == Decision.rearm)
        #expect(WantlistAlertStore.priceDecision(lowestPrice: nil, targetPrice: 20, lastNotifiedPrice: 18) == Decision.rearm)
    }
}
