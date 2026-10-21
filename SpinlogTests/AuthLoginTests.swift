import AuthenticationServices
import Foundation
import Testing
@testable import Spinlog

/// Connexion Discogs : une fenêtre d'autorisation fermée par l'utilisateur n'est pas une erreur.
@MainActor
struct AuthLoginTests {
    @Test func closingTheAuthorizationWindowIsACancellation() {
        #expect(DiscogsAuthManager.isUserCancellation(ASWebAuthenticationSessionError(.canceledLogin)))
    }

    @Test func realFailuresAreStillReported() {
        #expect(!DiscogsAuthManager.isUserCancellation(ASWebAuthenticationSessionError(.presentationContextNotProvided)))
        #expect(!DiscogsAuthManager.isUserCancellation(URLError(.notConnectedToInternet)))
        #expect(!DiscogsAuthManager.isUserCancellation(DiscogsAuthManager.AuthError.invalidResponse))
    }
}
