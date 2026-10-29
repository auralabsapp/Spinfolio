import Testing
import Foundation
@testable import Spinlog

struct YearlySavingsTests {
    @Test func savingsAreRoundedToWholePercent() {
        // 1,99 × 12 = 23,88 ; annuel 17,99 → 24,7 % → 25
        #expect(SubscriptionManager.yearlySavingsPercent(yearly: Decimal(string: "17.99")!, monthly: Decimal(string: "1.99")!) == 25)
    }

    @Test func noSavingsWhenYearlyIsNotCheaper() {
        #expect(SubscriptionManager.yearlySavingsPercent(yearly: 24, monthly: 2) == nil)
        #expect(SubscriptionManager.yearlySavingsPercent(yearly: 30, monthly: 2) == nil)
    }

    @Test func noSavingsWhenMonthlyPriceIsZero() {
        #expect(SubscriptionManager.yearlySavingsPercent(yearly: 10, monthly: 0) == nil)
    }
}
