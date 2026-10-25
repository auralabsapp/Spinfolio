import CloudKit
import Testing
@testable import Spinlog

/// Suppression d'une zone de compte reçue d'iCloud : effacement local ou renvoi selon la raison.
struct CloudSyncZoneDeletionTests {
    @Test func userDeletionIsAppliedOnThisDeviceToo() {
        #expect(CloudSyncEngine.response(to: .deleted) == .clearLocalData)
        // Données de l'app effacées dans Réglages iOS > iCloud.
        #expect(CloudSyncEngine.response(to: .purged) == .clearLocalData)
    }

    @Test func encryptedDataResetReuploadsInsteadOfDeleting() {
        #expect(CloudSyncEngine.response(to: .encryptedDataReset) == .reuploadLocalData)
    }

    @Test func accountZoneNameGivesTheUsername() {
        #expect(CloudSyncEngine.username(fromZoneName: "account-alice") == "alice")
        #expect(CloudSyncEngine.username(fromZoneName: "account-") == nil)
        #expect(CloudSyncEngine.username(fromZoneName: "com.apple.coredata.cloudkit.zone") == nil)
    }
}
