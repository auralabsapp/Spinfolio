import SwiftUI

/// Écran de gestion avancée du Mode Hors Ligne Premium.
/// Permet de télécharger l'intégralité de la collection et des pochettes d'albums,
/// d'observer l'avancement en direct, de gérer l'espace de stockage et de consulter
/// les mentions légales relatives aux CGU de l'API Discogs (règle des 6 heures).
struct OfflineSettingsDetailView: View {
    @State private var authManager = DiscogsAuthManager.shared
    @State private var offlineManager = OfflineDownloadManager.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var imageCacheSize: String = "Calcul..."
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingClearCacheConfirmation = false
    @State private var showingCellularConfirmation = false
    @State private var alertMessage: String? = nil
    // `OfflineDownloadManager.isAutoSyncOverWifiEnabled` est une propriété calculée adossée à
    // UserDefaults (comme `lastSyncDate`), donc non suivie par `@Observable` : miroir local pour
    // piloter le Toggle, réécrit vers le manager via `onChange`.
    @State private var autoSyncOverWifiEnabled = OfflineDownloadManager.shared.isAutoSyncOverWifiEnabled

    var body: some View {
        SettingsSubPage(title: "Mode Hors Ligne") {
            // MARK: - 1. Statut & Carte Récapitulative
            Section {
                statusHeroCard
            }

            // MARK: - 2. Actions de Téléchargement
            Section {
                if offlineManager.state.isDownloading {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text(offlineManager.state.statusMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.primary)
                        }

                        ProgressView(value: offlineManager.progress, total: 1.0)
                            .tint(Color.spinlogPink)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: offlineManager.progress)

                        HStack {
                            Text(offlineManager.progress.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText(value: offlineManager.progress))
                                .animation(reduceMotion ? nil : .counterChange, value: offlineManager.progress)
                            Spacer()
                            Button("Annuler", role: .cancel) {
                                offlineManager.cancelDownload()
                            }
                            .font(.caption.weight(.medium))
                            .tint(.red)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        startSync()
                    } label: {
                        HStack(spacing: 14) {
                            SettingsIcon(systemName: "arrow.triangle.2.circlepath", backgroundColor: Color.spinlogPink)
                            VStack(alignment: .leading, spacing: 2) {
                                (offlineManager.lastSyncDate == nil ? Text("Télécharger toute ma collection") : Text("Synchroniser maintenant"))
                                    .foregroundStyle(.primary)
                                Text("Récupère tous tes albums, tes dossiers, ta wantlist et les pochettes")
                                    .font(.caption)
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                            Spacer()
                        }
                    }
                }
            } header: {
                SectionEyebrow(title: "Synchronisation locale", icon: "arrow.triangle.2.circlepath")
            } footer: {
                Text("Le téléchargement s'exécute par tranches avec une pause entre chaque page afin de respecter le quota de 60 requêtes/minute de Discogs.")
            }

            // MARK: - 2bis. Synchro automatique en Wi-Fi
            Section {
                Toggle(isOn: $autoSyncOverWifiEnabled) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "wifi", backgroundColor: .teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Synchro auto en Wi-Fi")
                            Text("Relance le téléchargement complet dès qu'une connexion Wi-Fi est disponible")
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .tint(Color.spinlogPink)
                .onChange(of: autoSyncOverWifiEnabled) { _, newValue in
                    offlineManager.isAutoSyncOverWifiEnabled = newValue
                    // Le déclencheur normal (`autoSyncIfNeeded`) ne s'exécute qu'au lancement de
                    // l'app ou au retour au premier plan (voir `RootTabView`) : sans ça, activer
                    // le réglage ici ne lancerait rien de visible avant la prochaine ouverture.
                    if newValue, let (username, credentials) = authManager.session {
                        offlineManager.autoSyncIfNeeded(
                            username: username,
                            credentials: credentials,
                            isPremium: premiumStore.isPremium
                        )
                    }
                }
            } footer: {
                Text("Ne se déclenche jamais en 4G/5G ni en partage de connexion, et au maximum une fois toutes les 6 heures.")
            }

            // MARK: - 3. Gestion du Stockage Disque
            Section {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "photo.stack", backgroundColor: .teal)
                    Text("Pochettes en cache")
                    Spacer()
                    Text(imageCacheSize)
                        .foregroundStyle(Color.appSecondaryText)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .counterChange, value: imageCacheSize)
                }

                Button(role: .destructive) {
                    showingClearCacheConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Vider le cache d'images")
                    }
                }
            } header: {
                SectionEyebrow(title: "Espace de stockage", icon: "internaldrive.fill")
            } footer: {
                // Durée lue dans la constante partagée (`KingfisherConfig`) pour ne pas se désynchroniser.
                Text("Les pochettes sont conservées sur le disque \(DiscogsConstants.imageDiskRetentionDays) jours au plus après leur téléchargement, pour un affichage immédiat hors ligne : synchronise régulièrement pour les garder. Vider le cache libère l'espace sans effacer ta liste d'albums.")
            }

            // MARK: - 4. Fonctionnement
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color.appOffline)
                        Text("Actualisation automatique")
                            .font(.subheadline.weight(.semibold))
                    }

                    Text("En déplacement sans réseau, \(AppInfo.name) te permet de consulter ta discothèque et tes pochettes en toute autonomie.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Dès que ton appareil retrouve une connexion Internet, tes albums, tes dossiers et les estimations de prix du marché se synchronisent automatiquement.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                SectionEyebrow(title: "À savoir", icon: "info.circle.fill")
            }
        }
        // Le bloc de progression remplace le bouton de synchro en fondu plutôt que d'un coup.
        .animation(reduceMotion ? nil : .settingsContentChange, value: offlineManager.state.isDownloading)
        .onChange(of: isSyncCompleted) { _, completed in
            if completed { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        .task {
            await refreshCacheSize()
        }
        .confirmationDialog(
            "Vider le cache d'images ?",
            isPresented: $showingClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Vider le cache", role: .destructive) {
                KingfisherConfig.clearDiskCache()
                Task {
                    await refreshCacheSize()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les pochettes d'albums seront re-téléchargées la prochaine fois que tu les consulteras avec une connexion Internet.")
        }
        .confirmationDialog(
            "Télécharger en 4G/5G ?",
            isPresented: $showingCellularConfirmation,
            titleVisibility: .visible
        ) {
            Button("Télécharger quand même") {
                startSync(ignoringNetworkCost: true)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tu n'es pas connecté en Wi-Fi. Télécharger toute ta collection et ses pochettes peut consommer une quantité importante de données mobiles.")
        }
        .messageAlert(message: $alertMessage)
    }

    private var isSyncCompleted: Bool {
        if case .completed = offlineManager.state { return true }
        return false
    }

    private var statusHeroCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.appOffline.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.appOffline)
                        // Petit rebond à la fin d'une synchronisation réussie.
                        .symbolEffect(.bounce, options: .nonRepeating, value: isSyncCompleted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Archive locale")
                        .font(.headline)

                    if let date = offlineManager.lastSyncDate {
                        Text("Dernière synchro : \(formattedDate(date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Aucune synchronisation effectuée")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text("\(offlineManager.offlineItemCount) disques archivés")
                            .animatedCount(offlineManager.offlineItemCount)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.appOffline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.appOffline.opacity(0.12), in: Capsule())
                    }
                }

                Spacer()
            }
        }
        .padding(.vertical, 6)
    }

    private func startSync(ignoringNetworkCost: Bool = false) {
        guard let (username, credentials) = authManager.session else {
            alertMessage = String(localized: "Connecte-toi à ton compte Discogs dans les Réglages pour synchroniser.")
            return
        }

        if !ignoringNetworkCost && networkMonitor.isExpensive {
            showingCellularConfirmation = true
            return
        }

        offlineManager.startDownload(username: username, credentials: credentials)
    }

    private func refreshCacheSize() async {
        let size = await KingfisherConfig.calculateDiskCacheSize()
        self.imageCacheSize = size
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
