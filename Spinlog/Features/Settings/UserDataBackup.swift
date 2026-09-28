import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Modèle de données pour la sauvegarde des données locales de l'utilisateur
nonisolated struct SpinlogUserDataBackup: Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let exportDate: Date
    let discogsUsername: String
    let tagsByRelease: [String: [String]]
    let standaloneTags: [String]
    let appTheme: String?
    let lastConsultedFolderId: Int?
    let collectionSortOption: String?
    let collectionFilterTag: String?
    let collectionFilterFormat: String?

    var totalTagsCount: Int {
        let fromReleases = tagsByRelease.values.flatMap { $0 }
        return Set(fromReleases).union(standaloneTags).count
    }

    var totalReleasesTaggedCount: Int {
        tagsByRelease.count
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
