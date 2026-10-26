import Foundation
import Testing
@testable import Spinlog

/// Fusion des données reçues d'iCloud : tags, tags autonomes, personnalisations de rangement,
/// réglages scalaires, et lecture des enregistrements écrits par une autre version de l'app.
@MainActor
struct CloudMergeRulesTests {
    private func tag(_ name: String, _ seconds: TimeInterval) -> SyncedTag {
        SyncedTag(name: name, addedAt: Date(timeIntervalSinceReferenceDate: seconds))
    }

    // MARK: - Tags d'un exemplaire

    @Test func tagsAreReplacedByTheRemoteStateOutsideTheInitialReconciliation() {
        let result = CloudMergeRules.tags(local: [tag("Jazz", 1), tag("Rare", 2)], remote: [tag("Jazz", 1)], allowMerge: false)
        #expect(result == [tag("Jazz", 1)])
    }

    @Test func aDeletionDoneOnAnotherDevicePropagatesAnEmptyRemote() {
        let result = CloudMergeRules.tags(local: [tag("Jazz", 1)], remote: [], allowMerge: false)
        #expect(result.isEmpty)
    }

    @Test func tagsAreUnitedDuringTheInitialReconciliation() {
        let result = CloudMergeRules.tags(local: [tag("Rare", 2)], remote: [tag("Jazz", 1)], allowMerge: true)
        #expect(result.map(\.name) == ["Jazz", "Rare"])
    }

    @Test func aLocalOnlyDeviceKeepsItsTagsWhenTheRemoteIsEmpty() {
        let result = CloudMergeRules.tags(local: [tag("Rare", 2)], remote: [], allowMerge: true)
        #expect(result == [tag("Rare", 2)])
    }

    // MARK: - Tags autonomes

    @Test func standaloneTagsAreUnitedDuringTheInitialReconciliation() {
        let result = CloudMergeRules.standaloneTags(local: ["Rock", "Live"], remote: ["Live", "Jazz"], allowMerge: true)
        #expect(result == ["Rock", "Live", "Jazz"])
    }

    @Test func standaloneTagsFollowTheRemoteOtherwise() {
        let result = CloudMergeRules.standaloneTags(local: ["Rock", "Live"], remote: ["Live"], allowMerge: false)
        #expect(result == ["Live"])
        #expect(CloudMergeRules.standaloneTags(local: ["Rock"], remote: [], allowMerge: false).isEmpty)
    }

    // MARK: - Personnalisations de rangement

    @Test func shelfOverridesKeepLocalOnlyEntriesWhenMerging() {
        let result = CloudMergeRules.shelfOverrides(local: ["Bowie": "Bowie, David"], remote: ["Prince": "Prince"], allowMerge: true)
        #expect(result == ["Bowie": "Bowie, David", "Prince": "Prince"])
    }

    @Test func theServerWinsOnTheSameArtistWhenMerging() {
        let result = CloudMergeRules.shelfOverrides(local: ["Bowie": "Local"], remote: ["Bowie": "Serveur"], allowMerge: true)
        #expect(result == ["Bowie": "Serveur"])
    }

    @Test func shelfOverridesAreReplacedOutsideTheInitialReconciliation() {
        let result = CloudMergeRules.shelfOverrides(local: ["Bowie": "Local", "Prince": "Prince"], remote: ["Bowie": "Serveur"], allowMerge: false)
        #expect(result == ["Bowie": "Serveur"])
        #expect(CloudMergeRules.shelfOverrides(local: ["Bowie": "Local"], remote: [:], allowMerge: false).isEmpty)
    }

    // MARK: - Réglages scalaires

    @Test func knownSettingsAreTakenFromTheRemote() {
        #expect(CloudMergeRules.setting(rawValue: "chronologicalOnly", fallback: ShelfSortStrategy.artistThenTitle) == .chronologicalOnly)
        #expect(CloudMergeRules.setting(rawValue: "cobalt", fallback: AppColorTheme.signature) == .cobalt)
    }

    @Test func aSettingUnknownToThisVersionKeepsTheCurrentValue() {
        #expect(CloudMergeRules.setting(rawValue: "futureStrategy", fallback: ShelfSortStrategy.artistThenTitle) == .artistThenTitle)
        #expect(CloudMergeRules.setting(rawValue: "futureTheme", fallback: AppColorTheme.velvet) == .velvet)
        #expect(CloudMergeRules.setting(rawValue: "futureAppearance", fallback: AppTheme.dark) == .dark)
    }

    // MARK: - Enregistrements écrits par une autre version

    @Test func shelfPreferencesWithoutTheRecentFieldStillDecode() throws {
        let json = """
        {"sortStrategy":"artistThenTitle","ignoreArticles":true,"sortByLastName":false,"customArtistSortOverrides":{"Bowie":"Bowie, David"}}
        """
        let prefs = try JSONDecoder().decode(SyncedShelfPreferences.self, from: Data(json.utf8))
        #expect(prefs.restrictToSameFolder == false)
        #expect(prefs.ignoreArticles)
        #expect(prefs.customArtistSortOverrides == ["Bowie": "Bowie, David"])
    }

    @Test func wantlistAlertKeepsItsTrackingFieldsThroughTheSyncPayload() throws {
        let alert = WantlistAlert(
            releaseId: 42, albumTitle: "Blue", artistName: "Joni Mitchell", coverURL: nil,
            targetPrice: 20, currency: "EUR", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_800_003_600), lastNotifiedPrice: 18,
            currentLowestPrice: 17.5, currentLowestPriceCurrency: "EUR", currentNumForSale: 3
        )
        let decoded = try JSONDecoder().decode(WantlistAlert.self, from: JSONEncoder().encode(alert))
        #expect(decoded == alert)
    }

    @Test func wantlistAlertWithoutTrackingFieldsStillDecodes() throws {
        let json = """
        {"releaseId":42,"albumTitle":"Blue","artistName":"Joni Mitchell","targetPrice":20,"currency":"EUR","createdAt":0}
        """
        let decoded = try JSONDecoder().decode(WantlistAlert.self, from: Data(json.utf8))
        #expect(decoded.lastNotifiedPrice == nil)
        #expect(decoded.currentLowestPrice == nil)
        #expect(!decoded.isTriggered)
    }
}

/// Réglages appliqués depuis iCloud : propres à chaque compte, sans écraser les autres.
@MainActor
struct RemotePreferencesApplyTests {
    @Test func remoteShelfPreferencesAreStoredForTheActiveAccountOnly() throws {
        let suite = "RemotePreferencesApplyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShelfPreferencesStore(defaults: defaults)

        store.setActiveUsername("alice")
        store.applyRemoteShelfPreferences(
            sortStrategy: .chronologicalOnly, ignoreArticles: true, sortByLastName: true,
            restrictToSameFolder: true, customArtistSortOverrides: ["Bowie": "Bowie, David"]
        )
        #expect(store.sortStrategy == .chronologicalOnly)
        #expect(store.restrictToSameFolder)

        // Le compte B ne voit rien de ce qui vient d'être reçu pour A, et A le retrouve ensuite.
        store.setActiveUsername("bob")
        #expect(store.sortStrategy == .artistThenMasterYear)
        #expect(store.customArtistSortOverrides.isEmpty)
        store.setActiveUsername("alice")
        #expect(store.sortStrategy == .chronologicalOnly)
        #expect(store.customArtistSortOverrides == ["Bowie": "Bowie, David"])
    }

    @Test func remoteCollectionPreferencesAreStoredPerAccount() {
        let alice = "remote-prefs-alice-\(UUID().uuidString)"
        let bob = "remote-prefs-bob-\(UUID().uuidString)"
        defer {
            CollectionPreferencesStore.clearAccountData(for: alice)
            CollectionPreferencesStore.clearAccountData(for: bob)
        }

        CollectionPreferencesStore.applyRemotePreferences(
            currency: "USD", purchasePriceFieldId: 7, mediaConditionFieldId: 8, defaultAddFolderId: 12, for: alice
        )
        #expect(CollectionPreferencesStore.defaultCurrency(for: alice) == "USD")
        #expect(CollectionPreferencesStore.purchasePriceFieldId(for: alice) == 7)
        #expect(CollectionPreferencesStore.mediaConditionFieldId(for: alice) == 8)
        #expect(CollectionPreferencesStore.defaultAddFolderId(for: alice) == 12)
        #expect(CollectionPreferencesStore.defaultCurrency(for: bob) == "EUR")
        #expect(CollectionPreferencesStore.purchasePriceFieldId(for: bob) == nil)
    }

    @Test func aFieldClearedOnAnotherDeviceIsClearedHere() {
        let user = "remote-prefs-clear-\(UUID().uuidString)"
        defer { CollectionPreferencesStore.clearAccountData(for: user) }

        CollectionPreferencesStore.applyRemotePreferences(
            currency: "EUR", purchasePriceFieldId: 7, mediaConditionFieldId: 8, defaultAddFolderId: 1, for: user
        )
        CollectionPreferencesStore.applyRemotePreferences(
            currency: "EUR", purchasePriceFieldId: nil, mediaConditionFieldId: 8, defaultAddFolderId: 1, for: user
        )
        #expect(CollectionPreferencesStore.purchasePriceFieldId(for: user) == nil)
        #expect(CollectionPreferencesStore.mediaConditionFieldId(for: user) == 8)
    }
}
