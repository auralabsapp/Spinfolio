import SwiftUI

/// Écran d'accueil de Réglages : le compte, puis une ligne par sujet — chacune ouvre sa page
/// (Organisation, Rangement, Suivi de plus-value, Export, Écoute, iCloud, hors ligne, Apparence, Guide,
/// À propos) — et une recherche qui retrouve n'importe quel réglage. Les réglages eux-mêmes vivent dans
/// ces pages ; seul ce qui concerne le compte (déconnexion, suppression) reste ici.
struct SettingsView: View {
    @State private var themeManager = ThemeManager.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var shelfPreferences = ShelfPreferencesStore.shared
    @State private var cloudSyncEngine = CloudSyncEngine.shared
    @State private var tabCoordinator = TabNavigationCoordinator.shared
    @State private var showingPremiumFeaturesSheet = false
    @State private var showingLogoutConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingEraseDataSheet = false
    @State private var showingDeleteAccountWebsite = false
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        applySheetsAndAlerts(to: applyDialogs(to: content))
            .navigationDestination(for: SettingsDestination.self) { destination in
                destination.view
            }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if isSearching {
                SettingsSearchResultsView(query: searchText)
            } else {
                settingsList
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher un réglage")
        .navigationTitle("Réglages")
        .serifNavigationTitle()
    }

    @ViewBuilder
    private func applyDialogs(to content: some View) -> some View {
        content
            .confirmationDialog("Se déconnecter", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) {
                    authManager.logout()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Veux-tu vraiment te déconnecter de ton compte Discogs ?")
            }
            .confirmationDialog(
                "Supprimer le compte Discogs",
                isPresented: $showingDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer le compte sur Discogs.com", role: .destructive) {
                    showingDeleteAccountWebsite = true
                }
                Button("Effacer les données de l'app…", role: .destructive) {
                    showingEraseDataSheet = true
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ton compte est géré par Discogs. Pour supprimer définitivement ton compte et l'ensemble de tes données, tu dois finaliser la demande sur le site officiel de Discogs.\n\nTu peux aussi effacer les données de l'app (historique d'écoute, tags, alertes, préférences), sur cet appareil et sur iCloud. C'est irréversible : tu devras le confirmer à l'étape suivante.")
            }
    }

    @ViewBuilder
    private func applySheetsAndAlerts(to content: some View) -> some View {
        content
            .sheet(isPresented: $showingDeleteAccountWebsite) {
                SafariView(url: DiscogsConstants.accountDeletionURL)
            }
            .eraseAccountDataSheet(isPresented: $showingEraseDataSheet) {
                authManager.deleteLocalAccountData()
            }
            .premiumFeaturesSheet(isPresented: $showingPremiumFeaturesSheet)
    }

    // MARK: - Accueil

    @ViewBuilder
    private var settingsList: some View {
        ScrollViewReader { proxy in
            List {
                // `hasAccessOutsideDemo` (abonnement réel, ou forçage développeur en Debug) :
                // l'offre reste proposée pendant l'aperçu Premium de la démo.
                if !premiumStore.hasAccessOutsideDemo {
                    Section {
                        SettingsPremiumHeroBanner {
                            showingPremiumFeaturesSheet = true
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .id("premiumBanner")
                }
                SettingsAccountSection()
                    .id("accountSection")
                // Hors App Store seulement (TestFlight, sandbox, Xcode) : voir la section.
                SubscriptionDiagnosticSection()
                collectionGroup
                listeningGroup
                synchronizationGroup
                helpAndPersonalizationGroup
                logoutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .listRowSeparatorTint(Color.appSeparator)
            .onChange(of: premiumStore.isPremium) { _, isPremium in
                themeManager.revertToDefaultIfNeeded(isPremium: isPremium)
            }
            .onChange(of: tabCoordinator.scrollToTopOfSettingsTrigger) {
                withAnimation {
                    proxy.scrollTo(premiumStore.hasAccessOutsideDemo ? "accountSection" : "premiumBanner", anchor: .top)
                }
            }
        }
    }

    // MARK: - Groupes de pages

    private var collectionGroup: some View {
        Section {
            NavigationLink(value: SettingsDestination.organization) {
                SettingsHubRow(
                    icon: "tag.fill", color: .orange, title: "Organisation",
                    subtitle: String(localized: "Tags, dossiers et tri par artiste")
                )
            }
            NavigationLink(value: SettingsDestination.shelving) {
                SettingsHubRow(
                    icon: "books.vertical.fill", color: .indigo, title: "Rangement",
                    subtitle: shelfPreferences.sortStrategy.title
                )
            }
            NavigationLink(value: SettingsDestination.gainTracking) {
                SettingsHubRow(
                    icon: "chart.line.uptrend.xyaxis", color: .green, title: "Suivi de plus-value",
                    subtitle: String(localized: "Prix d'achat, état du disque et devise"),
                    isPremiumFeature: true
                )
            }
            NavigationLink(value: SettingsDestination.export) {
                SettingsHubRow(
                    icon: "square.and.arrow.up.fill", color: .blue, title: "Export",
                    subtitle: String(localized: "CSV et déclaration PDF"),
                    isPremiumFeature: true
                )
            }
        } header: {
            SectionEyebrow(title: "Ma collection", icon: "square.stack.fill")
        }
    }

    private var listeningGroup: some View {
        Section {
            NavigationLink(value: SettingsDestination.listening) {
                SettingsHubRow(
                    icon: "opticaldisc.fill", color: .pink, title: "Écoute et Apple Music",
                    subtitle: String(localized: "Arrêt automatique et compte Apple Music")
                )
            }
        } header: {
            SectionEyebrow(title: "Écoute", icon: "waveform")
        }
    }

    private var synchronizationGroup: some View {
        Section {
            NavigationLink(value: SettingsDestination.iCloud) {
                SettingsHubRow(
                    icon: "icloud.fill", color: .blue, title: "Synchronisation iCloud",
                    subtitle: iCloudSummary,
                    isPremiumFeature: true
                )
            }
            NavigationLink(value: premiumStore.isPremium ? SettingsDestination.offline : SettingsDestination.offlineLocked) {
                SettingsHubRow(
                    icon: "arrow.down.circle.fill", color: .teal, title: "Données hors ligne",
                    subtitle: offlineSummary,
                    isPremiumFeature: true
                )
            }
        } header: {
            SectionEyebrow(title: "Synchronisation", icon: "arrow.triangle.2.circlepath")
        }
    }

    private var helpAndPersonalizationGroup: some View {
        Section {
            NavigationLink(value: SettingsDestination.appearance) {
                SettingsHubRow(
                    icon: "paintbrush.fill", color: .purple, title: "Apparence",
                    subtitle: String(localized: "Mode d'affichage et thème")
                )
            }
            NavigationLink(value: SettingsDestination.guide) {
                SettingsHubRow(
                    icon: "book.fill", color: .indigo, title: "Guide",
                    subtitle: String(localized: "Découvre les fonctions de l'app")
                )
            }
            NavigationLink(value: SettingsDestination.about) {
                SettingsHubRow(
                    icon: "info.circle.fill", color: .brown, title: "À propos",
                    subtitle: AppInfo.versionString
                )
            }
        } header: {
            SectionEyebrow(title: "Aide & personnalisation", icon: "sparkles")
        }
    }

    // MARK: - Résumés

    private var iCloudSummary: String {
        guard premiumStore.isPremium else { return String(localized: "Fonction Premium") }
        let isOn = !authManager.isDemoMode && cloudSyncEngine.isUserEnabled
        return isOn ? String(localized: "Activée") : String(localized: "Désactivée")
    }

    private var offlineSummary: String {
        guard premiumStore.isPremium else { return String(localized: "Fonction Premium") }
        if let date = OfflineDownloadManager.shared.lastSyncDate {
            return String(localized: "Synchronisé le \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        return String(localized: "Aucune archive locale complète")
    }

    // MARK: - 6. Déconnexion (Bouton centré rouge en bas)

    @ViewBuilder
    private var logoutSection: some View {
        if authManager.isDemoMode {
            Section {
                Button {
                    authManager.logout()
                } label: {
                    HStack {
                        Spacer()
                        Text("Quitter le mode démo")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .accessibilityIdentifier("settingsExitDemoButton")
            }
        } else if authManager.isAuthenticated {
            Section {
                Button {
                    showingLogoutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Se déconnecter")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }

                Button(role: .destructive) {
                    showingDeleteAccountConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Supprimer mon compte...", systemImage: "trash")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            } footer: {
                Text("Ton compte est hébergé sur Discogs. Tu peux lancer la suppression définitive de ton compte ou effacer les données locales et synchronisées sur iCloud (tags, historique d'écoute, préférences).")
            }
        }
    }

}
