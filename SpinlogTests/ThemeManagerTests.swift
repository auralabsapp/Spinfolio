import Foundation
import Testing
@testable import Spinlog

/// Thème affiché selon le Premium : un thème Premium est masqué sans abonnement, jamais oublié.
@MainActor
struct ThemeManagerTests {
    @Test func premiumThemeIsMaskedWithoutSubscription() {
        #expect(ThemeManager.displayedTheme(chosen: .cobalt, isPremium: false) == .signature)
    }

    @Test func chosenThemeComesBackWithPremium() {
        // Thème masqué à la perte de l'abonnement, rétabli à la reprise.
        #expect(ThemeManager.displayedTheme(chosen: .cobalt, isPremium: true) == .cobalt)
    }

    @Test func defaultThemeIsKeptWithoutPremium() {
        #expect(ThemeManager.displayedTheme(chosen: .signature, isPremium: false) == .signature)
    }
}
