import Foundation
import Testing
@testable import Spinlog

/// Conflits iCloud : la modification la plus récente l'emporte, quel que soit l'appareil qui
/// envoie en dernier.
@MainActor
struct CloudSyncConflictTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func remoteAppliesWhenNothingIsPendingLocally() {
        #expect(CloudSyncModificationLog.remoteWins(remoteModifiedAt: t0, localPendingAt: nil))
        #expect(CloudSyncModificationLog.remoteWins(remoteModifiedAt: nil, localPendingAt: nil))
    }

    @Test func newerRemoteBeatsOlderOfflineEdit() {
        #expect(CloudSyncModificationLog.remoteWins(remoteModifiedAt: t0.addingTimeInterval(60), localPendingAt: t0))
    }

    @Test func newerLocalEditIsKept() {
        #expect(!CloudSyncModificationLog.remoteWins(remoteModifiedAt: t0, localPendingAt: t0.addingTimeInterval(60)))
    }

    @Test func undatedRemoteFromOlderAppVersionDoesNotOverwritePendingEdit() {
        #expect(!CloudSyncModificationLog.remoteWins(remoteModifiedAt: nil, localPendingAt: t0))
    }

    @Test func pendingDatesArePerAccountAndClearedOnlyWhenUnchanged() throws {
        let suiteName = "CloudSyncConflictTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CloudSyncModificationLog.recordLocalModification("tags-1", at: t0, username: "alice", defaults: defaults)
        #expect(CloudSyncModificationLog.pendingDate(for: "tags-1", username: "alice", defaults: defaults) == t0)
        #expect(CloudSyncModificationLog.pendingDate(for: "tags-1", username: "bob", defaults: defaults) == nil)

        // Une modification plus récente faite pendant l'envoi reste en attente.
        CloudSyncModificationLog.recordLocalModification("tags-1", at: t0.addingTimeInterval(5), username: "alice", defaults: defaults)
        CloudSyncModificationLog.clear("tags-1", onlyIfDatedAt: t0, username: "alice", defaults: defaults)
        #expect(CloudSyncModificationLog.pendingDate(for: "tags-1", username: "alice", defaults: defaults) == t0.addingTimeInterval(5))

        CloudSyncModificationLog.clear("tags-1", onlyIfDatedAt: t0.addingTimeInterval(5), username: "alice", defaults: defaults)
        #expect(CloudSyncModificationLog.pendingDate(for: "tags-1", username: "alice", defaults: defaults) == nil)
    }
}
