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
    @State private var authManager = DiscogsAuthManager.shared

    @State private var tagStore = TagStore.shared
    @State private var themeManager = ThemeManager.shared
    @State private var appearancePreferences = AppearancePreferencesStore.shared

    @State private var showingPaywall = false
    @State private var showingFeaturesSheet = false
    @State private var toastMessage: String? = nil

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
            DeveloperPremiumSection(
                showingPaywall: $showingPaywall,
                showingFeaturesSheet: $showingFeaturesSheet,
                showToast: showToast
            )

            // MARK: - 2. Simulation Réseau & Mode Hors Ligne
            DeveloperNetworkSection()

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
            DeveloperSyncQueueSection(showToast: showToast)

            // MARK: - 4bis. Synchronisation iCloud (CloudSyncEngine)
            DeveloperCloudSyncSection(showToast: showToast)

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
        .messageAlert(message: $toastMessage)
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

    private func runNetPurchasePriceBackfill(username: String, credentials: DiscogsCredentials) async {
        switch await NetPurchasePriceBackfill.run(username: username, credentials: credentials) {
        case .purchaseFieldNotConfigured:
            showToast("Configure d'abord le champ « Prix d'achat » dans Réglages > Suivi de plus-value.")
        case .fieldsUnavailable:
            showToast("Impossible de récupérer les champs personnalisés Discogs.")
        case .discountFieldMissing:
            showToast("Champ « Réduc » introuvable sur Discogs. Crée-le d'abord depuis discogs.com.")
        case .netFieldMissing:
            showToast("Champ « Prix d'achat net » introuvable sur Discogs. Crée-le d'abord depuis discogs.com.")
        case .finished(let updated, let failures):
            let failureSuffix = failures > 0 ? " (\(failures) échec\(failures > 1 ? "s" : ""))" : ""
            showToast("Prix d'achat net recalculé pour \(updated) exemplaire\(updated > 1 ? "s" : "")\(failureSuffix).")
        }
    }

    private func showToast(_ msg: String) {
        toastMessage = msg
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
        DeveloperBackup.confirmationMessage(for: backup)
    }

    private func prepareExport() {
        guard let username = authManager.username, authManager.isAuthenticated else {
            showToast("Tu dois être connecté à ton compte Discogs pour générer une sauvegarde de tes données.")
            return
        }
        exportDocument = SpinlogBackupDocument(
            backup: DeveloperBackup.make(username: username, tagStore: tagStore, appearance: appearancePreferences, themeManager: themeManager)
        )
        exportFilename = DeveloperBackup.filename(username: username)
        showingFileExporter = true
    }

    private func handleImport(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            showToast("Impossible d'accéder au fichier sélectionné.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            showToast("Le fichier sélectionné n'est pas une sauvegarde \(AppInfo.name) valide ou est endommagé.")
            return
        }
        switch DeveloperBackup.check(data: data, currentUsername: authManager.username, isAuthenticated: authManager.isAuthenticated) {
        case .accepted(let backup):
            pendingBackupToRestore = backup
            showingRestoreConfirmation = true
        case .notSignedIn:
            showToast("Connecte-toi à ton compte Discogs avant de restaurer une sauvegarde.")
        case .wrongAccount(let backupUser, let currentUser):
            showToast("Ce fichier de sauvegarde appartient au compte « \(backupUser) », alors que tu es connecté avec le compte « \(currentUser) ».\n\nLa restauration a été refusée pour éviter toute incohérence.")
        case .invalidFile:
            showToast("Le fichier sélectionné n'est pas une sauvegarde \(AppInfo.name) valide ou est endommagé.")
        }
    }

    private func applyBackup(_ backup: SpinlogUserDataBackup) {
        DeveloperBackup.restore(backup, tagStore: tagStore, appearance: appearancePreferences, themeManager: themeManager, isPremium: premiumStore.isPremium)
        showToast(DeveloperBackup.successMessage(for: backup))
        pendingBackupToRestore = nil
    }

}

#endif
