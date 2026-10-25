import Foundation
import Testing
@testable import Spinlog

/// Délai minimal de 5 min entre deux rechargements automatiques d'un onglet depuis Discogs.
struct ReloadThrottleTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func firstAppearanceAlwaysReloads() {
        #expect(ReloadThrottle().shouldReload(for: "alice", now: start))
    }

    @Test func returningWithinFiveMinutesUsesTheCache() {
        var throttle = ReloadThrottle()
        throttle.recordReload(for: "alice", at: start)
        #expect(!throttle.shouldReload(for: "alice", now: start.addingTimeInterval(60)))
        #expect(!throttle.shouldReload(for: "alice", now: start.addingTimeInterval(299)))
    }

    @Test func afterFiveMinutesTheTabReloads() {
        var throttle = ReloadThrottle()
        throttle.recordReload(for: "alice", at: start)
        #expect(throttle.shouldReload(for: "alice", now: start.addingTimeInterval(300)))
    }

    @Test func anotherAccountOrAResetReloadsAtOnce() {
        var throttle = ReloadThrottle()
        throttle.recordReload(for: "alice", at: start)
        #expect(throttle.shouldReload(for: "bob", now: start.addingTimeInterval(10)))
        throttle.reset()
        #expect(throttle.shouldReload(for: "alice", now: start.addingTimeInterval(10)))
    }
}
