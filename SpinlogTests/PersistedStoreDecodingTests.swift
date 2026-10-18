import Foundation
import Testing
@testable import Spinlog

/// Un élément abîmé ne doit plus faire perdre tout un store (tags, écoutes, alertes, file).
@MainActor
struct PersistedStoreDecodingTests {
    private struct Item: Codable, Equatable {
        let id: Int
        let name: String
    }

    private let suiteName = "PersistedStoreDecodingTests-\(UUID().uuidString)"
    private let key = "store"

    private func withDefaults(_ json: String?, _ body: (UserDefaults) throws -> Void) rethrows {
        let defaults = UserDefaults(suiteName: suiteName)!
        if let json { defaults.set(Data(json.utf8), forKey: key) }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test func missingKeyReturnsNil() {
        withDefaults(nil) { defaults in
            #expect(PersistedStoreDecoding.decodeArray(Item.self, forKey: key, defaults: defaults) == nil)
        }
    }

    @Test func validArrayIsReadWithoutBackup() {
        withDefaults(#"[{"id":1,"name":"a"},{"id":2,"name":"b"}]"#) { defaults in
            let items = PersistedStoreDecoding.decodeArray(Item.self, forKey: key, defaults: defaults)
            #expect(items == [Item(id: 1, name: "a"), Item(id: 2, name: "b")])
            #expect(defaults.data(forKey: PersistedStoreDecoding.backupKey(for: key)) == nil)
        }
    }

    @Test func unreadableElementsAreSkippedAndOriginalIsBackedUp() {
        let json = #"[{"id":1,"name":"a"},{"id":"oops"},"texte",42,{"id":3,"name":"c"}]"#
        withDefaults(json) { defaults in
            let items = PersistedStoreDecoding.decodeArray(Item.self, forKey: key, defaults: defaults)
            #expect(items == [Item(id: 1, name: "a"), Item(id: 3, name: "c")])
            #expect(defaults.data(forKey: PersistedStoreDecoding.backupKey(for: key)) == Data(json.utf8))
        }
    }

    @Test func unreadableStructureKeepsTheOriginalBytes() {
        let json = #"{"pas":"un tableau"}"#
        withDefaults(json) { defaults in
            #expect(PersistedStoreDecoding.decodeArray(Item.self, forKey: key, defaults: defaults) == [])
            #expect(defaults.data(forKey: PersistedStoreDecoding.backupKey(for: key)) == Data(json.utf8))
        }
    }

    @Test func firstBackupIsNeverOverwritten() {
        let original = #"[{"id":1,"name":"a"},{"id":"oops"}]"#
        withDefaults(original) { defaults in
            _ = PersistedStoreDecoding.decodeArray(Item.self, forKey: key, defaults: defaults)
            defaults.set(Data(#"[{"bad":true}]"#.utf8), forKey: key)
            _ = PersistedStoreDecoding.decodeArray(Item.self, forKey: key, defaults: defaults)
            #expect(defaults.data(forKey: PersistedStoreDecoding.backupKey(for: key)) == Data(original.utf8))
        }
    }

    @Test func dictionaryKeepsReadableEntriesOfEachArray() {
        let json = #"{"10":[{"id":1,"name":"a"},{"id":"oops"}],"20":[{"id":2,"name":"b"}]}"#
        withDefaults(json) { defaults in
            let dict = PersistedStoreDecoding.decodeDictionaryOfArrays(Item.self, forKey: key, defaults: defaults)
            #expect(dict?["10"] == [Item(id: 1, name: "a")])
            #expect(dict?["20"] == [Item(id: 2, name: "b")])
            #expect(defaults.data(forKey: PersistedStoreDecoding.backupKey(for: key)) != nil)
        }
    }

    @Test func pendingActionsSurviveOneCorruptedEntry() throws {
        let valid = PendingAction(type: .addToWantlist, releaseId: 5)
        let validJSON = try #require(String(data: JSONEncoder().encode(valid), encoding: .utf8))
        withDefaults("[\(validJSON),{\"type\":\"inconnu\"}]") { defaults in
            let actions = PersistedStoreDecoding.decodeArray(PendingAction.self, forKey: key, defaults: defaults)
            #expect(actions?.map(\.releaseId) == [5])
        }
    }
}
