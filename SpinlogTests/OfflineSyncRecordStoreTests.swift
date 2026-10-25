import Foundation
import Testing
@testable import Spinlog

/// Date de la dernière synchro hors ligne et nombre de disques archivés, rangés par compte.
struct OfflineSyncRecordStoreTests {
    private func makeStore() throws -> (OfflineSyncRecordStore, UserDefaults, String) {
        let suite = "OfflineSyncRecordStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (OfflineSyncRecordStore(defaults: defaults), defaults, suite)
    }

    @Test func eachAccountKeepsItsOwnSync() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 1_000)

        store.recordSync(at: date, itemCount: 850, for: "alice")

        #expect(store.lastSyncDate(for: "alice") == date)
        #expect(store.itemCount(for: "alice") == 850)
        // Le compte suivant part de zéro : sa synchro auto n'est plus sautée.
        #expect(store.lastSyncDate(for: "bob") == nil)
        #expect(store.itemCount(for: "bob") == 0)
    }

    @Test func noAccountMeansNothingToShow() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.recordSync(at: Date(), itemCount: 3, for: "alice")

        #expect(store.lastSyncDate(for: nil) == nil)
        #expect(store.itemCount(for: nil) == 0)
    }

    @Test func accountNameIsCaseInsensitive() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.recordSync(at: Date(timeIntervalSince1970: 5), itemCount: 2, for: " Alice ")
        #expect(store.itemCount(for: "alice") == 2)
    }

    @Test func clearOnlyForgetsThatAccount() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.recordSync(at: Date(), itemCount: 1, for: "alice")
        store.recordSync(at: Date(), itemCount: 2, for: "bob")

        store.clear(for: "alice")

        #expect(store.lastSyncDate(for: "alice") == nil)
        #expect(store.itemCount(for: "bob") == 2)
    }

    @Test func legacyValueGoesToTheFirstAccountThenDisappears() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyDate = Date(timeIntervalSince1970: 42)
        defaults.set(legacyDate, forKey: OfflineSyncRecordStore.legacyDateKey)
        defaults.set(120, forKey: OfflineSyncRecordStore.legacyCountKey)

        store.migrateLegacyIfNeeded(to: "alice")
        store.migrateLegacyIfNeeded(to: "bob")

        #expect(store.lastSyncDate(for: "alice") == legacyDate)
        #expect(store.itemCount(for: "alice") == 120)
        #expect(store.lastSyncDate(for: "bob") == nil)
        #expect(defaults.object(forKey: OfflineSyncRecordStore.legacyDateKey) == nil)
        #expect(defaults.object(forKey: OfflineSyncRecordStore.legacyCountKey) == nil)
    }

    @Test func migrationNeverOverwritesAnExistingAccountValue() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let current = Date(timeIntervalSince1970: 100)
        store.recordSync(at: current, itemCount: 7, for: "alice")
        defaults.set(Date(timeIntervalSince1970: 1), forKey: OfflineSyncRecordStore.legacyDateKey)

        store.migrateLegacyIfNeeded(to: "alice")

        #expect(store.lastSyncDate(for: "alice") == current)
        #expect(store.itemCount(for: "alice") == 7)
    }
}
