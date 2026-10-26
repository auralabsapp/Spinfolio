import SwiftUI

// Exclu des builds Release/App Store, comme `DeveloperOptionsView` dont il porte la logique.
#if DEBUG

/// Alimentation ponctuelle du champ personnalisé « Prix d'achat net » (outil développeur).
enum NetPurchasePriceBackfill {
    enum Outcome {
        case purchaseFieldNotConfigured
        case fieldsUnavailable
        case discountFieldMissing
        case netFieldMissing
        case finished(updated: Int, failures: Int)
    }

    /// Recalcule "Prix d'achat net" (Prix d'achat − Réduction, chaque champ manquant valant 0)
    /// pour tout exemplaire de la collection possédant au moins l'un des deux champs renseigné,
    /// et pousse le résultat sur Discogs. Les champs sont retrouvés par nom (insensible à la
    /// casse/aux accents) plutôt que par un réglage dédié : ce sont deux champs que l'utilisateur
    /// vient de créer sur discogs.com pour cet outil ponctuel.
    static func run(username: String, credentials: DiscogsCredentials) async -> Outcome {
        guard let purchaseFieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username) else {
            return .purchaseFieldNotConfigured
        }
        guard let fieldsResponse = try? await DiscogsAPIClient.shared.collectionFields(username: username, credentials: credentials) else {
            return .fieldsUnavailable
        }
        guard let discountField = matchCollectionField(named: "réduc", in: fieldsResponse.fields) else {
            return .discountFieldMissing
        }
        guard let netField = matchCollectionField(named: "prix d'achat net", in: fieldsResponse.fields) else {
            return .netFieldMissing
        }

        let items = await LocalDataStore.shared.getAllCollectionItems(username: username)
        let defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)

        var updatedCount = 0
        var failureCount = 0

        for item in items {
            let purchaseRaw = item.value(forFieldId: purchaseFieldId)
            let discountRaw = item.value(forFieldId: discountField.id)
            guard !purchaseRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !discountRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let purchase = PurchasePriceParser.parse(purchaseRaw, defaultCurrency: defaultCurrency)
            let discount = PurchasePriceParser.parse(discountRaw, defaultCurrency: defaultCurrency)
            let net = (purchase?.amount ?? 0) - (discount?.amount ?? 0)
            let currency = purchase?.currency ?? discount?.currency ?? defaultCurrency
            let canonical = PurchasePriceParser.canonicalString(amount: net, currency: currency)

            do {
                try await DiscogsAPIClient.shared.updateCollectionField(
                    username: username,
                    folderId: item.folderId,
                    releaseId: item.releaseId,
                    instanceId: item.instanceId,
                    fieldId: netField.id,
                    value: canonical,
                    credentials: credentials
                )
                var updatedItem = item
                if let noteIndex = updatedItem.notes.firstIndex(where: { $0.fieldId == netField.id }) {
                    updatedItem.notes[noteIndex] = CollectionFieldValue(fieldId: netField.id, value: canonical)
                } else {
                    updatedItem.notes.append(CollectionFieldValue(fieldId: netField.id, value: canonical))
                }
                await LocalDataStore.shared.saveCollectionItems([updatedItem], username: username, folderId: item.folderId)
                await LocalDataStore.shared.saveCollectionItems([updatedItem], username: username, folderId: DiscogsConstants.allFolderId)
                updatedCount += 1
            } catch {
                failureCount += 1
            }
        }
        return .finished(updated: updatedCount, failures: failureCount)
    }

    private static func matchCollectionField(named target: String, in fields: [CollectionField]) -> CollectionField? {
        let normalizedTarget = normalizedFieldName(target)
        return fields.first { normalizedFieldName($0.name) == normalizedTarget }
    }

    /// Ne garde que lettres/chiffres (repliés sans accent/casse) : insensible aux apostrophes
    /// (droite ' vs typographique ’) et aux espacements, qui font sinon échouer une comparaison
    /// stricte alors que le champ existe bel et bien sur Discogs.
    private static func normalizedFieldName(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init)
            .reduce(into: "") { $0.append($1) }
    }
}

/// Sauvegarde et restauration JSON des données locales (outil développeur).
enum DeveloperBackup {
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

#endif
