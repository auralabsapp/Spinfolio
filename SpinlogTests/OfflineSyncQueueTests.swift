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

/// Suppression d'un dossier : les actions en attente qui le visaient sont redirigées.
struct FolderRetargetingTests {
    @Test func actionsTargetingTheDeletedFolderAreRedirected() {
        var add = PendingAction(type: .addToCollection, releaseId: 1, folderId: 42, instanceId: -1)
        add.username = "alice"
        let move = PendingAction(type: .moveCollectionInstance, releaseId: 2, folderId: 7, instanceId: 20, targetFolderId: 42)
        let field = PendingAction(type: .updateCollectionField, releaseId: 3, folderId: 42, instanceId: 30, fieldId: 4, value: "10 EUR")
        let other = PendingAction(type: .removeFromCollection, releaseId: 4, folderId: 7, instanceId: 40)

        let result = OfflineSyncQueue.retargeted([add, move, field, other], fromFolderId: 42, toFolderId: 1)

        #expect(result.map(\.folderId) == [1, 7, 1, 7])
        #expect(result.map(\.targetFolderId) == [nil, 1, nil, nil])
        #expect(result.map(\.id) == [add, move, field, other].map(\.id))
        #expect(result[0].username == "alice")
        #expect(result[2].value == "10 EUR" && result[2].fieldId == 4)
    }
}

/// Un ajout rejoué ne doit pas recréer un exemplaire déjà créé par un premier envoi resté sans
/// réponse, sans pour autant confondre deux ajouts volontaires du même disque.
@MainActor
struct DuplicateAddDetectionTests {
    private func instance(_ id: Int, added: Date) throws -> CollectionItem {
        let formatter = ISO8601DateFormatter()
        let json: [String: Any] = [
            "id": 99, "instance_id": id, "folder_id": 1, "rating": 0,
            "date_added": formatter.string(from: added),
            "basic_information": ["id": 99, "title": "T", "resource_url": ""]
        ]
        return try JSONDecoder().decode(CollectionItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private let queuedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func copiesOwnedBeforeTheAddAreIgnored() throws {
        let action = PendingAction(type: .addToCollection, releaseId: 99, date: queuedAt)
        let owned = try instance(1, added: queuedAt.addingTimeInterval(-86_400))
        #expect(OfflineSyncQueue.matchingAlreadyAddedInstance(in: [owned], for: action) == nil)
    }

    @Test func copyCreatedAfterQueuingIsRecognized() throws {
        let action = PendingAction(type: .addToCollection, releaseId: 99, date: queuedAt)
        let owned = try instance(1, added: queuedAt.addingTimeInterval(-86_400))
        let created = try instance(2, added: queuedAt.addingTimeInterval(5))
        #expect(OfflineSyncQueue.matchingAlreadyAddedInstance(in: [owned, created], for: action) == 2)
    }

    @Test func smallClockSkewIsTolerated() throws {
        let action = PendingAction(type: .addToCollection, releaseId: 99, date: queuedAt)
        let created = try instance(2, added: queuedAt.addingTimeInterval(-60))
        #expect(OfflineSyncQueue.matchingAlreadyAddedInstance(in: [created], for: action) == 2)
    }

    @Test func copyClaimedByAnotherAddIsNotReused() throws {
        var second = PendingAction(type: .addToCollection, releaseId: 99, date: queuedAt)
        second.excludedInstanceIds = [2]
        let createdForFirst = try instance(2, added: queuedAt.addingTimeInterval(5))
        #expect(OfflineSyncQueue.matchingAlreadyAddedInstance(in: [createdForFirst], for: second) == nil)
    }

    @Test func excludedIdsSurvivePersistence() throws {
        var action = PendingAction(type: .addToCollection, releaseId: 99)
        action.excludedInstanceIds = [7, 8]
        let decoded = try JSONDecoder().decode(PendingAction.self, from: JSONEncoder().encode(action))
        #expect(decoded.excludedInstanceIds == [7, 8])
    }
}
