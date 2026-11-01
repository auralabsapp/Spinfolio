import Foundation
import Testing
@testable import Spinlog

/// Sauvegarde JSON des données locales : vérification d'un fichier avant restauration, nom de fichier, messages.
@MainActor
struct UserDataBackupServiceTests {
    private func data(username: String) throws -> Data {
        let backup = SpinlogUserDataBackup(
            version: SpinlogUserDataBackup.currentVersion,
            exportDate: Date(timeIntervalSince1970: 1_800_000_000),
            discogsUsername: username,
            tagsByInstance: ["1": ["Jazz"], "2": ["Jazz", "Live"]],
            tagsByRelease: [:],
            standaloneTags: ["Jazz", "Live"],
            appTheme: nil,
            appColorTheme: nil,
            masterYears: nil,
            listeningSessions: nil,
            lastConsultedFolderId: nil,
            lastConsultedFolderName: nil,
            collectionSortOption: nil,
            collectionFilterTags: [],
            collectionFilterFormat: nil,
            collectionFolders: nil,
            customArtistSortOverrides: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    @Test func fileOfTheSameAccountIsAccepted() throws {
        let verdict = UserDataBackupService.check(data: try data(username: "Alice"), currentUsername: " alice ", isAuthenticated: true)
        guard case .accepted(let backup) = verdict else { Issue.record("fichier refusé à tort"); return }
        #expect(backup.discogsUsername == "Alice")
    }

    @Test func fileOfAnotherAccountIsRefused() throws {
        let verdict = UserDataBackupService.check(data: try data(username: "Alice"), currentUsername: "Bob", isAuthenticated: true)
        guard case .wrongAccount(let backupUser, let currentUser) = verdict else { Issue.record("compte différent accepté"); return }
        #expect(backupUser == "Alice" && currentUser == "Bob")
    }

    @Test func signedOutUserCannotRestore() throws {
        let verdict = UserDataBackupService.check(data: try data(username: "Alice"), currentUsername: nil, isAuthenticated: false)
        guard case .notSignedIn = verdict else { Issue.record("restauration permise sans compte"); return }
    }

    @Test func corruptedFileIsInvalid() {
        let verdict = UserDataBackupService.check(data: Data("pas du json".utf8), currentUsername: "Alice", isAuthenticated: true)
        guard case .invalidFile = verdict else { Issue.record("fichier illisible accepté"); return }
    }

    @Test func filenameIsStableAndPortable() {
        let name = UserDataBackupService.filename(username: "Alice")
        #expect(name.hasPrefix("spinlog-backup-Alice-"))
        #expect(name.hasSuffix(".json"))
        #expect(!name.contains(" "))
    }
}
