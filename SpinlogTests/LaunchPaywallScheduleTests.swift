import Foundation
import Testing
@testable import Spinlog

/// Chaque test utilise sa propre suite `UserDefaults`, pour ne jamais toucher aux préférences
/// réelles de l'app hôte.
@MainActor
struct LaunchPaywallScheduleTests {
    private let suiteName = "LaunchPaywallScheduleTests-\(UUID().uuidString)"

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test func dueOnFirstLaunch() throws {
        try withDefaults { defaults in
            #expect(LaunchPaywallSchedule.isDue(defaults: defaults))
        }
    }

    @Test func notDueAgainWithinAWeek() throws {
        try withDefaults { defaults in
            let shownAt = Date()
            LaunchPaywallSchedule.markShown(now: shownAt, defaults: defaults)
            #expect(!LaunchPaywallSchedule.isDue(now: shownAt.addingTimeInterval(3600), defaults: defaults))
            #expect(!LaunchPaywallSchedule.isDue(now: shownAt.addingTimeInterval(6 * 24 * 3600), defaults: defaults))
        }
    }

    @Test func dueAgainAfterAWeek() throws {
        try withDefaults { defaults in
            let shownAt = Date()
            LaunchPaywallSchedule.markShown(now: shownAt, defaults: defaults)
            #expect(LaunchPaywallSchedule.isDue(now: shownAt.addingTimeInterval(7 * 24 * 3600), defaults: defaults))
        }
    }

    @Test func neverPresentedBeforeSignIn() throws {
        try withDefaults { defaults in
            // Premier lancement, offre due, mais personne n'est connecté : pas de paywall avant
            // l'écran de connexion.
            #expect(!LaunchPaywallSchedule.shouldPresent(isAuthenticated: false, hasSubscription: false, defaults: defaults))
        }
    }

    @Test func presentedRightAfterFirstSignIn() throws {
        try withDefaults { defaults in
            #expect(LaunchPaywallSchedule.shouldPresent(isAuthenticated: true, hasSubscription: false, defaults: defaults))
        }
    }

    @Test func skippedForSubscribersAndWithinTheWeek() throws {
        try withDefaults { defaults in
            #expect(!LaunchPaywallSchedule.shouldPresent(isAuthenticated: true, hasSubscription: true, defaults: defaults))
            let shownAt = Date()
            LaunchPaywallSchedule.markShown(now: shownAt, defaults: defaults)
            #expect(!LaunchPaywallSchedule.shouldPresent(
                isAuthenticated: true, hasSubscription: false, now: shownAt.addingTimeInterval(3600), defaults: defaults
            ))
        }
    }
}
