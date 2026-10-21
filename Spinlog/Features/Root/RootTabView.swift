import SwiftUI

/// Navigation racine de l'app : 5 onglets. Recherche est déclarée avec `role: .search`,
/// ce qui l'épingle automatiquement au bord de fin de la barre (comportement natif façon
/// Musique/Podcasts), peu importe l'ordre de déclaration ci-dessous.
/// Le scan de code-barres est intégré à la barre de recherche elle-même (pas d'onglet dédié).
struct RootTabView: View {
    @Bindable private var coordinator = TabNavigationCoordinator.shared
    @State private var appearancePreferences = AppearancePreferencesStore.shared
    @State private var themeManager = ThemeManager.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var showingLaunchPaywall = false
    // Force la création de ces singletons dès le lancement de l'app plutôt qu'à la première
    // visite de leur onglet : leurs observateurs NotificationCenter (ajout/retrait déclenchés
    // depuis une fiche release) doivent déjà exister quel que soit l'onglet ouvert en premier,
    // sinon la notification part avant que quiconque l'écoute et est perdue définitivement.
    @State private var collectionViewModelWarmup = CollectionViewModel.shared
    @State private var wantlistViewModelWarmup = WantlistViewModel.shared
    @State private var membershipStore = LibraryMembershipStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Liaison manuelle plutôt que `$coordinator.selectedTab` : un nouveau tap sur l'onglet déjà
        // actif repasse par ce setter avec la même valeur, seul moyen en SwiftUI de le détecter.
        TabView(selection: Binding(
            get: { coordinator.selectedTab },
            set: { newTab in
                if newTab == coordinator.selectedTab {
                    coordinator.handleReselection(of: newTab)
                } else {
                    coordinator.selectedTab = newTab
                }
            }
        )) {
            Tab("Collection", systemImage: "square.stack", value: .collection) {
                NavigationStack(path: $coordinator.collectionPath) {
                    CollectionView()
                }
            }

            Tab("Wantlist", systemImage: "heart", value: .wantlist) {
                NavigationStack(path: $coordinator.wantlistPath) {
                    WantlistView()
                }
            }

            Tab("Stats", systemImage: "chart.bar.fill", value: .stats) {
                NavigationStack(path: $coordinator.statsPath) {
                    StatsView()
                }
            }

            Tab("Recherche", systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack(path: $coordinator.searchPath) {
                    SearchView()
                }
            }

            Tab("Réglages", systemImage: "gearshape", value: .settings) {
                NavigationStack(path: $coordinator.settingsPath) {
                    SettingsView()
                }
            }
        }
        .tint(themeManager.currentTheme.primaryColor)
        .environment(themeManager)
        .preferredColorScheme(appearancePreferences.appearance.colorScheme)
        // Réduit la barre d'onglets à l'icône de l'onglet actif quand on scrolle vers le bas
        // dans le contenu (liste Collection, Wantlist...), et la restaure dès qu'on remonte —
        // comportement standard iOS 26 (Musique, Podcasts...).
        .tabBarMinimizeBehavior(.onScrollDown)
        // Mini-lecteur audio : au-dessus de la barre quand elle est normale, inline entre l'icône
        // de l'onglet courant et l'icône de recherche quand elle est réduite (comportement natif
        // identique à Musique). `MiniPlayerBar` adapte sa présentation via `tabViewBottomAccessoryPlacement`.
        .tabViewBottomAccessory(isEnabled: MiniPlayerBar.isActive) {
            MiniPlayerBar()
        }
        // Bulle de confirmation ajout/retrait collection/wantlist (voir `LibraryMembershipStore`) :
        // overlay global plutôt que posé sur chaque écran, puisque l'action peut partir de
        // n'importe quel onglet (résultats de recherche, fiche release/artiste, Collection, Wantlist...).
        .overlay(alignment: .bottom) {
            if let toast = membershipStore.activeToast {
                LibraryToastBubble(kind: toast, queuedOffline: membershipStore.activeToastIsQueuedOffline)
                    // L'overlay couvre tout le `TabView`, barre d'onglets comprise : il faut
                    // donc une marge qui dépasse sa hauteur (+ celle du mini-lecteur si affiché)
                    // pour que la bulle flotte au-dessus plutôt que d'être masquée derrière.
                    .padding(.bottom, MiniPlayerBar.isActive ? 150 : 95)
            }
        }
        .fullScreenCover(isPresented: $showingLaunchPaywall) {
            SpinlogPaywallView()
        }
        // Présenté une fois l'utilisateur connecté (compte Discogs ou démo), jamais avant l'écran
        // de connexion : un nouvel utilisateur voyait l'offre avant même de savoir ce qu'est l'app.
        // Relancé à la connexion (`isAuthenticated` change) ; la limite hebdomadaire évite de la
        // représenter ensuite.
        .task(id: authManager.isAuthenticated) {
            // Abonnement réel : l'aperçu Premium de la démo ne dispense pas de voir l'offre.
            guard LaunchPaywallSchedule.shouldPresent(
                isAuthenticated: authManager.isAuthenticated,
                hasSubscription: premiumStore.hasAccessOutsideDemo
            ), !Self.isUITestLaunch else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            // Déconnexion pendant l'attente : plus de raison d'afficher l'offre.
            guard !Task.isCancelled, authManager.isAuthenticated else { return }
            showingLaunchPaywall = true
            LaunchPaywallSchedule.markShown()
        }
        .task(id: authManager.isAuthenticated) {
            await refreshWidgetSnapshotIfNeeded()
            autoSyncOfflineIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                themeManager.revertToDefaultIfNeeded(isPremium: PremiumStore.shared.isPremium)
                Task {
                    await refreshWidgetSnapshotIfNeeded()
                }
                autoSyncOfflineIfNeeded()
            }
        }
    }

    /// Les tests d'interface démarrent sans paywall, pour arriver directement sur les onglets.
    private static var isUITestLaunch: Bool {
        #if DEBUG
        UITestLaunchOptions.isActive
        #else
        false
        #endif
    }

    /// Relance silencieusement le téléchargement complet hors ligne (Premium) si l'utilisateur
    /// a activé la synchro auto Wi-Fi dans Réglages > Mode Hors Ligne. Appelé aux mêmes points
    /// d'entrée que le rafraîchissement du widget : lancement et retour au premier plan.
    private func autoSyncOfflineIfNeeded() {
        guard authManager.isAuthenticated, let username = authManager.username else { return }
        OfflineDownloadManager.shared.autoSyncIfNeeded(
            username: username,
            credentials: authManager.credentials,
            isPremium: premiumStore.isPremium
        )
    }

    /// Délègue à `WidgetSnapshotSyncService` (voir son commentaire pour le détail) : ne reste ici
    /// que la vérification d'authentification, propre à cet appelant.
    private func refreshWidgetSnapshotIfNeeded() async {
        guard authManager.isAuthenticated, let username = authManager.username else { return }
        await WidgetSnapshotSyncService.shared.refreshIfNeeded(username: username, credentials: authManager.credentials)
    }
}

/// Fréquence du paywall présenté après la connexion : dès la première connexion, puis au plus une
/// fois par semaine. L'afficher à chaque ouverture lassait les utilisateurs gratuits (et un paywall
/// systématique est un motif courant de remarque en App Review) ; l'offre reste accessible à
/// tout moment depuis Réglages et les fonctions Premium verrouillées.
enum LaunchPaywallSchedule {
    private static let lastShownKey = "launchPaywallLastShownAt"
    private static let minimumInterval: TimeInterval = 7 * 24 * 3600

    /// Règle de présentation : seulement une fois connecté (compte ou démo), sans abonnement réel,
    /// et si la dernière présentation remonte à plus d'une semaine.
    /// `hasSubscription` : accès Premium hors aperçu de la démo (`PremiumStore.hasAccessOutsideDemo`).
    static func shouldPresent(
        isAuthenticated: Bool,
        hasSubscription: Bool,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        isAuthenticated && !hasSubscription && isDue(now: now, defaults: defaults)
    }

    static func isDue(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        let lastShown = defaults.double(forKey: lastShownKey)
        guard lastShown > 0 else { return true }
        return now.timeIntervalSince1970 - lastShown >= minimumInterval
    }

    static func markShown(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: lastShownKey)
    }
}

enum AppTab: Hashable {
    case collection
    case wantlist
    case settings
    case search
    case stats
}

@MainActor
@Observable
final class TabNavigationCoordinator {
    static let shared = TabNavigationCoordinator()

    var selectedTab: AppTab = .collection
    var collectionPath = NavigationPath()
    var wantlistPath = NavigationPath()
    var searchPath = NavigationPath()
    var statsPath = NavigationPath()
    var settingsPath = NavigationPath()
    var scrollToTopOfCollectionTrigger = 0
    var scrollToTopOfWantlistTrigger = 0
    var scrollToTopOfStatsTrigger = 0
    var scrollToTopOfSearchTrigger = 0
    var scrollToTopOfSettingsTrigger = 0
    var scrollToOrganizationSectionTrigger = 0

    /// Nouveau tap sur l'onglet déjà actif : revient à la racine si une fiche est ouverte,
    /// sinon remonte tout en haut de l'onglet (comportement standard iOS).
    func handleReselection(of tab: AppTab) {
        switch tab {
        case .collection:
            if !collectionPath.isEmpty { collectionPath = NavigationPath() } else { scrollToTopOfCollectionTrigger += 1 }
        case .wantlist:
            if !wantlistPath.isEmpty { wantlistPath = NavigationPath() } else { scrollToTopOfWantlistTrigger += 1 }
        case .stats:
            if !statsPath.isEmpty { statsPath = NavigationPath() } else { scrollToTopOfStatsTrigger += 1 }
        case .search:
            if !searchPath.isEmpty { searchPath = NavigationPath() } else { scrollToTopOfSearchTrigger += 1 }
        case .settings:
            if !settingsPath.isEmpty { settingsPath = NavigationPath() } else { scrollToTopOfSettingsTrigger += 1 }
        }
    }
    /// Alerte à ouvrir dès que `WantlistView` peut résoudre l'élément (au lancement à froid, la
    /// wantlist n'est pas encore chargée au moment du tap sur la notification).
    var pendingWantlistAlertReleaseId: Int?

    /// Destination actuellement au sommet de chaque onglet
    var currentTopDestination: [AppTab: SearchDestination] = [:]

    func registerTopDestination(_ destination: SearchDestination) {
        currentTopDestination[selectedTab] = destination
    }

    func unregisterTopDestination(_ destination: SearchDestination) {
        if currentTopDestination[selectedTab] == destination {
            currentTopDestination[selectedTab] = nil
        }
    }

    /// Revient instantanément sur la vue (Release ou Master) où la lecture a été lancée
    func returnToPlayingItem(_ item: NowPlayingItem) {
        guard let destination = item.destination else { return }
        selectedTab = item.sourceTab

        switch item.sourceTab {
        case .collection:
            if currentTopDestination[.collection] != destination {
                collectionPath.append(destination)
            }
        case .wantlist:
            if currentTopDestination[.wantlist] != destination {
                wantlistPath.append(destination)
            }
        case .search:
            if currentTopDestination[.search] != destination {
                searchPath.append(destination)
            }
        case .stats:
            if currentTopDestination[.stats] != destination {
                statsPath.append(destination)
            }
        case .settings:
            selectedTab = .search
            if currentTopDestination[.search] != destination {
                searchPath = NavigationPath()
                searchPath.append(destination)
            }
        }
    }

    /// Revient ou navigue instantanément vers la release en cours d'écoute sur la platine
    func returnToRelease(releaseId: Int, coverURL: String?) {
        let destination = SearchDestination.release(releaseId, coverURL: coverURL)
        switch selectedTab {
        case .collection:
            if currentTopDestination[.collection] != destination {
                collectionPath.append(destination)
            }
        case .wantlist:
            if currentTopDestination[.wantlist] != destination {
                wantlistPath.append(destination)
            }
        case .search:
            if currentTopDestination[.search] != destination {
                searchPath.append(destination)
            }
        case .stats:
            if currentTopDestination[.stats] != destination {
                statsPath.append(destination)
            }
        case .settings:
            selectedTab = .collection
            if currentTopDestination[.collection] != destination {
                collectionPath.append(destination)
            }
        }
    }

    func openCollectionAtTop() {
        if !collectionPath.isEmpty {
            collectionPath = NavigationPath()
        }
        selectedTab = .collection
        scrollToTopOfCollectionTrigger += 1
    }

    func openWantlistAtTop() {
        if !wantlistPath.isEmpty {
            wantlistPath = NavigationPath()
        }
        selectedTab = .wantlist
        scrollToTopOfWantlistTrigger += 1
    }

    func openWantlistAlert(releaseId: Int) {
        if !wantlistPath.isEmpty {
            wantlistPath = NavigationPath()
        }
        selectedTab = .wantlist
        pendingWantlistAlertReleaseId = releaseId
    }

    /// Ouvre Réglages directement positionné sur la section "Collection & Rangement" (ex: depuis
    /// "Modifier" dans la méthode de classement du guide de rangement), plutôt qu'en haut de la liste.
    func openSettingsAtOrganizationSection() {
        // Section de la racine de Réglages : un sous-écran resté ouvert la masquerait.
        settingsPath = NavigationPath()
        selectedTab = .settings
        scrollToOrganizationSectionTrigger += 1
    }

    /// Navigation profonde vers une release précise (lien `spinlog://release/{id}` ouvert depuis
    /// la Live Activity ou le widget "Album du jour"). Poussée sur l'onglet courant (Collection
    /// depuis Réglages) sans vider sa pile : auparavant, l'onglet Recherche était toujours vidé,
    /// ce qui faisait perdre la recherche ou la fiche en cours de consultation.
    func openRelease(id: Int, coverURL: String? = nil) {
        returnToRelease(releaseId: id, coverURL: coverURL)
    }
}

#Preview {
    RootTabView()
}
