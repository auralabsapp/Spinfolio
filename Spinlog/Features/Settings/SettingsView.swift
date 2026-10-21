import SwiftUI
import StoreKit
import UniformTypeIdentifiers

/// Sections autonomes (compte, écoute, Apple Music, hors ligne, apparence) : voir
/// `SettingsSections.swift`. Restent ici celles qui partagent l'état chargé par cet écran.
struct SettingsView: View {
    @State private var themeManager = ThemeManager.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var tagStore = TagStore.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var shelfPreferences = ShelfPreferencesStore.shared
    @State private var tabCoordinator = TabNavigationCoordinator.shared
    @State private var showingDiscogsWebsite = false
    @State private var showingManageSubscriptions = false
    @State private var showingPremiumFeaturesSheet = false
    @State private var showingLogoutConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingDeleteAccountWebsite = false
    @State private var isShelfRuleHighlighted = false

    // Export CSV/PDF de la collection (appels réseau délégués à ce ViewModel)
    @State private var exportViewModel = CollectionExportViewModel()

    // Dossier d'ajout par défaut
    @State private var defaultFolderId: Int = CollectionPreferencesStore.alwaysAskFolderId

    // Suivi de cote (prix d'achat)
    @State private var availableCollectionFields: [CollectionField] = []
    @State private var purchasePriceFieldId: Int?
    @State private var mediaConditionFieldId: Int?
    @State private var defaultCurrency: String = "EUR" 

    var body: some View {
        applySheetsAndAlerts(to: applyDialogs(to: settingsList))
            .navigationDestination(for: SettingsDestination.self) { destination in
                destination.view
            }
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
                Button("Effacer les données locales & iCloud et se déconnecter", role: .destructive) {
                    authManager.deleteLocalAccountData()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ton compte est géré par Discogs. Pour supprimer définitivement ton compte et l'ensemble de tes données, tu dois finaliser la demande sur le site officiel de Discogs.\n\nTu peux également effacer immédiatement toutes les données stockées par l'application sur cet appareil et synchronisées sur iCloud (tags, historique d'écoute, préférences).")
            }
    }

    @ViewBuilder
    private func applySheetsAndAlerts(to content: some View) -> some View {
        content
            .alert(exportViewModel.alertTitle, isPresented: $exportViewModel.showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportViewModel.alertMessage)
            }
            .sheet(isPresented: $showingDiscogsWebsite) {
                SafariView(url: DiscogsConstants.websiteURL)
            }
            .sheet(isPresented: $showingDeleteAccountWebsite) {
                SafariView(url: DiscogsConstants.accountDeletionURL)
            }
            .premiumFeaturesSheet(isPresented: $showingPremiumFeaturesSheet)
            .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
            .task {
                loadDefaultFolder()
                await loadPurchasePriceSettings()
            }
            // Sans ça, un dossier par défaut/champ de suivi de cote/devise mis à jour par
            // `CloudSyncEngine` depuis un autre appareil est bien écrit en local (UserDefaults),
            // mais cet écran continue d'afficher l'ancienne valeur tant qu'il reste ouvert — les
            // `@State` ci-dessus ne sont chargés qu'une seule fois via `.task`, qui ne se
            // redéclenche pas de lui-même.
            .onReceive(NotificationCenter.default.publisher(for: .collectionPreferencesChanged)) { _ in
                Task {
                    loadDefaultFolder()
                    await loadPurchasePriceSettings()
                }
            }
    }


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
                Group {
                    SettingsAccountSection()
                        .id("accountSection")
                    // Hors App Store seulement (TestFlight, sandbox, Xcode) : voir la section.
                    SubscriptionDiagnosticSection()
                    organizationSection
                        .id("organizationSection")
                    SettingsListeningSection()
                    SettingsAppleMusicSection()
                    gainTrackingSection
                    purchasePriceSection
                    SettingsOfflineSection()
                    SettingsICloudSyncSection()
                    exportSection
                }
                Group {
                    SettingsAppearanceSection()
                    aboutSection
                    logoutSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .listRowSeparatorTint(Color.appSeparator)
            .navigationTitle("Réglages")
            .serifNavigationTitle()
            .onChange(of: premiumStore.isPremium) { _, isPremium in
                themeManager.revertToDefaultIfNeeded(isPremium: isPremium)
            }
            .onChange(of: tabCoordinator.scrollToTopOfSettingsTrigger) {
                withAnimation {
                    proxy.scrollTo(premiumStore.hasAccessOutsideDemo ? "accountSection" : "premiumBanner", anchor: .top)
                }
            }
            .onChange(of: tabCoordinator.scrollToOrganizationSectionTrigger) { _, newValue in
                guard newValue > 0 else { return }
                Task { @MainActor in
                    // Délai plus généreux que `scrollSettleDelay` : ce déclenchement arrive en
                    // même temps que la fermeture de la sheet "Guide de rangement" et le
                    // changement d'onglet, qui doivent terminer leur animation avant de scroller
                    // sans quoi le titre de section finit caché/mal positionné sous la barre de
                    // navigation. L'ancrage n'est pas strictement `.top` pour garder une marge de
                    // respiration au-dessus du titre plutôt que de le coller au bord de l'écran.
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation { proxy.scrollTo("organizationSection", anchor: UnitPoint(x: 0.5, y: 0.08)) }
                    // Seul point d'entrée : « Modifier » du guide de rangement. La règle de
                    // rangement est mise en évidence 2 s pour qu'on la repère tout de suite.
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.settingsRowHighlight) { isShelfRuleHighlighted = true }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.settingsRowHighlight) { isShelfRuleHighlighted = false }
                }
            }
        }
    }


    // MARK: - 2. Collection & Rangement

    @ViewBuilder
    private var organizationSection: some View {
        Section {
            NavigationLink(value: SettingsDestination.tags) {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "tag.fill", backgroundColor: .orange)
                    Text("Gestion des tags")
                    Spacer()
                    let count = tagStore.allTags.count
                    Text(count == 0 ? "Aucun" : "\(count)")
                        .foregroundStyle(Color.appSecondaryText)
                }
            }

            if authManager.isAuthenticated {
                NavigationLink(value: SettingsDestination.folders) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "folder.fill", backgroundColor: .blue)
                        Text("Gestion des dossiers")
                        Spacer()
                        Text(defaultFolderName)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            }

            Picker(selection: $shelfPreferences.sortStrategy) {
                ForEach(ShelfSortStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            } label: {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "books.vertical.fill", backgroundColor: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Règle de rangement dans le meuble")
                            .foregroundStyle(.primary)
                        Text(shelfPreferences.sortStrategy.title)
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            }
            .pickerStyle(.menu)
            .tint(Color.spinlogPink)
            // Fond de ligne par défaut, teinté le temps de la mise en évidence (voir
            // `scrollToOrganizationSectionTrigger`), comme les badges actifs de l'app.
            .listRowBackground(
                ZStack {
                    Color(uiColor: .secondarySystemGroupedBackground)
                    Color.spinlogPinkBadge
                        .opacity(isShelfRuleHighlighted ? 1 : 0)
                }
            )

            Toggle(isOn: $shelfPreferences.ignoreArticles) {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "text.quote", backgroundColor: .teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ignorer les articles (The...)")
                            .foregroundStyle(.primary)
                        Text("Ex : « Beatles, The » si actif, sinon « The Beatles »")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            }
            .tint(Color.spinlogPink)

            Toggle(isOn: $shelfPreferences.sortByLastName) {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "person.text.rectangle", backgroundColor: .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trier par nom de famille")
                            .foregroundStyle(.primary)
                        Text("S'applique à tous les tris par artiste (meuble, Collection, Wantlist)")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            }
            .tint(Color.spinlogPink)

            Toggle(isOn: $shelfPreferences.restrictToSameFolder) {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "square.stack.3d.up.fill", backgroundColor: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Limiter au dossier Discogs")
                            .foregroundStyle(.primary)
                        Text("Le guide de rangement ne compare qu'au dossier du disque, plutôt qu'à toute la collection")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            }
            .tint(Color.spinlogPink)

            if shelfPreferences.sortByLastName {
                NavigationLink(value: SettingsDestination.artistSort) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "slider.horizontal.3", backgroundColor: .pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Personnaliser le tri des artistes")
                                .foregroundStyle(.primary)
                            let count = shelfPreferences.customArtistSortOverrides.count
                            Text(count > 0 ? "\(count) artistes personnalisés" : "Ajuster l'ordre artiste par artiste")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
            }
        } header: {
            SectionEyebrow(title: "Collection & Rangement", icon: "books.vertical.fill")
        } footer: {
            Text("Personnalise tes tags, le dossier d'enregistrement par défaut et les règles de tri appliquées à ton meuble physique et ta collection.")
        }
    }

    // MARK: - 2bis. Prix d'achat et état (gratuit)

    /// Réglages gratuits : le prix d'achat est un champ personnalisé Discogs que chacun peut
    /// remplir (ici comme sur discogs.com), et l'état et la devise servent aussi à la cote, elle
    /// aussi gratuite. Seul le calcul de la plus-value est Premium (`gainTrackingSection`).
    @ViewBuilder
    private var purchasePriceSection: some View {
        if authManager.isAuthenticated {
            Section {
                Picker(selection: Binding(
                    get: { purchasePriceFieldId ?? -1 },
                    set: { newValue in
                        let fieldId = newValue == -1 ? nil : newValue
                        purchasePriceFieldId = fieldId
                        if let user = authManager.username {
                            CollectionPreferencesStore.setPurchasePriceFieldId(fieldId, for: user)
                        }
                    }
                )) {
                    Text("Aucun").tag(-1)
                    ForEach(availableCollectionFields) { field in
                        Text(field.name).tag(field.id)
                    }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "tag.fill", backgroundColor: .green)
                        Text("Champ prix d'achat")
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.spinlogPink)

                Picker(selection: Binding(
                    get: { mediaConditionFieldId ?? -1 },
                    set: { newValue in
                        let fieldId = newValue == -1 ? nil : newValue
                        mediaConditionFieldId = fieldId
                        if let user = authManager.username {
                            CollectionPreferencesStore.setMediaConditionFieldId(fieldId, for: user)
                        }
                    }
                )) {
                    Text("Aucun").tag(-1)
                    ForEach(availableCollectionFields) { field in
                        Text(field.name).tag(field.id)
                    }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "opticaldisc.fill", backgroundColor: .purple)
                        Text("Champ état du disque")
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.spinlogPink)

                Picker(selection: Binding(
                    get: { defaultCurrency },
                    set: { newValue in
                        defaultCurrency = newValue
                        if let user = authManager.username {
                            CollectionPreferencesStore.setDefaultCurrency(newValue, for: user)
                        }
                    }
                )) {
                    ForEach(PurchasePriceParser.supportedCurrencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "eurosign.circle.fill", backgroundColor: .blue)
                        Text("Devise par défaut")
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.spinlogPink)
            } header: {
                SectionEyebrow(title: "Prix d'achat et état", icon: "tag.fill")
            } footer: {
                Text("Associe les champs personnalisés Discogs correspondants à ton prix d'achat et à l'état de conservation pour alimenter le suivi de valeur.")
            }
        }
    }

    // MARK: - 2ter. Suivi de plus-value (Premium)

    @ViewBuilder
    private var gainTrackingSection: some View {
        Section {
            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Suivi de plus-value",
                    message: "Passe premium pour comparer ton investissement à la cote actuelle et suivre ta plus-value."
                )
            }
            // Accessible à tous, abonnés ou non : cette aide explique quoi saisir dans le prix
            // d'achat et l'état de la pochette, des champs que chacun remplit même sans Premium.
            NavigationLink(value: SettingsDestination.purchasePriceHelp) {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "questionmark.circle.fill", backgroundColor: .mint)
                    Text("Comment ça fonctionne ?")
                }
            }
        } header: {
            SectionEyebrow(title: "Suivi de plus-value", icon: "chart.line.uptrend.xyaxis", isPremiumFeature: true)
        }
    }

    // MARK: - 4. Export

    @ViewBuilder
    private var exportSection: some View {
        Section {
            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "tablecells.fill",
                    title: "Export CSV de la collection",
                    message: "Passe premium pour exporter toute ta discothèque avec métadonnées, notes et tags."
                )
            } else {
                Button {
                    Task { await exportViewModel.exportCSV() }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "tablecells", backgroundColor: .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exporter la collection en CSV")
                                .font(.body)
                                .foregroundStyle(authManager.isAuthenticated ? .primary : .secondary)
                            Text(csvExportSubtitle)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        if exportViewModel.isExportingCSV {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.appTertiaryText)
                        }
                    }
                }
                .disabled(!authManager.isAuthenticated || exportViewModel.isExportingCSV)

                Button {
                    Task { await exportViewModel.exportPDF() }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "doc.richtext", backgroundColor: .indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Déclaration de collection (PDF)")
                                .font(.body)
                                .foregroundStyle(authManager.isAuthenticated ? .primary : .secondary)
                            Text(pdfExportSubtitle)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        if exportViewModel.isExportingPDF {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.appTertiaryText)
                        }
                    }
                }
                .disabled(!authManager.isAuthenticated || exportViewModel.isExportingPDF)
            }
        } header: {
            // Badge de démo sur le titre : toute la section (CSV et PDF) est Premium.
            SectionEyebrow(title: "Export", icon: "square.and.arrow.up.fill", isPremiumFeature: true)
        } footer: {
            Text("L'export CSV regroupe tous tes albums (tous dossiers confondus) avec leurs métadonnées, tags et notes pour tes tableurs (Excel, Numbers). La déclaration PDF liste la collection avec état et prix d'achat, à présenter par exemple à un assureur.")
        }
    }

    private var pdfExportSubtitle: String {
        if exportViewModel.isExportingPDF {
            return String(localized: "Génération du document en cours…")
        }
        if authManager.isAuthenticated {
            return String(localized: "Pochettes, état et prix d'achat, tous dossiers confondus")
        } else {
            return String(localized: "Connexion à Discogs requise")
        }
    }

    private var csvExportSubtitle: String {
        if exportViewModel.isExportingCSV {
            return String(localized: "Génération du fichier en cours…")
        }
        if authManager.isAuthenticated {
            return String(localized: "Tous dossiers confondus avec tags et notes")
        } else {
            return String(localized: "Connexion à Discogs requise")
        }
    }

    // MARK: - 6. À propos & Assistance

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            Button {
                showingDiscogsWebsite = true
            } label: {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "globe", backgroundColor: .cyan)
                    Text("Site web Discogs")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
            }

            // Feuille système StoreKit (lecture seule, aucun risque à l'exposer partout,
            // contrairement aux outils du menu développeur) : état réel de l'abonnement, utile
            // notamment en TestFlight pour vérifier qu'un essai Sandbox précédent n'en a pas
            // laissé un actif avant d'en retenter un nouveau depuis le paywall.
            Button {
                showingManageSubscriptions = true
            } label: {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "creditcard.fill", backgroundColor: .indigo)
                    Text("Gérer mon abonnement")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.appTertiaryText)
                }
            }

            #if DEBUG
            NavigationLink(value: SettingsDestination.developerOptions) {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "hammer.fill", backgroundColor: .gray)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Options développeur")
                            .foregroundStyle(.primary)
                        Text("Debug, sauvegardes JSON & simulations")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
            #endif

            HStack(spacing: 14) {
                SettingsIcon(systemName: "info.circle.fill", backgroundColor: .brown)
                Text("Version")
                Spacer()
                Text(appVersionString)
                    .foregroundStyle(Color.appSecondaryText)
            }
        } header: {
            SectionEyebrow(title: "À propos", icon: "info.circle.fill")
        } footer: {
            Text("\(AppInfo.name) utilise l'API publique Discogs mais n'est ni affilié à ni approuvé par Discogs.")
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
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

    private func loadDefaultFolder() {
        guard let username = authManager.username else { return }
        defaultFolderId = CollectionPreferencesStore.defaultAddFolderId(for: username)
    }

    private var defaultFolderName: String {
        if defaultFolderId == CollectionPreferencesStore.alwaysAskFolderId {
            return String(localized: "Toujours demander")
        }
        return CollectionViewModel.shared.folders.first { $0.id == defaultFolderId }?.name ?? ""
    }

    /// Charge les champs personnalisés Discogs et, pour chaque champ pas déjà configuré (prix
    /// d'achat, état du disque), tente une détection automatique par mots-clés insensible à la
    /// casse et aux accents.
    private func loadPurchasePriceSettings() async {
        guard let username = authManager.username else { return }
        defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)
        purchasePriceFieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username)
        mediaConditionFieldId = CollectionPreferencesStore.mediaConditionFieldId(for: username)

        guard NetworkMonitor.shared.isConnected else { return }
        let fields = await ReleaseActions.fetchCollectionFields(username: username, credentials: authManager.credentials)
        guard !fields.isEmpty else { return }
        availableCollectionFields = fields

        if purchasePriceFieldId == nil {
            let keywords = ["prix d'achat", "prix", "purchase price", "price", "bought for", "cost"]
            if let detected = fields.first(where: { field in
                let normalized = field.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                return keywords.contains { normalized.contains($0) }
            }) {
                purchasePriceFieldId = detected.id
                CollectionPreferencesStore.setPurchasePriceFieldId(detected.id, for: username)
            }
        }

        if mediaConditionFieldId == nil {
            // Discogs fournit aussi par défaut "Sleeve Condition" (état de la pochette) : on
            // l'exclut explicitement pour ne pas la confondre avec l'état du média.
            if let detected = fields.first(where: { field in
                let normalized = field.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                guard !normalized.contains("sleeve"), !normalized.contains("pochette") else { return false }
                return normalized.contains("media condition") || normalized.contains("etat du media") || normalized.contains("etat du disque")
            }) {
                mediaConditionFieldId = detected.id
                CollectionPreferencesStore.setMediaConditionFieldId(detected.id, for: username)
            }
        }
    }

}
