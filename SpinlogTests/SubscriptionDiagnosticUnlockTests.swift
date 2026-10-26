import Foundation
import Testing
@testable import Spinlog

/// Geste de déverrouillage du diagnostic d'abonnement (7 touchers rapprochés sur la version).
struct SubscriptionDiagnosticUnlockTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func seventhQuickTapUnlocks() {
        var unlock = SubscriptionDiagnosticUnlock()
        let results = (0..<7).map { unlock.registerTap(at: start.addingTimeInterval(Double($0) * 0.3)) }
        #expect(results == [false, false, false, false, false, false, true])
    }

    @Test func aPauseRestartsTheCount() {
        var unlock = SubscriptionDiagnosticUnlock()
        for index in 0..<6 { _ = unlock.registerTap(at: start.addingTimeInterval(Double(index) * 0.3)) }
        // Pause de plus d'une seconde avant le 7e toucher : le décompte repart à 1.
        let unlocked = unlock.registerTap(at: start.addingTimeInterval(1.5 + 1.1))
        #expect(!unlocked)
    }

    @Test func countRestartsAfterUnlocking() {
        var unlock = SubscriptionDiagnosticUnlock()
        for index in 0..<7 { _ = unlock.registerTap(at: start.addingTimeInterval(Double(index) * 0.3)) }
        let unlockedAgain = unlock.registerTap(at: start.addingTimeInterval(2.4))
        #expect(!unlockedAgain)
    }
}
