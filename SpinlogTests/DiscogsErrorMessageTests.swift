import Foundation
import Testing
@testable import Spinlog

/// Les erreurs HTTP Discogs sont montrées dans la langue de l'utilisateur, jamais avec le message
/// anglais renvoyé par l'API.
@MainActor
struct DiscogsErrorMessageTests {
    @Test func discogsBodyMessageIsNotShown() {
        let error = DiscogsAPIClient.APIError.http(status: 404, message: "The requested resource was not found.")
        #expect(error.localizedDescription == DiscogsAPIClient.userMessage(forHTTPStatus: 404))
        #expect(!error.localizedDescription.contains("requested resource"))
    }

    @Test func statusFamiliesGetDistinctMessages() {
        let messages = [401, 403, 404, 422, 429, 503].map(DiscogsAPIClient.userMessage(forHTTPStatus:))
        #expect(Set(messages).count == messages.count)
        #expect(DiscogsAPIClient.userMessage(forHTTPStatus: 500) == DiscogsAPIClient.userMessage(forHTTPStatus: 503))
        #expect(DiscogsAPIClient.userMessage(forHTTPStatus: 400) == DiscogsAPIClient.userMessage(forHTTPStatus: 422))
    }

    @Test func unknownStatusMentionsTheCode() {
        #expect(DiscogsAPIClient.userMessage(forHTTPStatus: 418).contains("418"))
    }
}
