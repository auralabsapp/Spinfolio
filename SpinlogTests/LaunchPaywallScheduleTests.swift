import Foundation
import Testing
@testable import Spinlog

/// Chaque test utilise sa propre suite `UserDefaults`, pour ne jamais toucher aux préférences
/// réelles de l'app hôte.
@MainActor
struct LaunchPaywallScheduleTests {
    private let suiteName = "LaunchPaywallScheduleTests-\(UUID().uuidString)"

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let defaults = UserDefaults(suiteName: suiteName)!
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func dueOnFirstLaunch() {
        withDefaults { defaults in
            #expect(LaunchPaywallSchedule.isDue(defaults: defaults))
        }
    }

    @Test func notDueAgainWithinAWeek() {
        withDefaults { defaults in
            let shownAt = Date()
            LaunchPaywallSchedule.markShown(now: shownAt, defaults: defaults)
            #expect(!LaunchPaywallSchedule.isDue(now: shownAt.addingTimeInterval(3600), defaults: defaults))
            #expect(!LaunchPaywallSchedule.isDue(now: shownAt.addingTimeInterval(6 * 24 * 3600), defaults: defaults))
        }
    }

    @Test func dueAgainAfterAWeek() {
        withDefaults { defaults in
            let shownAt = Date()
            LaunchPaywallSchedule.markShown(now: shownAt, defaults: defaults)
            #expect(LaunchPaywallSchedule.isDue(now: shownAt.addingTimeInterval(7 * 24 * 3600), defaults: defaults))
        }
    }
}
