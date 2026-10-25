import Foundation
import Testing
@testable import Spinlog

/// Réglages de rangement propres à chaque compte, reprise des réglages globaux d'avant, effacement.
@MainActor
struct ShelfPreferencesStoreTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "ShelfPreferencesStoreTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test func eachAccountKeepsItsOwnSettings() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShelfPreferencesStore(defaults: defaults)

        store.setActiveUsername("alice")
        store.sortByLastName = true
        store.setCustomSort(for: "The Beatles", sortKey: "Beatles")

        store.setActiveUsername("bob")
        #expect(store.sortByLastName == false)
        #expect(store.customArtistSortOverrides.isEmpty)

        store.setActiveUsername("Alice")
        #expect(store.sortByLastName)
        #expect(store.customSort(for: "The Beatles") == "Beatles")
    }

    @Test func legacyGlobalSettingsGoToTheFirstAccountOnly() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ShelfPreferenceKeys.sortByLastName)
        defaults.set(["Bowie": "Bowie, David"], forKey: ShelfPreferenceKeys.customArtistOverrides)
        let store = ShelfPreferencesStore(defaults: defaults)

        store.setActiveUsername("alice")
        #expect(store.sortByLastName)
        #expect(store.customArtistSortOverrides == ["Bowie": "Bowie, David"])
        #expect(defaults.object(forKey: ShelfPreferenceKeys.sortByLastName) == nil)

        store.setActiveUsername("bob")
        #expect(store.sortByLastName == false)
    }

    @Test func demoNeverTakesTheLegacySettings() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ShelfPreferenceKeys.restrictToSameFolder)
        let store = ShelfPreferencesStore(defaults: defaults)

        store.setActiveUsername(DemoMode.username)
        #expect(store.restrictToSameFolder == false)
        // Toujours là pour le vrai compte.
        #expect(defaults.object(forKey: ShelfPreferenceKeys.restrictToSameFolder) != nil)
    }

    @Test func clearingAnAccountRemovesOnlyItsSettings() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShelfPreferencesStore(defaults: defaults)
        store.setActiveUsername("bob")
        store.ignoreArticles = false
        store.setActiveUsername("alice")
        store.ignoreArticles = false
        store.setCustomSort(for: "Prince", sortKey: "Prince (artiste)")

        store.clearAccountData(for: "alice")

        #expect(store.ignoreArticles)
        #expect(store.customArtistSortOverrides.isEmpty)
        for base in ShelfPreferenceKeys.all {
            #expect(defaults.object(forKey: ShelfPreferenceKeys.key(base, for: "alice")) == nil)
        }
        #expect(defaults.object(forKey: ShelfPreferenceKeys.key(ShelfPreferenceKeys.ignoreArticles, for: "bob")) as? Bool == false)
    }

    @Test func nothingIsWrittenWithoutAnAccount() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShelfPreferencesStore(defaults: defaults)
        store.sortByLastName = true
        #expect(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("com.spinlog.shelf") } == false)
    }
}

/// Données laissées par « Supprimer mes données » et la déconnexion.
@MainActor
struct AccountLeftoversTests {
    @Test func batchScanDraftIsClearedForThatAccountOnly() throws {
        let suite = "AccountLeftoversTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1]), forKey: BatchScanViewModel.draftKey(for: "alice"))
        defaults.set(Data([2]), forKey: BatchScanViewModel.draftKey(for: "bob"))

        BatchScanViewModel.clearDraft(for: " Alice ", defaults: defaults)

        #expect(defaults.data(forKey: BatchScanViewModel.draftKey(for: "alice")) == nil)
        #expect(defaults.data(forKey: BatchScanViewModel.draftKey(for: "bob")) != nil)
    }

    @Test(arguments: ["discogs.com", "google.com", "accounts.google.com", "apple.com", "facebook.com"])
    func identityProviderSessionsAreClearedAtLogout(_ displayName: String) {
        #expect(DiscogsWebPolicy.isSessionRecord(displayName: displayName))
    }

    @Test(arguments: ["youtube.com", "example.com", "notgoogle.com"])
    func otherSitesAreKept(_ displayName: String) {
        #expect(!DiscogsWebPolicy.isSessionRecord(displayName: displayName))
    }

    @Test func droppedOfflineActionsAreAllListed() {
        let first = OfflineSyncQueue.combinedFailureMessage(nil, adding: "A")
        #expect(first == "A")
        #expect(OfflineSyncQueue.combinedFailureMessage(first, adding: "B") == "A\nB")
    }
}
