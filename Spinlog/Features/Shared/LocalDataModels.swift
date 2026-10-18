import Foundation
import SwiftData

// Modèles SwiftData du cache local (`LocalDataStore`) et clés de métadonnées associées.
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

/// Identifiants de `CachedFetchMetadata` ("quand ce dossier/cette wantlist a-t-il été récupéré
/// pour la dernière fois") — avant ces helpers, le même format de chaîne était retapé à la main
/// une dizaine de fois dans `LocalDataStore`, au risque qu'une des copies diverge silencieusement
/// (ex: ordre des composants inversé) sans qu'aucun compilateur ne le détecte.
enum CacheMetaKey {
    static func collection(username: String, folderId: Int) -> String {
        "\(username)_collection_\(folderId)"
    }
    static func wantlist(username: String) -> String {
        "\(username)_wantlist"
    }
}
