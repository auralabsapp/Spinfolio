import Testing
import Foundation
@testable import Spinlog

@MainActor
struct CopyDetailsCloudSyncTests {
    private func details(_ amount: Double?, at seconds: TimeInterval) -> CopyDetails {
        CopyDetails(
            purchaseAmount: amount, purchaseCurrency: amount == nil ? nil : "EUR",
            modifiedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test func theRecordNameRoundTripsAndStaysApartFromOtherKinds() {
        let kind = SyncedRecordKind.copyDetails(instanceId: 42)
        #expect(kind.recordName == "copy_42")
        #expect(kind.recordType == "CopyDetails")
        #expect(SyncedRecordKind.from(recordName: "copy_42") == kind)
        #expect(SyncedRecordKind.from(recordName: "copy_x") == nil)
        #expect(SyncedRecordKind.from(recordName: "tags_42") == .tag(instanceId: 42))
    }

    @Test func theMostRecentlyEnteredVersionWins() {
        let local = details(10, at: 100)
        #expect(CloudMergeRules.copyDetails(local: local, remote: details(20, at: 200))?.purchaseAmount == 20)
        #expect(CloudMergeRules.copyDetails(local: local, remote: details(20, at: 50)) == nil)
        #expect(CloudMergeRules.copyDetails(local: nil, remote: details(20, at: 50))?.purchaseAmount == 20)
    }

    @Test func aValueTakenFromDiscogsYieldsToARealEdit() {
        let adopted = CopyDetails(purchaseAmount: 10, purchaseCurrency: "EUR", modifiedAt: .distantPast)
        #expect(CloudMergeRules.copyDetails(local: adopted, remote: details(20, at: 5))?.purchaseAmount == 20)
        let edited = details(30, at: 5)
        #expect(CloudMergeRules.copyDetails(local: edited, remote: adopted) == nil)
    }

    @Test func aRemoteClearingReplacesTheLocalValueWhenNewer() {
        let cleared = details(nil, at: 300)
        let result = CloudMergeRules.copyDetails(local: details(10, at: 100), remote: cleared)
        #expect(result?.purchaseAmount == nil)
    }

    @Test func receivingFromICloudKeepsANewerLocalEdit() throws {
        let suite = "CopyDetailsCloudSyncTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = CopyDetailsStore(defaults: defaults)
        store.setActiveUsername("cloud-\(UUID().uuidString)")
        store.setPurchasePrice((15, "EUR"), for: 7)

        store.applyRemote(details(99, at: 1), for: 7)
        #expect(store.purchasePrice(for: 7)?.amount == 15)

        store.applyRemote(details(42, at: Date.now.timeIntervalSince1970 + 60), for: 7)
        #expect(store.purchasePrice(for: 7)?.amount == 42)
        #expect(store.allInstanceIds() == [7])
    }

    @Test func preferencesWithoutTheSendingFlagStillDecode() throws {
        let json = #"{"defaultCurrency":"EUR","defaultAddFolderId":1}"#
        let prefs = try JSONDecoder().decode(SyncedCollectionPreferences.self, from: Data(json.utf8))
        #expect(prefs.sendsCopyDetailsToDiscogs == nil)
    }
}
