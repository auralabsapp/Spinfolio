import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

// Exclu des builds Release/App Store : ce type n'existe même pas en dehors du Debug, pour
// qu'aucun futur point d'entrée ne puisse le rendre accessible par erreur en production.
#if DEBUG

/// Écran d'options et d'outils développeur pour tester les fonctionnalités de Spinlog :
/// simulation du compte premium, simulation du mode hors ligne (sans couper le Wi-Fi),
/// déclenchement de la règle des 6h Discogs, et inspection des files de synchronisation.
struct DeveloperOptionsView: View {
    @State private var premiumStore = PremiumStore.shared
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var offlineManager = OfflineDownloadManager.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var syncQueue = OfflineSyncQueue.shared

    @State private var tagStore = TagStore.shared
    @State private var cloudSyncEngine = CloudSyncEngine.shared
    @State private var themeManager = ThemeManager.shared
    @State private var appearancePreferences = AppearancePreferencesStore.shared

    @State private var showingPaywall = false
    @State private var showingFeaturesSheet = false
    @State private var toastMessage: String? = nil
    @State private var showingToast = false

    // Sauvegarde & Restauration JSON
    @State private var showingFileExporter = false
    @State private var showingFileImporter = false
    @State private var exportDocument: SpinlogBackupDocument?
    @State private var exportFilename: String = ""
    @State private var pendingBackupToRestore: SpinlogUserDataBackup?
    @State private var showingRestoreConfirmation = false

    // Alimentation ponctuelle du champ personnalisé "Prix d'achat net"
    @State private var isBackfillingNetPrice = false

    var body: some View {
        List {
            // MARK: - 1. Statut Premium & Achat
            Section {
                Toggle(isOn: $premiumStore.developerOverride) {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Compte Premium")
                                .font(.body.weight(.medium))
                            Text(premiumStore.isPremium ? "Toutes les fonctions débloquées" : "Compte gratuit bridé")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .tint(Color.spinlogPink)

                Button {
                    showingPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color(red: 0.95, green: 0.68, blue: 0.18))
                        Text("Afficher l'écran Paywall")
                            .foregroundStyle(.primary)
                    }
                }

                Button {
                    showingFeaturesSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "list.star")
                            .foregroundStyle(.blue)
                        Text("Afficher la fiche des fonctionnalités")
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "cart.fill")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("StoreKit 2")
                            .font(.body.weight(.medium))
                        Text(subscriptionManager.products.isEmpty ? "Aucun produit chargé" : "\(subscriptionManager.products.count) forfaits chargés (\(subscriptionManager.yearlyPriceString), \(subscriptionManager.monthlyPriceString))")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                        // Diagnostic temporaire : permet de voir directement sur l'appareil si
                        // `introductoryOffer` remonte bien depuis StoreKit (config locale ou réelle).
                        Text("Essai annuel : \(subscriptionManager.freeTrialText(for: .yearly) ?? "aucun (introductoryOffer = nil)")")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                        if let errorMessage = subscriptionManager.errorMessage {
                            Text("Erreur StoreKit : \(errorMessage)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    Button("Sync") {
                        Task {
                            await subscriptionManager.loadProducts()
                            await subscriptionManager.updateCustomerProductStatus()
                            toastMessage = "StoreKit 2 synchronisé"
                            showingToast = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !subscriptionManager.purchasedProductIDs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Abonnement actif StoreKit")
                                .font(.body.weight(.medium))
                            Text(subscriptionManager.purchasedProductIDs.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Text("Simulation Premium")
            } footer: {
                Text("Permet de basculer instantanément entre l'expérience gratuite et premium pour tester les bridages et paywalls.")
            }

            // MARK: - 2. Simulation Réseau & Mode Hors Ligne
            Section {
                Toggle(isOn: $networkMonitor.simulatedOffline) {
                    HStack(spacing: 12) {
                        Image(systemName: networkMonitor.simulatedOffline ? "wifi.slash" : "wifi")
                            .foregroundStyle(networkMonitor.simulatedOffline ? .orange : .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simuler mode hors ligne")
                                .font(.body.weight(.medium))
                            Text(networkMonitor.simulatedOffline ? "Réseau désactivé artificiellement" : "Connectivité réelle")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .tint(.orange)

                HStack {
                    Text("État réseau réel")
                    Spacer()
                    Text(networkMonitor.isConnected ? "En ligne" : "Hors ligne")
                        .foregroundStyle(networkMonitor.isConnected ? .green : .red)
                        .font(.footnote.weight(.medium))
                }
            } header: {
                Text("Simulation Réseau")
            } footer: {
                Text("Active ce toggle pour tester le mode hors ligne sans avoir besoin d'activer le mode Avion de ton iPhone.")
            }

            // MARK: - 3. Règle des 6 heures Discogs (Cache Stale)
            Section {
                Button {
                    simulateStaleCache()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simuler expiration du cache (> 6h)")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Recule l'horodatage de 7 heures pour afficher le bandeau hors ligne")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }

                Button {
                    resetFreshCache()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Réinitialiser cache frais (< 6h)")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Met l'horodatage du cache à maintenant")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
            } header: {
                Text("Règle des 6h Discogs")
            } footer: {
                Text("Permet de tester l'apparition du bandeau d'instantané hors ligne conforme aux CGU Discogs.")
            }

            // MARK: - 4. File d'attente Hors Ligne (OfflineSyncQueue)
            Section {
                HStack {
                    Text("Actions en attente")
                    Spacer()
                    Text("\(syncQueue.pendingActions.count)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(syncQueue.pendingActions.isEmpty ? Color.appSecondaryText : .orange)
                }

                if !syncQueue.pendingActions.isEmpty {
                    Button {
                        Task { await syncQueue.processQueue() }
                        showToast("Traitement de la file d'attente lancé")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Forcer le traitement de la file")
                        }
                    }

                    Button(role: .destructive) {
                        syncQueue.clearQueue()
                        showToast("File d'attente vidée")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                            Text("Vider la file d'attente")
                        }
                    }
                }
            } header: {
                Text("File d'attente locale (Sync Queue)")
            }

            // MARK: - 4bis. Synchronisation iCloud (CloudSyncEngine)
            Section {
                HStack {
                    Text("Compte actif")
                    Spacer()
                    Text(cloudSyncEngine.activeUsername ?? "—")
                        .foregroundStyle(Color.appSecondaryText)
                }

                Button {
                    cloudSyncEngine.resetInitialSyncForActiveAccount()
                    showToast("Poussée initiale relancée pour ce compte sur cet appareil.")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Forcer une nouvelle poussée initiale")
                                .font(.body.weight(.medium))
                                .foregroundStyle(cloudSyncEngine.activeUsername == nil ? .secondary : .primary)
                            Text("Récupère et repousse tags, sessions, préférences et historique de valeur")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .disabled(cloudSyncEngine.activeUsername == nil)
            } header: {
                Text("Synchronisation iCloud")
            } footer: {
                Text("Oublie que la synchro initiale a déjà eu lieu sur cet appareil pour ce compte, et la redéclenche immédiatement (récupération puis poussée). Utile pour retester la réconciliation entre deux appareils, ou repousser des données pré-existantes après l'ajout d'un nouveau genre synchronisé.")
            }

            // MARK: - 5. Caches & Widgets
            Section {
                Button {
                    KingfisherConfig.clearDiskCache()
                    showToast("Cache des images vidé")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(.purple)
                        Text("Vider le cache d'images")
                            .foregroundStyle(.primary)
                    }
                }

                Button {
                    WidgetCenter.shared.reloadAllTimelines()
                    showToast("Widgets rechargés")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.3.group")
                            .foregroundStyle(.indigo)
                        Text("Recharger les widgets")
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("Stockage & Widgets")
            }

            // MARK: - 6. Sauvegarde & Restauration JSON
            Section {
                Button {
                    prepareExport()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exporter une sauvegarde JSON")
                                .font(.body.weight(.medium))
                                .foregroundStyle(authManager.isAuthenticated ? .primary : .secondary)
                            Text(exportSubtitle)
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.appTertiaryText)
                    }
                }
                .disabled(!authManager.isAuthenticated)

                Button {
                    showingFileImporter = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restaurer une sauvegarde JSON")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Restaure tags, réglages et métadonnées locales")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.appTertiaryText)
                    }
                }
            } header: {
                Text("Sauvegarde interne (JSON)")
            } footer: {
                Text("Outil de développement pour exporter et importer l'intégralité des métadonnées locales : tags, sessions d'écoute, préférences et correspondance des années.")
            }

            // MARK: - 7. Champs personnalisés (backfill ponctuel)
            Section {
                Button {
                    fillNetPurchasePriceField()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "eurosign.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alimentation prix d'achat net")
                                .font(.body.weight(.medium))
                                .foregroundStyle(authManager.isAuthenticated ? .primary : .secondary)
                            Text("Prix d'achat net = Prix d'achat − Réduction, sur toute la collection")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        if isBackfillingNetPrice {
                            ProgressView()
                        }
                    }
                }
                .disabled(isBackfillingNetPrice || !authManager.isAuthenticated)
            } header: {
                Text("Champs personnalisés")
            } footer: {
                Text("Recalcule et pousse sur Discogs le champ « Prix d'achat net » pour chaque exemplaire possédant au moins un prix d'achat ou une réduction renseigné(e) — une valeur manquante compte pour 0. Nécessite que les champs « Prix d'achat » (choisi dans Réglages), « Réduction » et « Prix d'achat net » existent déjà sur discogs.com.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .listRowSeparatorTint(Color.appSeparator)
        .navigationTitle("Options développeur")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingPaywall) {
            SpinlogPaywallView()
        }
        .sheet(isPresented: $showingFeaturesSheet) {
            PremiumFeaturesSheet()
        }
        .alert(toastMessage ?? "", isPresented: $showingToast) {
            Button("OK", role: .cancel) {}
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success(let url):
                showToast("Fichier de sauvegarde exporté avec succès :\n\(url.lastPathComponent)")
            case .failure(let error):
                showToast("Échec de l'export : \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                handleImport(url: url)
            case .failure(let error):
                showToast("Échec de l'ouverture : \(error.localizedDescription)")
            }
        }
        .confirmationDialog(
            "Restaurer la sauvegarde ?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remplacer les données locales", role: .destructive) {
                if let backup = pendingBackupToRestore {
                    applyBackup(backup)
                }
            }
            Button("Annuler", role: .cancel) {
                pendingBackupToRestore = nil
            }
        } message: {
            if let backup = pendingBackupToRestore {
                Text(restoreConfirmationMessage(for: backup))
            } else {
                Text("Tes données locales seront remplacées.")
            }
        }
    }

    private func simulateStaleCache() {
        guard let username = authManager.username else {
            showToast("Connecte-toi d'abord à un compte Discogs")
            return
        }
        LocalDataStore.shared.simulateStaleCache(username: username)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showToast("Cache daté à -7 heures. Va sur Collection ou Wantlist en mode hors ligne pour voir le bandeau.")
    }

    private func resetFreshCache() {
        guard let username = authManager.username else {
            showToast("Connecte-toi d'abord à un compte Discogs")
            return
        }
        LocalDataStore.shared.resetCacheFreshness(username: username)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Horodatage réinitialisé à l'instant présent.")
    }

    private func fillNetPurchasePriceField() {
        guard let username = authManager.username, let credentials = authManager.credentials else {
            showToast("Connecte-toi d'abord à un compte Discogs")
            return
        }
        isBackfillingNetPrice = true
        Task {
            await runNetPurchasePriceBackfill(username: username, credentials: credentials)
            isBackfillingNetPrice = false
        }
    }

    /// Recalcule "Prix d'achat net" (Prix d'achat − Réduction, chaque champ manquant valant 0)
    /// pour tout exemplaire de la collection possédant au moins l'un des deux champs renseigné,
    /// et pousse le résultat sur Discogs. Les champs sont retrouvés par nom (insensible à la
    /// casse/aux accents) plutôt que par un réglage dédié : ce sont deux champs que l'utilisateur
    /// vient de créer sur discogs.com pour cet outil ponctuel.
    private func runNetPurchasePriceBackfill(username: String, credentials: DiscogsCredentials) async {
        guard let purchaseFieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username) else {
            showToast("Configure d'abord le champ « Prix d'achat » dans Réglages > Suivi de plus-value.")
            return
        }
        guard let fieldsResponse = try? await DiscogsAPIClient.shared.collectionFields(username: username, credentials: credentials) else {
            showToast("Impossible de récupérer les champs personnalisés Discogs.")
            return
        }
        guard let discountField = matchCollectionField(named: "réduc", in: fieldsResponse.fields) else {
            showToast("Champ « Réduc » introuvable sur Discogs. Crée-le d'abord depuis discogs.com.")
            return
        }
        guard let netField = matchCollectionField(named: "prix d'achat net", in: fieldsResponse.fields) else {
            showToast("Champ « Prix d'achat net » introuvable sur Discogs. Crée-le d'abord depuis discogs.com.")
            return
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

        let failureSuffix = failureCount > 0 ? " (\(failureCount) échec\(failureCount > 1 ? "s" : ""))" : ""
        showToast("Prix d'achat net recalculé pour \(updatedCount) exemplaire\(updatedCount > 1 ? "s" : "")\(failureSuffix).")
    }

    private func matchCollectionField(named target: String, in fields: [CollectionField]) -> CollectionField? {
        let normalizedTarget = normalizedFieldName(target)
        return fields.first { normalizedFieldName($0.name) == normalizedTarget }
    }

    /// Ne garde que lettres/chiffres (repliés sans accent/casse) : insensible aux apostrophes
    /// (droite ' vs typographique ’) et aux espacements, qui font sinon échouer une comparaison
    /// stricte alors que le champ existe bel et bien sur Discogs.
    private func normalizedFieldName(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init)
            .reduce(into: "") { $0.append($1) }
    }

    private func showToast(_ msg: String) {
        toastMessage = msg
        showingToast = true
    }

    private var exportSubtitle: String {
        if authManager.isAuthenticated {
            if let user = authManager.username {
                return "Exporte tes tags pour le compte \(user)"
            } else {
                return "Exporte tes tags associés à ton compte"
            }
        } else {
            return "Connexion à Discogs requise"
        }
    }

    private func restoreConfirmationMessage(for backup: SpinlogUserDataBackup) -> String {
        let dateFormatted = backup.exportDate.formatted(date: .abbreviated, time: .shortened)
        let tagsSuffix = backup.totalTagsCount > 1 ? "s" : ""
        let albumsSuffix = backup.totalReleasesTaggedCount > 1 ? "s" : ""
        return "Sauvegarde du \(dateFormatted) pour le compte Discogs « \(backup.discogsUsername) ».\n\nElle contient \(backup.totalTagsCount) tag\(tagsSuffix) et \(backup.totalReleasesTaggedCount) album\(albumsSuffix) étiqueté\(albumsSuffix).\n\nVos tags actuels seront remplacés par ceux du fichier."
    }

    private func prepareExport() {
        guard let username = authManager.username, authManager.isAuthenticated else {
            showToast("Tu dois être connecté à ton compte Discogs pour générer une sauvegarde de tes données.")
            return
        }

        let lastFolderId = CollectionPreferencesStore.lastConsultedFolderId(for: username) ?? DiscogsConstants.allFolderId
        let lastFolderName = CollectionPreferencesStore.lastConsultedFolderName(for: username)
        let sortOption = (CollectionPreferencesStore.sortOption(for: username) ?? .artist).rawValue
        let filterTags = CollectionPreferencesStore.filterTags(for: username)
        let filterFormat = CollectionPreferencesStore.filterFormat(for: username) ?? ""
        let cachedFolders = LocalDataStore.shared.getFolders(username: username)
        let masterYears = LocalDataStore.shared.getAllMasterYears()
        let sessions = ListeningLogStore.shared.sessions

        let backup = SpinlogUserDataBackup(
            version: SpinlogUserDataBackup.currentVersion,
            exportDate: Date(),
            discogsUsername: username,
            tagsByInstance: tagStore.tagsByInstance,
            tagsByRelease: [:],
            standaloneTags: Array(tagStore.standaloneTags),
            appTheme: appearancePreferences.appearance.rawValue,
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

        exportDocument = SpinlogBackupDocument(backup: backup)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        exportFilename = "spinlog-backup-\(username)-\(dateFormatter.string(from: Date())).json"
        showingFileExporter = true
    }

    private func handleImport(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            showToast("Impossible d'accéder au fichier sélectionné.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(SpinlogUserDataBackup.self, from: data)

            guard let currentUsername = authManager.username, authManager.isAuthenticated else {
                showToast("Connecte-toi à ton compte Discogs avant de restaurer une sauvegarde.")
                return
            }

            let backupUser = backup.discogsUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentUser = currentUsername.trimmingCharacters(in: .whitespacesAndNewlines)

            if backupUser.caseInsensitiveCompare(currentUser) != .orderedSame {
                showToast("Ce fichier de sauvegarde appartient au compte « \(backupUser) », alors que tu es connecté avec le compte « \(currentUser) ».\n\nLa restauration a été refusée pour éviter toute incohérence.")
                return
            }

            pendingBackupToRestore = backup
            showingRestoreConfirmation = true

        } catch {
            showToast("Le fichier sélectionné n'est pas une sauvegarde \(AppInfo.name) valide ou est endommagé.")
        }
    }

    private func applyBackup(_ backup: SpinlogUserDataBackup) {
        tagStore.restoreData(
            tagsByInstance: backup.tagsByInstance,
            tagsByRelease: backup.tagsByRelease,
            standaloneTags: Set(backup.standaloneTags)
        )
        if let theme = backup.appTheme, let appTheme = AppTheme(rawValue: theme) {
            appearancePreferences.appearance = appTheme
        }
        if let colorTheme = backup.appColorTheme, let theme = AppColorTheme(rawValue: colorTheme) {
            themeManager.selectTheme(theme, isPremium: premiumStore.isPremium)
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
        showToast("Tes données ont été restaurées avec succès (\(backup.totalTagsCount) tag\(backup.totalTagsCount > 1 ? "s" : "") et \(backup.totalReleasesTaggedCount) album\(backup.totalReleasesTaggedCount > 1 ? "s" : "") étiqueté\(backup.totalReleasesTaggedCount > 1 ? "s" : "")).")
        pendingBackupToRestore = nil
    }

}

#endif
