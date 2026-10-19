import Foundation
import Testing
@testable import Spinlog

/// Règle de lecture du cache de cote (`MarketEstimate.fromCache`) : une cote de plus de 6 h
/// n'est jamais présentée comme actuelle (CGU Discogs).
struct MarketEstimateCacheTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var recent: Date { now.addingTimeInterval(-3600) }
    private var old: Date { now.addingTimeInterval(-3 * 24 * 3600) }

    private func estimate(date: Date, cachedCondition: String? = "Mint (M)", requested: String? = "Mint (M)", canFetch: Bool) -> MarketEstimate? {
        MarketEstimate.fromCache(
            price: 25,
            currency: "EUR",
            date: date,
            cachedCondition: cachedCondition,
            requestedCondition: requested,
            canFetch: canFetch,
            now: now
        )
    }

    @Test func freshEstimateForSameConditionIsReusedWithoutDate() {
        #expect(estimate(date: recent, canFetch: true) == MarketEstimate(price: 25, currency: "EUR", staleSince: nil))
    }

    @Test func staleEstimateTriggersFetchWhenOnline() {
        #expect(estimate(date: old, canFetch: true) == nil)
    }

    @Test func changedConditionTriggersFetchWhenOnline() {
        #expect(estimate(date: recent, requested: "Very Good (VG)", canFetch: true) == nil)
    }

    @Test func staleEstimateOfflineIsShownWithItsDate() {
        #expect(estimate(date: old, canFetch: false)?.staleSince == old)
    }

    @Test func freshEstimateOfflineWithChangedConditionHasNoDate() {
        let result = estimate(date: recent, requested: "Very Good (VG)", canFetch: false)
        #expect(result != nil)
        #expect(result?.staleSince == nil)
    }

    @Test func exactlySixHoursIsStale() {
        let boundary = now.addingTimeInterval(-DiscogsConstants.sixHoursTTL)
        #expect(estimate(date: boundary, canFetch: true) == nil)
        #expect(estimate(date: boundary, canFetch: false)?.staleSince == boundary)
    }
}
