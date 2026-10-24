import Testing
@testable import Spinlog

/// État du compte Apple Music affiché sous la case de connexion dans Réglages.
struct AppleMusicAccountStatusTests {
    private func status(
        connected: Bool = true,
        checking: Bool = false,
        authorized: Bool = true,
        known: Bool = true,
        subscribed: Bool = false
    ) -> AppleMusicAccountStatus {
        .resolve(
            isConnected: connected,
            isChecking: checking,
            isAuthorized: authorized,
            isSubscriptionKnown: known,
            hasActiveSubscription: subscribed
        )
    }

    @Test func nothingIsShownWhenTheAccountIsNotConnected() {
        #expect(status(connected: false, subscribed: true) == .disconnected)
    }

    @Test func checkingWinsWhileAVerificationIsRunning() {
        #expect(status(checking: true, authorized: false) == .checking)
    }

    @Test func aDeniedAuthorizationIsReportedBeforeTheSubscription() {
        #expect(status(authorized: false, subscribed: true) == .denied)
    }

    @Test func anUnknownSubscriptionIsNotShownAsMissing() {
        #expect(status(known: false, subscribed: false) == .checking)
    }

    @Test func theSubscriptionDecidesOnceKnown() {
        #expect(status(subscribed: true) == .active)
        #expect(status(subscribed: false) == .noSubscription)
    }
}
