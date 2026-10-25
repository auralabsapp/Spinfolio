import Foundation
import Testing
@testable import Spinlog

/// Règles pures des grades : paliers, progression, fusion iCloud et célébration.
struct GradeRulesTests {
    private let day1 = Date(timeIntervalSince1970: 1_000_000)
    private let day2 = Date(timeIntervalSince1970: 2_000_000)

    @Test func tiersAreReachedAtTheirThreshold() {
        #expect(GradeRules.reachedTierCount(count: 0, track: .collection) == 0)
        #expect(GradeRules.reachedTierCount(count: 1, track: .collection) == 1)
        #expect(GradeRules.reachedTierCount(count: 9, track: .collection) == 1)
        #expect(GradeRules.reachedTierCount(count: 10, track: .collection) == 2)
        #expect(GradeRules.reachedTierCount(count: 1_000, track: .collection) == 7)
        #expect(GradeRules.reachedTierCount(count: 50_000, track: .listening) == 7)
    }

    @Test func nextThresholdIsNilAtTheTopGrade() {
        #expect(GradeRules.nextThreshold(acquiredTiers: 0, track: .collection) == 1)
        #expect(GradeRules.nextThreshold(acquiredTiers: 3, track: .collection) == 100)
        #expect(GradeRules.nextThreshold(acquiredTiers: 7, track: .collection) == nil)
    }

    @Test func progressRunsBetweenTwoThresholds() {
        // Entre 50 (grade 3 acquis) et 100 : 75 disques = moitié du chemin.
        #expect(GradeRules.progress(count: 75, acquiredTiers: 3, track: .collection) == 0.5)
        #expect(GradeRules.progress(count: 50, acquiredTiers: 3, track: .collection) == 0)
        #expect(GradeRules.progress(count: 10_000, acquiredTiers: 7, track: .collection) == 1)
    }

    /// Un nombre qui redescend sous le palier ne fait ni baisser la jauge sous zéro ni déborder.
    @Test func progressIsClamped() {
        #expect(GradeRules.progress(count: 20, acquiredTiers: 3, track: .collection) == 0)
        #expect(GradeRules.progress(count: 400, acquiredTiers: 3, track: .collection) == 1)
    }

    @Test func mergeKeepsEveryTierAndTheEarliestDate() {
        let local = [GradeUnlock(track: .collection, tier: 0, date: day2), GradeUnlock(track: .collection, tier: 1, date: day2)]
        let remote = [GradeUnlock(track: .collection, tier: 0, date: day1), GradeUnlock(track: .listening, tier: 0, date: day2)]
        let merged = GradeRules.merge(local, remote)
        #expect(merged.count == 3)
        #expect(merged.first { $0.track == .collection && $0.tier == 0 }?.date == day1)
        #expect(merged.contains { $0.track == .collection && $0.tier == 1 })
        #expect(merged.contains { $0.track == .listening && $0.tier == 0 })
    }

    @Test func mergeIsCommutativeAndIdempotent() {
        let a = [GradeUnlock(track: .collection, tier: 1, date: day2), GradeUnlock(track: .collection, tier: 0, date: day2)]
        let b = [GradeUnlock(track: .collection, tier: 2, date: day1)]
        #expect(GradeRules.merge(a, b) == GradeRules.merge(b, a))
        #expect(GradeRules.merge(a, a) == GradeRules.normalized(a))
    }

    /// Avoir le grade 3 suppose avoir franchi 0, 1 et 2, même si un enregistrement ne portait que le 3.
    @Test func normalizationBackfillsLowerTiers() {
        let result = GradeRules.normalized([GradeUnlock(track: .collection, tier: 3, date: day1)])
        #expect(result.map(\.tier) == [0, 1, 2, 3])
        #expect(result.allSatisfy { $0.date == day1 })
    }

    @Test func newUnlocksOnlyContainMissingTiers() {
        let existing = [GradeUnlock(track: .collection, tier: 0, date: day1), GradeUnlock(track: .collection, tier: 1, date: day1)]
        let added = GradeRules.newUnlocks(count: 120, track: .collection, existing: existing, date: day2)
        #expect(added.map(\.tier) == [2, 3])
        #expect(GradeRules.newUnlocks(count: 12, track: .collection, existing: existing, date: day2).isEmpty)
    }

    @Test func firstEvaluationNeverCelebrates() {
        #expect(!GradeRules.shouldCelebrate(previousCount: nil, newCount: 250, track: .collection))
    }

    @Test func smallStepsCelebrateButBulkJumpsDoNot() {
        #expect(GradeRules.shouldCelebrate(previousCount: 49, newCount: 50, track: .collection))
        #expect(GradeRules.shouldCelebrate(previousCount: 9, newCount: 10, track: .listening))
        #expect(!GradeRules.shouldCelebrate(previousCount: 10, newCount: 400, track: .collection))
        #expect(!GradeRules.shouldCelebrate(previousCount: 3, newCount: 60, track: .listening))
    }

    @Test func aDecreaseNeverCelebrates() {
        #expect(!GradeRules.shouldCelebrate(previousCount: 100, newCount: 99, track: .collection))
    }

    /// Le N-ième événement (dans l'ordre chronologique) franchit le palier de seuil N.
    @Test func historicalDatesFollowTheNthEvent() {
        let dates = (1...12).map { Date(timeIntervalSince1970: Double($0) * 1_000) }.reversed()
        let result = GradeRules.historicalDates(eventDates: Array(dates), track: .collection, now: day2)
        #expect(result[0] == Date(timeIntervalSince1970: 1_000))
        #expect(result[1] == Date(timeIntervalSince1970: 10_000))
        #expect(result[2] == nil)
    }

    @Test func historicalDatesAreNeverInTheFuture() {
        let future = Date(timeIntervalSince1970: 9_000_000)
        let result = GradeRules.historicalDates(eventDates: [future], track: .listening, now: day2)
        #expect(result[0] == day2)
    }

    @Test func newUnlocksUseHistoricalDatesWhenKnown() {
        let added = GradeRules.newUnlocks(count: 12, track: .collection, existing: [], date: day2, historicalDates: [0: day1])
        #expect(added.first { $0.tier == 0 }?.date == day1)
        #expect(added.first { $0.tier == 1 }?.date == day2)
    }

    @Test func welcomeTargetIsTheHighestTierWithCollectionOnTies() {
        let unlocks = [
            GradeUnlock(track: .collection, tier: 3, date: day1),
            GradeUnlock(track: .listening, tier: 3, date: day1)
        ]
        #expect(GradeRules.welcomeTarget(unlocks: unlocks)?.track == .collection)
        let higherListening = unlocks + [GradeUnlock(track: .listening, tier: 5, date: day1)]
        #expect(GradeRules.welcomeTarget(unlocks: higherListening)?.track == .listening)
        #expect(GradeRules.welcomeTarget(unlocks: [])  == nil)
    }

    @Test func partialOrStaleCachesAreNotReliable() {
        #expect(GradeEvaluator.isCollectionCacheReliable(cachedCount: 120, announcedTotal: 120, isStale: false))
        #expect(GradeEvaluator.isCollectionCacheReliable(cachedCount: 130, announcedTotal: 120, isStale: false))
        #expect(!GradeEvaluator.isCollectionCacheReliable(cachedCount: 60, announcedTotal: 120, isStale: false))
        #expect(!GradeEvaluator.isCollectionCacheReliable(cachedCount: 120, announcedTotal: 120, isStale: true))
        #expect(!GradeEvaluator.isCollectionCacheReliable(cachedCount: 120, announcedTotal: nil, isStale: false))
        #expect(!GradeEvaluator.isCollectionCacheReliable(cachedCount: 0, announcedTotal: 0, isStale: false))
    }

    // MARK: - Fusion d'un enregistrement iCloud

    @Test func gradesKnownOnlyHereAreResentEvenWhenNothingChangesLocally() {
        // L'appareil connaît un grade absent d'iCloud : rien ne change en local, mais il faut renvoyer.
        let local = GradeRules.normalized([GradeUnlock(track: .collection, tier: 1, date: day1)])
        let result = GradeRules.mergeRemote(local: local, localWelcomeDecided: true, remote: [], remoteWelcomeDecided: true)
        #expect(!result.changesLocal)
        #expect(result.needsResend)
    }

    @Test func remoteGradesAddedLocallyWithoutResendWhenICloudKnowsMore() {
        let remote = [GradeUnlock(track: .listening, tier: 2, date: day1)]
        let result = GradeRules.mergeRemote(local: [], localWelcomeDecided: false, remote: remote, remoteWelcomeDecided: true)
        #expect(result.changesLocal)
        #expect(!result.needsResend)
        #expect(result.welcomeDecided)
        #expect(result.unlocks == GradeRules.normalized(remote))
    }

    @Test func identicalGradesNeitherChangeNorResend() {
        let unlocks = GradeRules.normalized([GradeUnlock(track: .collection, tier: 2, date: day1)])
        let result = GradeRules.mergeRemote(local: unlocks, localWelcomeDecided: true, remote: unlocks, remoteWelcomeDecided: true)
        #expect(!result.changesLocal)
        #expect(!result.needsResend)
    }

    @Test func welcomeDecidedOnlyHereIsResent() {
        let result = GradeRules.mergeRemote(local: [], localWelcomeDecided: true, remote: [], remoteWelcomeDecided: false)
        #expect(!result.changesLocal)
        #expect(result.needsResend)
    }

    @Test func earlierLocalDateIsResent() {
        let local = [GradeUnlock(track: .collection, tier: 0, date: day1)]
        let remote = [GradeUnlock(track: .collection, tier: 0, date: day2)]
        let result = GradeRules.mergeRemote(local: local, localWelcomeDecided: true, remote: remote, remoteWelcomeDecided: true)
        #expect(!result.changesLocal)
        #expect(result.needsResend)
        #expect(result.unlocks.first?.date == day1)
    }
}
