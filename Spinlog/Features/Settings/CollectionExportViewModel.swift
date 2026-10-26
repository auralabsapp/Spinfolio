import Foundation

/// Orchestre les exports CSV/PDF de la collection (`SettingsView`) : récupération des
/// dossiers/champs/exemplaires auprès de Discogs (avec repli sur le cache local hors ligne),
/// génération du fichier, puis présentation de la feuille de partage. Extrait de `SettingsView`,
/// qui appelait `DiscogsAPIClient` directement — ces appels réseau n'ont rien à faire dans une
/// `View`, qui ne devrait piloter que l'affichage (progression, alertes).
@Observable
@MainActor
final class CollectionExportViewModel {
    private(set) var isExportingCSV = false
    private(set) var isExportingPDF = false
    private(set) var alertTitle = ""
    /// Message de l'alerte affichée ; `nil` quand elle est fermée (`messageAlert`).
    var alertMessage: String?

    private let authManager = DiscogsAuthManager.shared
    private let tagStore = TagStore.shared
    private let localStore = LocalDataStore.shared
    private let networkMonitor = NetworkMonitor.shared

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
    }

    /// Dossiers et exemplaires de la collection entière (dossier "Tous"), rafraîchis depuis
    /// Discogs quand la connexion le permet, avec repli sur le cache SwiftData sinon — commun
    /// aux deux exports.
    private func fetchFoldersAndItems(username: String) async -> (folders: [CollectionFolder], items: [CollectionItem]) {
        var folders = localStore.getFolders(username: username)
        var items: [CollectionItem] = []

        if networkMonitor.isConnected, let credentials = authManager.credentials {
            if let foldersResp = try? await DiscogsAPIClient.shared.collectionFolders(username: username, credentials: credentials) {
                folders = foldersResp.folders
                localStore.saveFolders(folders, username: username)
            }
            // Cache de moins de 6 h, ou relecture complète déjà en cours (synchro de fond, mode hors
            // ligne, widget) : le cache suffit, sans relire une seconde fois toute la collection.
            let allFolder = DiscogsConstants.allFolderId
            if !localStore.isCollectionStale(username: username, folderId: allFolder)
                || !localStore.beginFullCollectionSync(username: username, folderId: allFolder) {
                items = await localStore.getAllCollectionItems(username: username)
            } else {
                defer { localStore.endFullCollectionSync(username: username, folderId: allFolder) }
                do {
                    items = try await DiscogsAPIClient.shared.fetchAllCollectionItems(
                        username: username,
                        folderId: allFolder,
                        credentials: credentials
                    )
                    await localStore.syncCollectionFolder(username: username, folderId: allFolder, fullItems: items)
                } catch {
                    items = await localStore.getAllCollectionItems(username: username)
                }
            }
        } else {
            items = await localStore.getAllCollectionItems(username: username)
        }

        // Filtrage de sécurité contre les entrées fantômes.
        items = items.filter { $0.instanceId > 0 && $0.instanceId != $0.releaseId }
        return (folders, items)
    }

    private func exportFilename(prefix: String, username: String, extension fileExtension: String) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "\(prefix)-\(username)-\(dateFormatter.string(from: Date())).\(fileExtension)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    func exportCSV() async {
        guard let username = authManager.username, authManager.isAuthenticated else {
            presentAlert(
                title: String(localized: "Connexion requise"),
                message: String(localized: "Tu dois être connecté à ton compte Discogs pour exporter ta collection.")
            )
            return
        }

        isExportingCSV = true
        defer { isExportingCSV = false }

        var fields: [CollectionField] = []
        if networkMonitor.isConnected, let credentials = authManager.credentials {
            fields = await CollectionFieldsService.fields(username: username, credentials: credentials)
        }
        let (folders, items) = await fetchFoldersAndItems(username: username)

        guard !items.isEmpty else {
            presentAlert(
                title: String(localized: "Collection vide"),
                message: String(localized: "Aucun album n'a été trouvé dans ta collection pour l'export.")
            )
            return
        }

        let csvText = CollectionCSVExporter.generateCSV(items: items, folders: folders, fields: fields, tagStore: tagStore)
        let tempURL = exportFilename(prefix: "spinlog-collection", username: username, extension: "csv")

        do {
            try csvText.write(to: tempURL, atomically: true, encoding: .utf8)
            ShareSheetPresenter.present(url: tempURL)
        } catch {
            presentAlert(
                title: String(localized: "Erreur de fichier"),
                message: String(localized: "Impossible de générer le fichier CSV : \(error.localizedDescription)")
            )
        }
    }

    func exportPDF() async {
        guard let username = authManager.username, authManager.isAuthenticated else {
            presentAlert(
                title: String(localized: "Connexion requise"),
                message: String(localized: "Tu dois être connecté à ton compte Discogs pour exporter ta collection.")
            )
            return
        }

        isExportingPDF = true
        defer { isExportingPDF = false }

        var marketValue: CollectionValueResponse?
        if networkMonitor.isConnected, let credentials = authManager.credentials {
            marketValue = try? await DiscogsAPIClient.shared.collectionValue(username: username, credentials: credentials)
        }
        let (folders, items) = await fetchFoldersAndItems(username: username)

        guard !items.isEmpty else {
            presentAlert(
                title: String(localized: "Collection vide"),
                message: String(localized: "Aucun album n'a été trouvé dans ta collection pour l'export.")
            )
            return
        }

        let purchasePriceFieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username)
        let mediaConditionFieldId = CollectionPreferencesStore.mediaConditionFieldId(for: username)
        let currency = CollectionPreferencesStore.defaultCurrency(for: username)

        var totalInvested: Double?
        if let purchasePriceFieldId {
            var total = 0.0
            for item in items {
                let raw = item.value(forFieldId: purchasePriceFieldId).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty, let parsed = PurchasePriceParser.parse(raw, defaultCurrency: currency) else { continue }
                total += await CurrencyConversionService.shared.convert(parsed.amount, from: parsed.currency, to: currency)
            }
            totalInvested = total
        }

        let coverImages = await CollectionPDFExporter.fetchCoverImages(for: items)
        let pdfData = CollectionPDFExporter.generatePDF(
            username: username,
            items: items,
            folders: folders,
            purchasePriceFieldId: purchasePriceFieldId,
            mediaConditionFieldId: mediaConditionFieldId,
            defaultCurrency: currency,
            totalInvested: totalInvested,
            marketValue: marketValue,
            coverImages: coverImages
        )

        let tempURL = exportFilename(prefix: "spinlog-declaration", username: username, extension: "pdf")
        do {
            try pdfData.write(to: tempURL, options: .atomic)
            ShareSheetPresenter.present(url: tempURL)
        } catch {
            presentAlert(
                title: String(localized: "Erreur de fichier"),
                message: String(localized: "Impossible de générer le document PDF : \(error.localizedDescription)")
            )
        }
    }
}
