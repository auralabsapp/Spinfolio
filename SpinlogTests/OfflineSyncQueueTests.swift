import Foundation
import Testing
@testable import Spinlog

@MainActor
struct PendingActionOwnershipTests {
    @Test func legacyActionWithoutOwnerBelongsToAnyAccount() {
        let action = PendingAction(type: .addToWantlist, releaseId: 1)
        #expect(action.belongs(to: "alice"))
    }

    @Test func ownerComparisonIsCaseInsensitive() {
        var action = PendingAction(type: .addToWantlist, releaseId: 1)
        action.username = "Alice"
        #expect(action.belongs(to: "alice"))
        #expect(!action.belongs(to: "bob"))
    }

    @Test func ownerSurvivesPersistenceRoundTrip() throws {
        var action = PendingAction(type: .removeFromCollection, releaseId: 42, folderId: 1, instanceId: 7)
        action.username = "alice"

        let decoded = try JSONDecoder().decode(PendingAction.self, from: JSONEncoder().encode(action))

        #expect(decoded.username == "alice")
        #expect(decoded.instanceId == 7)
    }

    @Test func actionsPersistedBeforeOwnershipStillDecode() throws {
        // Format écrit par les versions antérieures, sans le champ `username`.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","type":"addToWantlist","releaseId":5,"date":0,"retryCount":0}
        """
        let decoded = try JSONDecoder().decode(PendingAction.self, from: Data(legacyJSON.utf8))

        #expect(decoded.username == nil)
        #expect(decoded.belongs(to: "anyone"))
    }
}

struct OfflineRetryPolicyTests {
    @Test(arguments: [(0, 30.0), (1, 30.0), (2, 60.0), (3, 120.0), (6, 960.0), (7, 1800.0), (20, 1800.0)])
    func delayDoublesUpToThirtyMinutes(failures: Int, expected: TimeInterval) {
        #expect(OfflineSyncQueue.retryDelay(afterConsecutiveFailures: failures) == expected)
    }

    @Test func recentActionIsKept() {
        let now = Date()
        let action = PendingAction(type: .addToCollection, releaseId: 1, date: now.addingTimeInterval(-6 * 24 * 3600))
        #expect(!OfflineSyncQueue.hasExpired(action, now: now))
    }

    @Test func actionOlderThanSevenDaysIsAbandoned() {
        let now = Date()
        let action = PendingAction(type: .addToCollection, releaseId: 1, date: now.addingTimeInterval(-8 * 24 * 3600))
        #expect(OfflineSyncQueue.hasExpired(action, now: now))
    }
}

/// Le tri entre « réessayer plus tard » et « abandonner » repose entièrement sur cette
/// classification : une erreur passagère mal classée faisait perdre l'action en quelques secondes.
@MainActor
struct TransientFailureClassificationTests {
    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotFindHost])
    func networkErrorsAreTransient(code: URLError.Code) {
        #expect(URLError(code).isTransientNetworkFailure)
    }

    @Test func rateLimitAndServerErrorsAreTransient() {
        #expect(DiscogsAPIClient.APIError.rateLimited.isTransientNetworkFailure)
        #expect(DiscogsAPIClient.APIError.http(status: 429, message: nil).isTransientNetworkFailure)
        #expect(DiscogsAPIClient.APIError.http(status: 503, message: nil).isTransientNetworkFailure)
    }

    @Test(arguments: [400, 401, 403, 404, 422])
    func clientErrorsAreDefinitive(status: Int) {
        #expect(!DiscogsAPIClient.APIError.http(status: status, message: nil).isTransientNetworkFailure)
    }

    @Test func demoAndMalformedResponsesAreDefinitive() {
        #expect(!DiscogsAPIClient.APIError.demoReadOnly.isTransientNetworkFailure)
        #expect(!DiscogsAPIClient.APIError.invalidResponse.isTransientNetworkFailure)
    }

    @Test func cancellationIsRecognized() {
        #expect(CancellationError().isCancellation)
        #expect(URLError(.cancelled).isCancellation)
        #expect(!URLError(.timedOut).isCancellation)
    }

    @Test func onlyHTTP404CountsAsNotFound() {
        #expect(DiscogsAPIClient.APIError.http(status: 404, message: nil).isNotFound)
        #expect(!DiscogsAPIClient.APIError.http(status: 410, message: nil).isNotFound)
        #expect(!URLError(.timedOut).isNotFound)
    }
}
