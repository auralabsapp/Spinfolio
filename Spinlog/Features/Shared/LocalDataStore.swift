import Foundation
import SwiftData

@Model
final class CachedCollectionEntry {
    @Attribute(.unique) var id: String
    var username: String
    var folderId: Int
    var releaseId: Int
    var instanceId: Int
    var payload: Data
    var lastFetchedAt: Date

    init(username: String, folderId: Int, releaseId: Int, instanceId: Int, payload: Data, lastFetchedAt: Date = Date()) {
        self.id = "\(username)_\(folderId)_\(instanceId)"
        self.username = username
        self.folderId = folderId
        self.releaseId = releaseId
        self.instanceId = instanceId
        self.payload = payload
        self.lastFetchedAt = lastFetchedAt
    }
}

@Model
final class CachedWantlistEntry {
    @Attribute(.unique) var id: String
    var username: String
    var releaseId: Int
    var payload: Data
    var lastFetchedAt: Date

    init(username: String, releaseId: Int, payload: Data, lastFetchedAt: Date = Date()) {
        self.id = "\(username)_\(releaseId)"
        self.username = username
        self.releaseId = releaseId
        self.payload = payload
        self.lastFetchedAt = lastFetchedAt
    }
}

@Model
final class CachedFolderEntry {
    @Attribute(.unique) var id: String
    var username: String
    var folderId: Int
    var payload: Data
    var lastFetchedAt: Date

    init(username: String, folderId: Int, payload: Data, lastFetchedAt: Date = Date()) {
        self.id = "\(username)_\(folderId)"
        self.username = username
        self.folderId = folderId
        self.payload = payload
        self.lastFetchedAt = lastFetchedAt
    }
}

@Model
final class CachedFetchMetadata {
    @Attribute(.unique) var id: String
    var lastFetchedAt: Date

    init(id: String, lastFetchedAt: Date = Date()) {
        self.id = id
        self.lastFetchedAt = lastFetchedAt
    }
}

/// Gestionnaire de persistance locale basé sur SwiftData avec règle de TTL de 6 heures.
@MainActor
final class LocalDataStore {
    static let shared = LocalDataStore()

    /// Time-To-Live de 6 heures (21600 secondes) conformément aux contraintes.
    static let ttlSeconds: TimeInterval = 6 * 3600

    private let container: ModelContainer
    private let context: ModelContext

    private init() {
        let schema = Schema([
            CachedCollectionEntry.self,
            CachedWantlistEntry.self,
            CachedFolderEntry.self,
            CachedFetchMetadata.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            context = ModelContext(container)
        } catch {
            // Fallback en mémoire en cas d'erreur de schéma
            let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = (try? ModelContainer(for: schema, configurations: [inMemoryConfig]))
                ?? (try! ModelContainer(for: Schema([]), configurations: []))
            context = ModelContext(container)
        }
    }

    // MARK: - Collection

    func saveCollectionItems(_ items: [CollectionItem], username: String, folderId: Int) {
        let now = Date()
        let encoder = JSONEncoder()

        for item in items {
            guard let data = try? encoder.encode(item) else { continue }
            let entry = CachedCollectionEntry(
                username: username,
                folderId: folderId,
                releaseId: item.releaseId,
                instanceId: item.instanceId,
                payload: data,
                lastFetchedAt: now
            )
            context.insert(entry)
        }

        // Met à jour l'horodatage global pour ce dossier
        let metaId = "\(username)_collection_\(folderId)"
        let meta = CachedFetchMetadata(id: metaId, lastFetchedAt: now)
        context.insert(meta)

        try? context.save()
    }

    func getCollectionItems(username: String, folderId: Int) -> [CollectionItem] {
        let descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> {
                $0.username == username && $0.folderId == folderId
            }
        )
        guard let entries = try? context.fetch(descriptor) else { return [] }
        let decoder = JSONDecoder()
        return entries.compactMap { try? decoder.decode(CollectionItem.self, from: $0.payload) }
    }

    func removeCollectionItem(username: String, folderId: Int, instanceId: Int) {
        let targetId = "\(username)_\(folderId)_\(instanceId)"
        let descriptor = FetchDescriptor<CachedCollectionEntry>(
            predicate: #Predicate<CachedCollectionEntry> { $0.id == targetId }
        )
        if let entries = try? context.fetch(descriptor) {
            for entry in entries {
                context.delete(entry)
            }
            try? context.save()
        }
    }

    func lastCollectionFetchedAt(username: String, folderId: Int) -> Date? {
        let targetId = "\(username)_collection_\(folderId)"
        let descriptor = FetchDescriptor<CachedFetchMetadata>(
            predicate: #Predicate<CachedFetchMetadata> { $0.id == targetId }
        )
        return (try? context.fetch(descriptor))?.first?.lastFetchedAt
    }

    func isCollectionStale(username: String, folderId: Int) -> Bool {
        guard let date = lastCollectionFetchedAt(username: username, folderId: folderId) else {
            return true
        }
        return Date().timeIntervalSince(date) >= Self.ttlSeconds
    }

    // MARK: - Wantlist

    func saveWantlistItems(_ items: [WantlistItem], username: String) {
        let now = Date()
        let encoder = JSONEncoder()

        for item in items {
            guard let data = try? encoder.encode(item) else { continue }
            let entry = CachedWantlistEntry(
                username: username,
                releaseId: item.id,
                payload: data,
                lastFetchedAt: now
            )
            context.insert(entry)
        }

        let metaId = "\(username)_wantlist"
        let meta = CachedFetchMetadata(id: metaId, lastFetchedAt: now)
        context.insert(meta)

        try? context.save()
    }

    func getWantlistItems(username: String) -> [WantlistItem] {
        let descriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.username == username }
        )
        guard let entries = try? context.fetch(descriptor) else { return [] }
        let decoder = JSONDecoder()
        return entries.compactMap { try? decoder.decode(WantlistItem.self, from: $0.payload) }
    }

    func removeWantlistItem(username: String, releaseId: Int) {
        let targetId = "\(username)_\(releaseId)"
        let descriptor = FetchDescriptor<CachedWantlistEntry>(
            predicate: #Predicate<CachedWantlistEntry> { $0.id == targetId }
        )
        if let entries = try? context.fetch(descriptor) {
            for entry in entries {
                context.delete(entry)
            }
            try? context.save()
        }
    }

    func lastWantlistFetchedAt(username: String) -> Date? {
        let targetId = "\(username)_wantlist"
        let descriptor = FetchDescriptor<CachedFetchMetadata>(
            predicate: #Predicate<CachedFetchMetadata> { $0.id == targetId }
        )
        return (try? context.fetch(descriptor))?.first?.lastFetchedAt
    }

    func isWantlistStale(username: String) -> Bool {
        guard let date = lastWantlistFetchedAt(username: username) else {
            return true
        }
        return Date().timeIntervalSince(date) >= Self.ttlSeconds
    }

    // MARK: - Dossiers

    func saveFolders(_ folders: [CollectionFolder], username: String) {
        let now = Date()
        let encoder = JSONEncoder()
        for folder in folders {
            guard let data = try? encoder.encode(folder) else { continue }
            let entry = CachedFolderEntry(
                username: username,
                folderId: folder.id,
                payload: data,
                lastFetchedAt: now
            )
            context.insert(entry)
        }
        try? context.save()
    }

    func getFolders(username: String) -> [CollectionFolder] {
        let descriptor = FetchDescriptor<CachedFolderEntry>(
            predicate: #Predicate<CachedFolderEntry> { $0.username == username }
        )
        guard let entries = try? context.fetch(descriptor) else { return [] }
        let decoder = JSONDecoder()
        return entries.compactMap { try? decoder.decode(CollectionFolder.self, from: $0.payload) }
    }
}
