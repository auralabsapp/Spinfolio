import Foundation
import Testing
@testable import Spinlog

/// Choix du taux de conversion : cache de 24 h, délai après un échec, repli sur la table figée.
struct CurrencyConversionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 24 * 3600

    @Test func cachedRateIsUsedUntilItExpires() {
        let recent = (rate: 1.1, fetchedAt: now.addingTimeInterval(-3600))
        let old = (rate: 1.1, fetchedAt: now.addingTimeInterval(-day - 1))
        #expect(CurrencyConversionService.freshRate(recent, now: now, ttl: day) == 1.1)
        #expect(CurrencyConversionService.freshRate(old, now: now, ttl: day) == nil)
        #expect(CurrencyConversionService.freshRate(nil, now: now, ttl: day) == nil)
    }

    @Test func apiIsNotAskedAgainRightAfterAFailure() {
        let delay: TimeInterval = 600
        #expect(CurrencyConversionService.shouldFetch(lastFailureAt: nil, now: now, retryDelay: delay))
        #expect(!CurrencyConversionService.shouldFetch(lastFailureAt: now.addingTimeInterval(-60), now: now, retryDelay: delay))
        #expect(CurrencyConversionService.shouldFetch(lastFailureAt: now.addingTimeInterval(-delay), now: now, retryDelay: delay))
    }

    @Test func expiredRealRateBeatsTheStaticTable() {
        #expect(CurrencyConversionService.fallbackRate(staleRate: 1.17, from: "EUR", to: "USD") == 1.17)
        #expect(CurrencyConversionService.fallbackRate(staleRate: nil, from: "EUR", to: "USD") == 1.08)
    }

    @Test func unknownCurrencyFallsBackToOneToOne() {
        #expect(CurrencyConversionService.staticFallbackRate(from: "XYZ", to: "EUR") == 1.0)
        let gbpToEur = CurrencyConversionService.staticFallbackRate(from: "GBP", to: "EUR")
        #expect(abs(gbpToEur - 1.27 / 1.08) < 0.0001)
    }
}
