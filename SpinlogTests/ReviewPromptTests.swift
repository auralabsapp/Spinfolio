import Foundation
import Testing
@testable import Spinlog

/// Demande d'avis : règles pures (paliers, durée minimale, plafond) et compteurs par compte.
@MainActor
struct ReviewPromptTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func days(_ count: Int) -> TimeInterval { TimeInterval(count) * 24 * 3600 }

    /// Store isolé : suite `UserDefaults` jetable, version et démo injectées.
    private func makeStore(version: String = "1.0", demo: Bool = false) -> ReviewPromptStore {
        let suite = "ReviewPromptTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ReviewPromptStore(defaults: defaults, appVersion: version, isDemo: { demo })
        store.setActiveUsername("Alice")
        return store
    }

    // MARK: - Règles

    @Test func milestoneIsCrossedOnlyWhenReached() {
        let milestones = ReviewPromptRules.albumMilestones
        #expect(!ReviewPromptRules.crossedMilestone(previous: 8, new: 9, milestones: milestones))
        #expect(ReviewPromptRules.crossedMilestone(previous: 9, new: 10, milestones: milestones))
        #expect(!ReviewPromptRules.crossedMilestone(previous: 10, new: 11, milestones: milestones))
        #expect(ReviewPromptRules.crossedMilestone(previous: 49, new: 50, milestones: milestones))
    }

    @Test func milestoneIsCrossedEvenWhenSkipped() {
        // Plusieurs ajouts d'un coup (compteur qui saute au-delà d'un palier).
        #expect(ReviewPromptRules.crossedMilestone(previous: 8, new: 12, milestones: [10, 50]))
    }

    @Test func listeningShorterThanOneMinuteDoesNotCount() {
        #expect(!ReviewPromptRules.countsAsListening(duration: 59))
        #expect(ReviewPromptRules.countsAsListening(duration: 60))
    }

    @Test func noRequestTwiceInTheSameVersion() {
        #expect(!ReviewPromptRules.canRequest(now: now, lastRequestDate: now.addingTimeInterval(-days(200)),
                                              lastRequestVersion: "1.0", currentVersion: "1.0"))
    }

    @Test func sixtyDaysSeparateTwoRequests() {
        #expect(!ReviewPromptRules.canRequest(now: now, lastRequestDate: now.addingTimeInterval(-days(59)),
                                              lastRequestVersion: "1.0", currentVersion: "1.1"))
        #expect(ReviewPromptRules.canRequest(now: now, lastRequestDate: now.addingTimeInterval(-days(60)),
                                             lastRequestVersion: "1.0", currentVersion: "1.1"))
    }

    @Test func firstRequestIsAllowed() {
        #expect(ReviewPromptRules.canRequest(now: now, lastRequestDate: nil, lastRequestVersion: nil, currentVersion: "1.0"))
    }

    // MARK: - Compteurs

    @Test func firstUserStoppedListeningTriggersARequest() {
        let store = makeStore()
        store.recordListeningStopped(duration: 120, now: now)
        #expect(store.listensStoppedCount == 1)
        #expect(store.pendingRequestID != nil)
    }

    @Test func shortListeningIsNotCounted() {
        let store = makeStore()
        store.recordListeningStopped(duration: 30, now: now)
        #expect(store.listensStoppedCount == 0)
        #expect(store.pendingRequestID == nil)
    }

    @Test func tenthAlbumAddedTriggersARequest() {
        let store = makeStore()
        for _ in 0..<9 { store.recordCollectionAdd(now: now) }
        #expect(store.pendingRequestID == nil)
        store.recordCollectionAdd(now: now)
        #expect(store.albumsAddedCount == 10)
        #expect(store.pendingRequestID != nil)
    }

    @Test func nothingIsCountedInDemoOrWithoutAccount() {
        let demo = makeStore(demo: true)
        demo.recordCollectionAdd(now: now)
        demo.recordListeningStopped(duration: 600, now: now)
        #expect(demo.albumsAddedCount == 0 && demo.listensStoppedCount == 0 && demo.pendingRequestID == nil)

        let signedOut = makeStore()
        signedOut.setActiveUsername(nil)
        signedOut.recordCollectionAdd(now: now)
        #expect(signedOut.albumsAddedCount == 0 && signedOut.pendingRequestID == nil)
    }

    @Test func countersAreIsolatedPerAccount() {
        let store = makeStore()
        for _ in 0..<5 { store.recordCollectionAdd(now: now) }
        store.setActiveUsername("Bob")
        #expect(store.albumsAddedCount == 0)
        store.setActiveUsername("  ALICE ")
        #expect(store.albumsAddedCount == 5)
    }

    @Test func clearingAnAccountRemovesItsCounters() {
        let store = makeStore()
        store.recordListeningStopped(duration: 120, now: now)
        store.clearAccountData(for: "Alice")
        #expect(store.listensStoppedCount == 0)
        #expect(store.pendingRequestID == nil)
    }

    // MARK: - Plafond

    @Test func consumingARequestRecordsItAndBlocksTheNextOnes() {
        let store = makeStore()
        store.recordListeningStopped(duration: 120, now: now)
        #expect(store.consumePendingRequest(now: now))
        #expect(store.pendingRequestID == nil)

        // Même version : le palier suivant (10e écoute) ne redemande rien.
        for _ in 0..<9 { store.recordListeningStopped(duration: 120, now: now.addingTimeInterval(days(70))) }
        #expect(store.listensStoppedCount == 10)
        #expect(store.pendingRequestID == nil)
    }

    @Test func aNewVersionAfterSixtyDaysCanRequestAgain() {
        let suite = "ReviewPromptTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = ReviewPromptStore(defaults: defaults, appVersion: "1.0", isDemo: { false })
        first.setActiveUsername("alice")
        first.recordListeningStopped(duration: 120, now: now)
        #expect(first.consumePendingRequest(now: now))

        // Version suivante, 61 jours plus tard : la 10e écoute peut redéclencher.
        let second = ReviewPromptStore(defaults: defaults, appVersion: "1.1", isDemo: { false })
        second.setActiveUsername("alice")
        let later = now.addingTimeInterval(days(61))
        for _ in 0..<9 { second.recordListeningStopped(duration: 120, now: later) }
        #expect(second.pendingRequestID != nil)
    }

    @Test func discardingARequestKeepsTheDateFree() {
        let store = makeStore()
        store.recordListeningStopped(duration: 120, now: now)
        store.discardPendingRequest()
        #expect(store.pendingRequestID == nil)
        // Pas de date consignée : un autre palier peut redéclencher.
        for _ in 0..<9 { store.recordListeningStopped(duration: 120, now: now) }
        #expect(store.pendingRequestID != nil)
    }
}
