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

/// Interrupteur « Synchronisation iCloud » de Réglages : activé par défaut (comportement
/// d'avant son existence), et le moteur ne tourne qu'avec le Premium ET l'interrupteur.
@MainActor
struct CloudSyncToggleTests {
    @Test func iCloudSyncToggleDefaultsToOnAndGatesTheEngine() throws {
        let defaults = try #require(UserDefaults(suiteName: "CloudSyncToggleTests"))
        defaults.removePersistentDomain(forName: "CloudSyncToggleTests")
        #expect(CloudSyncEngine.isUserEnabled(in: defaults))
        defaults.set(false, forKey: CloudSyncEngine.userEnabledKey)
        #expect(!CloudSyncEngine.isUserEnabled(in: defaults))

        #expect(CloudSyncEngine.shouldRun(isPremium: true, isUserEnabled: true))
        #expect(!CloudSyncEngine.shouldRun(isPremium: true, isUserEnabled: false))
        #expect(!CloudSyncEngine.shouldRun(isPremium: false, isUserEnabled: true))
        defaults.removePersistentDomain(forName: "CloudSyncToggleTests")
    }

    @Test func becomingPremiumTurnsSyncBackOn() {
        #expect(CloudSyncEngine.shouldAutoEnable(hadAccess: false, hasAccess: true))
        // Déjà Premium, ou perte du Premium : l'interrupteur n'est pas touché (la perte coupe
        // le moteur via `shouldRun`).
        #expect(!CloudSyncEngine.shouldAutoEnable(hadAccess: true, hasAccess: true))
        #expect(!CloudSyncEngine.shouldAutoEnable(hadAccess: true, hasAccess: false))
        #expect(!CloudSyncEngine.shouldAutoEnable(hadAccess: false, hasAccess: false))
    }
}
