import Foundation
import Testing
@testable import Spinlog

/// Comportement du store de grades : isolation par compte, jamais de rétrogradation, silence au
/// premier comptage. `UserDefaults` dédié à chaque test pour ne rien laisser sur l'appareil.
@MainActor
final class GradeStoreTests {
    /// Une suite par test (Swift Testing crée une instance par test), effacée à la fin.
    private let suite = "GradeStoreTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    deinit {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func makeStore() -> (GradeStore, UserDefaults) {
        let store = GradeStore(defaults: defaults)
        store.setActiveUsername("alice")
        return (store, defaults)
    }

    @Test func firstEvaluationRecordsGradesWithoutCelebrating() {
        let (store, _) = makeStore()
        store.evaluate(track: .collection, count: 120, isReliable: true)
        #expect(store.acquiredTiers(for: .collection) == 4)
        #expect(store.pendingCelebration == nil)
    }

    @Test func crossingAThresholdLaterCelebrates() {
        let (store, _) = makeStore()
        store.evaluate(track: .collection, count: 49, isReliable: true)
        store.evaluate(track: .collection, count: 50, isReliable: true)
        #expect(store.acquiredTiers(for: .collection) == 3)
        #expect(store.pendingCelebration?.tier == 2)
        #expect(store.pendingCelebration?.track == .collection)
    }

    @Test func aGradeIsNeverLostWhenTheCountDrops() {
        let (store, _) = makeStore()
        store.evaluate(track: .collection, count: 120, isReliable: true)
        store.evaluate(track: .collection, count: 3, isReliable: true)
        #expect(store.acquiredTiers(for: .collection) == 4)
        #expect(store.knownCount(for: .collection) == 3)
    }

    @Test func anUnreliableCountChangesNothing() {
        let (store, _) = makeStore()
        store.evaluate(track: .collection, count: 120, isReliable: false)
        #expect(store.acquiredTiers(for: .collection) == 0)
        #expect(store.knownCount(for: .collection) == nil)
    }

    @Test func gradesAreIsolatedPerAccountAndRestored() {
        let (store, _) = makeStore()
        store.evaluate(track: .listening, count: 12, isReliable: true)
        store.setActiveUsername("bob")
        #expect(store.acquiredTiers(for: .listening) == 0)
        store.setActiveUsername("alice")
        #expect(store.acquiredTiers(for: .listening) == 2)
    }

    @Test func remoteGradesAreMergedNotReplaced() {
        let (store, _) = makeStore()
        store.evaluate(track: .collection, count: 12, isReliable: true)
        store.applyRemote(SyncedGrades(unlocks: [GradeUnlock(track: .listening, tier: 1, date: Date(timeIntervalSince1970: 5))], welcomeDecided: false))
        #expect(store.acquiredTiers(for: .collection) == 2)
        #expect(store.acquiredTiers(for: .listening) == 2)
    }

    @Test func demoAccountNeverEarnsGrades() {
        let store = GradeStore(defaults: defaults)
        store.setActiveUsername(DemoMode.username)
        store.evaluate(track: .collection, count: 500, isReliable: true)
        #expect(store.acquiredTiers(for: .collection) == 0)
    }

    @Test func clearingAnAccountRemovesItsGrades() {
        let (store, _) = makeStore()
        store.evaluate(track: .collection, count: 60, isReliable: true)
        store.clearAccountData(for: "alice")
        #expect(store.acquiredTiers(for: .collection) == 0)
        store.setActiveUsername(nil)
        store.setActiveUsername("alice")
        #expect(store.acquiredTiers(for: .collection) == 0)
    }

    @Test func silentGradesTakeTheirHistoricalDate() {
        let (store, _) = makeStore()
        let dates = (1...12).map { Date(timeIntervalSince1970: Double($0) * 1_000) }
        store.evaluate(track: .collection, count: 12, isReliable: true, eventDates: dates)
        #expect(store.unlockDate(track: .collection, tier: 0) == Date(timeIntervalSince1970: 1_000))
        #expect(store.unlockDate(track: .collection, tier: 1) == Date(timeIntervalSince1970: 10_000))
    }

    @Test func welcomeShowsTheHighestGradeOnceBothTracksAreCounted() {
        let (store, _) = makeStore()
        store.evaluate(track: .listening, count: 12, isReliable: true)
        #expect(store.pendingCelebration == nil)
        store.evaluate(track: .collection, count: 120, isReliable: true)
        #expect(store.pendingCelebration?.kind == .welcome)
        #expect(store.pendingCelebration?.track == .collection)
        #expect(store.pendingCelebration?.tier == 3)
        #expect(store.welcomeDecided)
    }

    @Test func welcomeIsNeverShownTwice() {
        let (store, _) = makeStore()
        store.evaluate(track: .listening, count: 12, isReliable: true)
        store.evaluate(track: .collection, count: 120, isReliable: true)
        store.dismissCelebration()
        store.evaluate(track: .collection, count: 121, isReliable: true)
        store.evaluate(track: .listening, count: 13, isReliable: true)
        #expect(store.pendingCelebration == nil)
    }

    @Test func anAccountStartingFromZeroGetsNoWelcome() {
        let (store, _) = makeStore()
        store.evaluate(track: .collection, count: 0, isReliable: true)
        store.evaluate(track: .listening, count: 0, isReliable: true)
        #expect(store.pendingCelebration == nil)
        #expect(store.welcomeDecided)
        // Le premier disque est ensuite fêté comme un grade ordinaire.
        store.evaluate(track: .collection, count: 1, isReliable: true)
        #expect(store.pendingCelebration?.kind == .newGrade)
    }

    @Test func welcomeAlreadyDoneOnAnotherDeviceIsNotRepeated() {
        let (store, _) = makeStore()
        store.applyRemote(SyncedGrades(unlocks: [GradeUnlock(track: .collection, tier: 3, date: Date(timeIntervalSince1970: 5))], welcomeDecided: true))
        store.evaluate(track: .listening, count: 12, isReliable: true)
        store.evaluate(track: .collection, count: 120, isReliable: true)
        #expect(store.pendingCelebration == nil)
    }
}
