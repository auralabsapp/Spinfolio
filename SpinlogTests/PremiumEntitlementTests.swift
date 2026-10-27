import Foundation
import StoreKit
import Testing
@testable import Spinlog

/// Droits Premium (abonnements et achat à vie), visibilité des outils d'achat dans Réglages et
/// résultat d'une saisie de code d'offre.
@MainActor
struct PremiumEntitlementTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let yearly = SubscriptionPlanID.yearly.rawValue
    private let monthly = SubscriptionPlanID.monthly.rawValue
    private let lifetime = PremiumProductID.lifetime

    private func active(_ productID: String, expiration: Date? = nil, revocation: Date? = nil) -> Bool {
        SubscriptionManager.isEntitlementActive(productID: productID, expirationDate: expiration, revocationDate: revocation, now: now)
    }

    // MARK: - Règle d'activité d'un droit

    @Test func aRunningSubscriptionIsActive() {
        #expect(active(yearly, expiration: now.addingTimeInterval(3600)))
        #expect(active(monthly, expiration: now.addingTimeInterval(1)))
    }

    @Test func anExpiredSubscriptionIsNotActive() {
        #expect(!active(yearly, expiration: now.addingTimeInterval(-1)))
        #expect(!active(monthly, expiration: now))
    }

    @Test func aRevokedSubscriptionIsNotActive() {
        #expect(!active(yearly, expiration: now.addingTimeInterval(3600), revocation: now.addingTimeInterval(-60)))
    }

    @Test func theLifetimePurchaseHasNoExpirationAndStaysActive() {
        #expect(active(lifetime))
    }

    @Test func aRevokedLifetimePurchaseIsNotActive() {
        #expect(!active(lifetime, revocation: now.addingTimeInterval(-60)))
    }

    @Test func aProductOutsideThePremiumSetUnlocksNothing() {
        #expect(!active("com.auralabs.Spinlog.tip.small"))
        #expect(!active("com.auralabs.Spinlog.tip.small", expiration: now.addingTimeInterval(3600)))
        // Le jeu de produits Premium peut être restreint par l'appelant.
        #expect(!SubscriptionManager.isEntitlementActive(
            productID: lifetime, expirationDate: nil, revocationDate: nil, now: now, premiumProductIDs: PremiumProductID.subscriptions
        ))
    }

    @Test func theLifetimeProductIsNotASubscriptionPlan() {
        #expect(PremiumProductID.all.contains(lifetime))
        #expect(!PremiumProductID.subscriptions.contains(lifetime))
        #expect(SubscriptionPlanID.allCases.count == 2)
        #expect(PremiumProductID.all.count == 3)
    }

    // MARK: - Visibilité dans Réglages

    @Test func subscriptionManagementIsHiddenOnlyForLifetimeWithoutSubscription() {
        #expect(PremiumSettingsVisibility.showsSubscriptionManagement(hasLifetime: false, hasActiveSubscription: false))
        #expect(PremiumSettingsVisibility.showsSubscriptionManagement(hasLifetime: false, hasActiveSubscription: true))
        #expect(PremiumSettingsVisibility.showsSubscriptionManagement(hasLifetime: true, hasActiveSubscription: true))
        #expect(!PremiumSettingsVisibility.showsSubscriptionManagement(hasLifetime: true, hasActiveSubscription: false))
    }

    @Test func codeRedemptionIsHiddenForLifetimeAndInDemo() {
        #expect(PremiumSettingsVisibility.showsCodeRedemption(hasLifetime: false, isDemoMode: false))
        #expect(!PremiumSettingsVisibility.showsCodeRedemption(hasLifetime: true, isDemoMode: false))
        #expect(!PremiumSettingsVisibility.showsCodeRedemption(hasLifetime: false, isDemoMode: true))
    }

    @Test func searchFollowsTheSameVisibilityRules() {
        func ids(management: Bool, redemption: Bool) -> Set<String> {
            Set(SettingsSearchIndex.entries(
                isAuthenticated: true, isPremium: true,
                showsSubscriptionManagement: management, showsCodeRedemption: redemption
            ).map(\.id))
        }
        #expect(ids(management: true, redemption: true).isSuperset(of: ["subscription", "redeemCode"]))
        #expect(!ids(management: false, redemption: true).contains("subscription"))
        #expect(ids(management: false, redemption: true).contains("redeemCode"))
        #expect(!ids(management: true, redemption: false).contains("redeemCode"))
    }

    // MARK: - Code d'offre

    @Test func closingTheRedemptionSheetShowsNoMessage() async {
        #expect(await SubscriptionManager.shared.handleOfferCodeResult(.failure(StoreKitError.userCancelled)) == nil)
        #expect(await SubscriptionManager.shared.handleLegacyOfferCodeResult(.failure(StoreKitError.userCancelled)) == nil)
    }

    @Test func aFailedRedemptionShowsTheErrorMessage() async {
        #expect(await SubscriptionManager.shared.handleOfferCodeResult(.failure(StoreKitError.unknown)) == AppMessages.offerCodeFailed)
        #expect(await SubscriptionManager.shared.handleLegacyOfferCodeResult(.failure(StoreKitError.unknown)) == AppMessages.offerCodeFailed)
    }
}
