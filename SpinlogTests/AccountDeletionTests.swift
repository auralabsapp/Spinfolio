import Foundation
import Testing
@testable import Spinlog

/// « Supprimer mon compte » doit effacer toutes les préférences du compte, et seulement les siennes.
@MainActor
struct AccountDeletionTests {
    @Test func clearsEveryPreferenceOfTheAccountOnly() throws {
        let suiteName = "AccountDeletionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("year", forKey: "com.spinlog.pref_alice_sortOption")
        defaults.set(12, forKey: "com.spinlog.pref_alice_defaultAddFolderId")
        defaults.set(3, forKey: "com.spinlog.lastConsultedFolder_alice")
        defaults.set("artist", forKey: "com.spinlog.pref_bob_sortOption")
        // Un compte dont le nom commence comme celui d'Alice ne doit pas être touché.
        defaults.set("title", forKey: "com.spinlog.pref_alicette_sortOption")

        CollectionPreferencesStore.clearAccountData(for: " Alice ", defaults: defaults)

        #expect(defaults.object(forKey: "com.spinlog.pref_alice_sortOption") == nil)
        #expect(defaults.object(forKey: "com.spinlog.pref_alice_defaultAddFolderId") == nil)
        #expect(defaults.object(forKey: "com.spinlog.lastConsultedFolder_alice") == nil)
        #expect(defaults.string(forKey: "com.spinlog.pref_bob_sortOption") == "artist")
        #expect(defaults.string(forKey: "com.spinlog.pref_alicette_sortOption") == "title")
    }
}
