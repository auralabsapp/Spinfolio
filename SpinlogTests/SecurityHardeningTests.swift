import Foundation
import Testing
@testable import Spinlog

/// Jetons Keychain effacés seulement sur une installation neuve ; lien d'arrêt d'écoute réservé
/// au bouton de la Live Activity.
struct SecurityHardeningTests {
    // MARK: - Installation neuve

    @Test func freshInstallWithoutAnyAppDataPurgesTheTokens() {
        #expect(FreshInstallKeychainReset.isFreshInstall(standardKeys: ["AppleLanguages", "NSInterfaceStyle"], hasAppGroupData: false))
    }

    @Test func updateFromAnOlderVersionKeepsTheUserSignedIn() {
        // Pas encore de marqueur, mais des réglages de l'app : c'est une mise à jour.
        #expect(!FreshInstallKeychainReset.isFreshInstall(standardKeys: ["com.spinlog.offlineItemCount_alice"], hasAppGroupData: false))
        #expect(!FreshInstallKeychainReset.isFreshInstall(standardKeys: ["appColorTheme"], hasAppGroupData: false))
        #expect(!FreshInstallKeychainReset.isFreshInstall(standardKeys: [], hasAppGroupData: true))
    }

    @Test func laterLaunchesNeverPurge() {
        #expect(!FreshInstallKeychainReset.isFreshInstall(standardKeys: [FreshInstallKeychainReset.markerKey], hasAppGroupData: false))
    }

    // MARK: - Lien d'arrêt d'écoute

    @Test func endSessionLinkCarriesTheTokenAndIsReadBack() throws {
        let attributes = NowPlayingActivityAttributes(releaseId: 42, albumTitle: "A", artistName: "B", sessionToken: "secret")
        let url = try #require(attributes.endSessionURL)
        let request = try #require(NowPlayingActivityAttributes.endSessionRequest(from: url))
        #expect(request.releaseId == 42)
        #expect(attributes.acceptsEndRequest(token: request.token))
    }

    @Test func forgedLinksAreRefused() throws {
        let attributes = NowPlayingActivityAttributes(releaseId: 42, albumTitle: "A", artistName: "B", sessionToken: "secret")
        let noTokenURL = try #require(URL(string: "spinlog://end-session/42"))
        let wrongTokenURL = try #require(URL(string: "spinlog://end-session/42?token=guess"))
        let noReleaseURL = try #require(URL(string: "spinlog://end-session"))
        let noToken = try #require(NowPlayingActivityAttributes.endSessionRequest(from: noTokenURL))
        let wrongToken = try #require(NowPlayingActivityAttributes.endSessionRequest(from: wrongTokenURL))
        #expect(!attributes.acceptsEndRequest(token: noToken.token))
        #expect(!attributes.acceptsEndRequest(token: wrongToken.token))
        // Sans identifiant de disque, le lien n'est même pas lu (il arrêtait toute écoute).
        #expect(NowPlayingActivityAttributes.endSessionRequest(from: noReleaseURL) == nil)
    }
}
