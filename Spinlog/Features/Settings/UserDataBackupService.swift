import Foundation

/// Sauvegarde et restauration JSON des données locales, section cachée de « Export » (voir
/// `UserDataBackupSection`). Règles pures ou presque, hors de l'interface : fichier refusé s'il
/// appartient à un autre compte, messages de confirmation. Textes volontairement non traduits,
/// comme les diagnostics : outil réservé aux tests.
enum UserDataBackupService {
    /// Verdict de la vérification d'un fichier de sauvegarde avant restauration.
    enum ImportCheck {
        case accepted(SpinlogUserDataBackup)
        case notSignedIn
        case wrongAccount(backupUser: String, currentUser: String)
        case invalidFile
    }

    static func make(
        username: String,
        tagStore: TagStore,
        appearance: AppearancePreferencesStore,
        themeManager: ThemeManager
    ) -> SpinlogUserDataBackup {
        let lastFolderId = CollectionPreferencesStore.lastConsultedFolderId(for: username) ?? DiscogsConstants.allFolderId
        let lastFolderName = CollectionPreferencesStore.lastConsultedFolderName(for: username)
        let sortOption = (CollectionPreferencesStore.sortOption(for: username) ?? .artist).rawValue
        let filterTags = CollectionPreferencesStore.filterTags(for: username)
        let filterFormat = CollectionPreferencesStore.filterFormat(for: username) ?? ""
        let cachedFolders = LocalDataStore.shared.getFolders(username: username)
        let masterYears = LocalDataStore.shared.getAllMasterYears()
        let sessions = ListeningLogStore.shared.sessions

        return SpinlogUserDataBackup(
            version: SpinlogUserDataBackup.currentVersion,
            exportDate: Date(),
            discogsUsername: username,
            tagsByInstance: tagStore.tagsByInstance,
            tagsByRelease: [:],
            standaloneTags: Array(tagStore.standaloneTags),
            appTheme: appearance.appearance.rawValue,
            appColorTheme: themeManager.currentTheme.rawValue,
            masterYears: masterYears.isEmpty ? nil : masterYears,
            listeningSessions: sessions.isEmpty ? nil : sessions,
            lastConsultedFolderId: lastFolderId,
            lastConsultedFolderName: lastFolderName,
            collectionSortOption: sortOption,
            collectionFilterTags: filterTags,
            collectionFilterFormat: filterFormat,
            collectionFolders: cachedFolders.isEmpty ? nil : cachedFolders,
            customArtistSortOverrides: ShelfPreferencesStore.shared.customArtistSortOverrides.isEmpty
                ? nil : ShelfPreferencesStore.shared.customArtistSortOverrides
        )
    }

    static func filename(username: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        return "spinlog-backup-\(username)-\(dateFormatter.string(from: Date())).json"
    }

    /// Décode le fichier et refuse une sauvegarde d'un autre compte, pour éviter toute incohérence.
    static func check(data: Data, currentUsername: String?, isAuthenticated: Bool) -> ImportCheck {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(SpinlogUserDataBackup.self, from: data) else {
            return .invalidFile
        }
        guard let currentUsername, isAuthenticated else { return .notSignedIn }

        let backupUser = backup.discogsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUser = currentUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard backupUser.caseInsensitiveCompare(currentUser) == .orderedSame else {
            return .wrongAccount(backupUser: backupUser, currentUser: currentUser)
        }
        return .accepted(backup)
    }

    static func confirmationMessage(for backup: SpinlogUserDataBackup) -> String {
        let dateFormatted = backup.exportDate.formatted(date: .abbreviated, time: .shortened)
        let tagsSuffix = backup.totalTagsCount > 1 ? "s" : ""
        let albumsSuffix = backup.totalReleasesTaggedCount > 1 ? "s" : ""
        return "Sauvegarde du \(dateFormatted) pour le compte Discogs « \(backup.discogsUsername) ».\n\nElle contient \(backup.totalTagsCount) tag\(tagsSuffix) et \(backup.totalReleasesTaggedCount) album\(albumsSuffix) étiqueté\(albumsSuffix).\n\nVos tags actuels seront remplacés par ceux du fichier."
    }

    static func successMessage(for backup: SpinlogUserDataBackup) -> String {
        "Tes données ont été restaurées avec succès (\(backup.totalTagsCount) tag\(backup.totalTagsCount > 1 ? "s" : "") et \(backup.totalReleasesTaggedCount) album\(backup.totalReleasesTaggedCount > 1 ? "s" : "") étiqueté\(backup.totalReleasesTaggedCount > 1 ? "s" : ""))."
    }

    static func restore(
        _ backup: SpinlogUserDataBackup,
        tagStore: TagStore,
        appearance: AppearancePreferencesStore,
        themeManager: ThemeManager,
        isPremium: Bool
    ) {
        tagStore.restoreData(
            tagsByInstance: backup.tagsByInstance,
            tagsByRelease: backup.tagsByRelease,
            standaloneTags: Set(backup.standaloneTags)
        )
        if let theme = backup.appTheme, let appTheme = AppTheme(rawValue: theme) {
            appearance.appearance = appTheme
        }
        if let colorTheme = backup.appColorTheme, let theme = AppColorTheme(rawValue: colorTheme) {
            themeManager.selectTheme(theme, isPremium: isPremium)
        }
        if let folderId = backup.lastConsultedFolderId {
            CollectionPreferencesStore.setLastConsultedFolderId(folderId, for: backup.discogsUsername)
        }
        if let folderName = backup.lastConsultedFolderName {
            CollectionPreferencesStore.setLastConsultedFolderName(folderName, for: backup.discogsUsername)
        }
        if let sortRaw = backup.collectionSortOption, let sort = CollectionSortOption(rawValue: sortRaw) {
            CollectionPreferencesStore.setSortOption(sort, for: backup.discogsUsername)
        }
        if !backup.collectionFilterTags.isEmpty {
            CollectionPreferencesStore.setFilterTags(backup.collectionFilterTags, for: backup.discogsUsername)
        }
        if let format = backup.collectionFilterFormat {
            CollectionPreferencesStore.setFilterFormat(format, for: backup.discogsUsername)
        }
        if let folders = backup.collectionFolders, !folders.isEmpty {
            LocalDataStore.shared.saveFolders(folders, username: backup.discogsUsername)
        }
        if let masterYears = backup.masterYears, !masterYears.isEmpty {
            LocalDataStore.shared.saveMasterYears(masterYears)
        }
        if let sessions = backup.listeningSessions, !sessions.isEmpty {
            ListeningLogStore.shared.restoreSessions(sessions)
        }
        if let overrides = backup.customArtistSortOverrides, !overrides.isEmpty {
            ShelfPreferencesStore.shared.applyRemoteCustomArtistSortOverrides(overrides)
        }
        NotificationCenter.default.post(name: .collectionPreferencesChanged, object: nil)
    }
}
