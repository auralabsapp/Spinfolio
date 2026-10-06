import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Modèle de données pour la sauvegarde des données locales de l'utilisateur
nonisolated struct SpinlogUserDataBackup: Codable, Sendable {
    static let currentVersion = 4

    let version: Int
    let exportDate: Date
    let discogsUsername: String
    let tagsByInstance: [String: [String]]?
    let tagsByRelease: [String: [String]]
    let standaloneTags: [String]
    let appTheme: String?
    let appColorTheme: String?
    /// Table de correspondance locale masterId -> année de sortie originale (`MasterRecord`),
    /// pour éviter de tout re-résoudre via l'API Masters (cadencée à 1 req/1,5s) après restauration.
    let masterYears: [Int: Int]?
    /// Sessions du journal d'écoute
    let listeningSessions: [ListeningSession]?

    // État de la collection (dossiers, tri et filtres)
    let lastConsultedFolderId: Int?
    let lastConsultedFolderName: String?
    let collectionSortOption: String?
    let collectionFilterTags: [String]
    let collectionFilterFormat: String?
    let collectionFolders: [CollectionFolder]?
    /// Personnalisations manuelles de tri des artistes (voir `ShelfPreferencesStore`).
    let customArtistSortOverrides: [String: String]?

    var totalTagsCount: Int {
        let fromInstances = tagsByInstance?.values.flatMap { $0 } ?? []
        let fromReleases = tagsByRelease.values.flatMap { $0 }
        return Set(fromInstances).union(fromReleases).union(standaloneTags).count
    }

    var totalInstancesTaggedCount: Int {
        tagsByInstance?.count ?? tagsByRelease.count
    }

    var totalReleasesTaggedCount: Int {
        totalInstancesTaggedCount
    }

    enum CodingKeys: String, CodingKey {
        case version
        case exportDate
        case discogsUsername
        case tagsByInstance
        case tagsByRelease
        case standaloneTags
        case appTheme
        case appColorTheme
        case masterYears
        case listeningSessions
        case lastConsultedFolderId
        case lastConsultedFolderName
        case collectionSortOption
        case collectionFilterTags
        /// Ancienne clé (filtre mono-tag) : conservée uniquement pour décoder d'anciennes
        /// sauvegardes, plus jamais écrite à l'exportation.
        case collectionFilterTagLegacy = "collectionFilterTag"
        case collectionFilterFormat
        case collectionFolders
        case customArtistSortOverrides
    }

    init(
        version: Int = currentVersion,
        exportDate: Date = Date(),
        discogsUsername: String,
        tagsByInstance: [String: [String]]? = nil,
        tagsByRelease: [String: [String]] = [:],
        standaloneTags: [String],
        appTheme: String?,
        appColorTheme: String? = nil,
        masterYears: [Int: Int]? = nil,
        listeningSessions: [ListeningSession]? = nil,
        lastConsultedFolderId: Int?,
        lastConsultedFolderName: String? = nil,
        collectionSortOption: String?,
        collectionFilterTags: [String],
        collectionFilterFormat: String?,
        collectionFolders: [CollectionFolder]? = nil,
        customArtistSortOverrides: [String: String]? = nil
    ) {
        self.version = version
        self.exportDate = exportDate
        self.discogsUsername = discogsUsername
        self.tagsByInstance = tagsByInstance
        self.tagsByRelease = tagsByRelease
        self.standaloneTags = standaloneTags
        self.appTheme = appTheme
        self.appColorTheme = appColorTheme
        self.masterYears = masterYears
        self.listeningSessions = listeningSessions
        self.lastConsultedFolderId = lastConsultedFolderId
        self.lastConsultedFolderName = lastConsultedFolderName
        self.collectionSortOption = collectionSortOption
        self.collectionFilterTags = collectionFilterTags
        self.collectionFilterFormat = collectionFilterFormat
        self.collectionFolders = collectionFolders
        self.customArtistSortOverrides = customArtistSortOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportDate = try container.decode(Date.self, forKey: .exportDate)
        discogsUsername = try container.decode(String.self, forKey: .discogsUsername)
        tagsByInstance = try container.decodeIfPresent([String: [String]].self, forKey: .tagsByInstance)
        tagsByRelease = try container.decodeIfPresent([String: [String]].self, forKey: .tagsByRelease) ?? [:]
        standaloneTags = try container.decodeIfPresent([String].self, forKey: .standaloneTags) ?? []
        appTheme = try container.decodeIfPresent(String.self, forKey: .appTheme)
        appColorTheme = try container.decodeIfPresent(String.self, forKey: .appColorTheme)
        masterYears = try container.decodeIfPresent([Int: Int].self, forKey: .masterYears)
        listeningSessions = try container.decodeIfPresent([ListeningSession].self, forKey: .listeningSessions)
        lastConsultedFolderId = try container.decodeIfPresent(Int.self, forKey: .lastConsultedFolderId)
        lastConsultedFolderName = try container.decodeIfPresent(String.self, forKey: .lastConsultedFolderName)
        collectionSortOption = try container.decodeIfPresent(String.self, forKey: .collectionSortOption)
        if let tags = try container.decodeIfPresent([String].self, forKey: .collectionFilterTags) {
            collectionFilterTags = tags
        } else if let legacyTag = try container.decodeIfPresent(String.self, forKey: .collectionFilterTagLegacy), !legacyTag.isEmpty {
            // Anciennes sauvegardes (filtre mono-tag, avant le passage au multi-tag).
            collectionFilterTags = [legacyTag]
        } else {
            collectionFilterTags = []
        }
        collectionFilterFormat = try container.decodeIfPresent(String.self, forKey: .collectionFilterFormat)
        collectionFolders = try container.decodeIfPresent([CollectionFolder].self, forKey: .collectionFolders)
        customArtistSortOverrides = try container.decodeIfPresent([String: String].self, forKey: .customArtistSortOverrides)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(exportDate, forKey: .exportDate)
        try container.encode(discogsUsername, forKey: .discogsUsername)
        if let tagsByInstance {
            try container.encode(tagsByInstance, forKey: .tagsByInstance)
        }
        // tagsByRelease est conservé uniquement pour décoder d'anciennes sauvegardes ; il n'est
        // plus jamais écrit à l'exportation, quelle que soit la valeur passée par l'appelant.
        try container.encode(standaloneTags, forKey: .standaloneTags)
        try container.encodeIfPresent(appTheme, forKey: .appTheme)
        try container.encodeIfPresent(appColorTheme, forKey: .appColorTheme)
        if let masterYears, !masterYears.isEmpty {
            try container.encode(masterYears, forKey: .masterYears)
        }
        if let listeningSessions, !listeningSessions.isEmpty {
            try container.encode(listeningSessions, forKey: .listeningSessions)
        }

        // Ces champs sont TOUJOURS encodés de manière explicite dans le JSON
        try container.encode(lastConsultedFolderId ?? 0, forKey: .lastConsultedFolderId)
        if let lastConsultedFolderName {
            try container.encode(lastConsultedFolderName, forKey: .lastConsultedFolderName)
        }
        try container.encode(collectionSortOption ?? CollectionSortOption.artist.rawValue, forKey: .collectionSortOption)
        try container.encode(collectionFilterTags, forKey: .collectionFilterTags)
        try container.encode(collectionFilterFormat ?? "", forKey: .collectionFilterFormat)
        if let collectionFolders, !collectionFolders.isEmpty {
            try container.encode(collectionFolders, forKey: .collectionFolders)
        }
        if let customArtistSortOverrides, !customArtistSortOverrides.isEmpty {
            try container.encode(customArtistSortOverrides, forKey: .customArtistSortOverrides)
        }
    }
}

/// Document de fichier gérant l'exportation et la lecture via les API système SwiftUI
struct SpinlogBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var backup: SpinlogUserDataBackup

    init(backup: SpinlogUserDataBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.backup = try decoder.decode(SpinlogUserDataBackup.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        return FileWrapper(regularFileWithContents: data)
    }
}
