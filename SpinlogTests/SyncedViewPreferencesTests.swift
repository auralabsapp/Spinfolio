import Testing
import Foundation
@testable import Spinlog

/// Mode d'affichage et tri de la Collection et de la Wantlist, synchronisés par iCloud dans la charge
/// utile des préférences de collection : compatibilité avec les anciennes charges utiles, valeurs
/// inconnues ignorées, et application sans toucher au reste.
@MainActor
struct SyncedViewPreferencesTests {
    private let username = "tests-vue-synchronisee"

    /// Écrit par une version d'avant ces réglages : aucun champ d'affichage ni de tri.
    private let legacyPayload = Data(#"{"defaultCurrency":"EUR","purchasePriceFieldId":7,"defaultAddFolderId":-1}"#.utf8)

    @Test func aPayloadWrittenBeforeTheseSettingsStillDecodes() throws {
        let prefs = try JSONDecoder().decode(SyncedCollectionPreferences.self, from: legacyPayload)
        #expect(prefs.defaultCurrency == "EUR")
        #expect(prefs.purchasePriceFieldId == 7)
        #expect(prefs.collectionDisplayMode == nil)
        #expect(prefs.collectionSortOption == nil)
        #expect(prefs.wantlistSortAscending == nil)
    }

    @Test func viewPreferencesSurviveAnEncodeDecodeRoundTrip() throws {
        let prefs = SyncedCollectionPreferences(
            defaultCurrency: "EUR", purchasePriceFieldId: nil, mediaConditionFieldId: nil, defaultAddFolderId: -1,
            collectionDisplayMode: "grid", collectionSortOption: "Année", collectionSortAscending: false,
            wantlistDisplayMode: "carousel", wantlistSortOption: "Artiste", wantlistSortAscending: true
        )
        let decoded = try JSONDecoder().decode(SyncedCollectionPreferences.self, from: JSONEncoder().encode(prefs))
        #expect(decoded.collectionDisplayMode == "grid")
        #expect(decoded.collectionSortOption == "Année")
        #expect(decoded.collectionSortAscending == false)
        #expect(decoded.wantlistDisplayMode == "carousel")
        #expect(decoded.wantlistSortOption == "Artiste")
        #expect(decoded.wantlistSortAscending == true)
    }

    @Test func remotePreferencesAreStoredAndUnknownValuesAreIgnored() {
        let defaults = UserDefaults.standard
        let savedModes = [DisplayPreferenceKeys.collection, DisplayPreferenceKeys.wantlist].map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in savedModes { defaults.set(value, forKey: key) }
            CollectionPreferencesStore.clearAccountData(for: username)
        }

        let prefs = SyncedCollectionPreferences(
            defaultCurrency: "EUR", purchasePriceFieldId: nil, mediaConditionFieldId: nil, defaultAddFolderId: -1,
            collectionDisplayMode: "grid", collectionSortOption: CollectionSortOption.year.rawValue, collectionSortAscending: false,
            wantlistDisplayMode: "mode-venu-du-futur", wantlistSortOption: "tri-venu-du-futur", wantlistSortAscending: true
        )
        defaults.set("list", forKey: DisplayPreferenceKeys.wantlist)
        CollectionPreferencesStore.applyRemoteViewPreferences(prefs, for: username)

        #expect(defaults.string(forKey: DisplayPreferenceKeys.collection) == "grid")
        #expect(CollectionPreferencesStore.sortOption(for: username) == .year)
        #expect(CollectionPreferencesStore.sortAscending(for: username) == false)
        // Valeurs inconnues d'une version plus récente : la Wantlist garde son affichage local et n'a pas de tri mémorisé.
        #expect(defaults.string(forKey: DisplayPreferenceKeys.wantlist) == "list")
        #expect(CollectionPreferencesStore.wantlistSortOption(for: username) == nil)
        // Le sens, lui, est valide même si le critère est inconnu.
        #expect(CollectionPreferencesStore.wantlistSortAscending(for: username) == true)
    }

    @Test func absentRemoteValuesLeaveLocalOnesUntouched() {
        defer { CollectionPreferencesStore.clearAccountData(for: username) }
        CollectionPreferencesStore.setWantlistSortOption(.title, for: username)

        let prefs = SyncedCollectionPreferences(
            defaultCurrency: "EUR", purchasePriceFieldId: nil, mediaConditionFieldId: nil, defaultAddFolderId: -1
        )
        CollectionPreferencesStore.applyRemoteViewPreferences(prefs, for: username)

        #expect(CollectionPreferencesStore.wantlistSortOption(for: username) == .title)
    }
}
