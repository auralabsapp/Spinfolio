import SwiftUI
import OSLog

private let widgetSyncLogger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "WidgetSnapshotSync")

/// Navigation racine de l'app : 5 onglets, Paramètres en dernière position.
/// (Recherche n'est plus déclarée avec `role: .search` : ce rôle épingle automatiquement
/// l'onglet au bord de traille quel que soit l'ordre déclaré, ce qui empêchait Paramètres
/// d'être réellement le dernier onglet.)
/// Le scan de code-barres est intégré à la barre de recherche elle-même (pas d'onglet dédié).
struct RootTabView: View {
    @Bindable private var coordinator = TabNavigationCoordinator.shared
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.system.rawValue
    @State private var themeManager = ThemeManager.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var showingLaunchPaywall = false
    @State private var hasCheckedLaunchPaywall = false
    // Force la création de ces singletons dès le lancement de l'app plutôt qu'à la première
    // visite de leur onglet : leurs observateurs NotificationCenter (ajout/retrait déclenchés
    // depuis une fiche release) doivent déjà exister quel que soit l'onglet ouvert en premier,
    // sinon la notification part avant que quiconque l'écoute et est perdue définitivement.
    @State private var collectionViewModelWarmup = CollectionViewModel.shared
    @State private var wantlistViewModelWarmup = WantlistViewModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            Tab("Collection", systemImage: "square.stack", value: .collection) {
                NavigationStack(path: $coordinator.collectionPath) {
                    CollectionView()
                }
                .withMiniPlayer()
            }

            Tab("Wantlist", systemImage: "heart", value: .wantlist) {
                NavigationStack(path: $coordinator.wantlistPath) {
                    WantlistView()
                }
                .withMiniPlayer()
            }

            Tab("Stats", systemImage: "chart.bar.fill", value: .stats) {
                NavigationStack(path: $coordinator.statsPath) {
                    StatsView()
                }
                .withMiniPlayer()
            }

            Tab("Recherche", systemImage: "magnifyingglass", value: .search) {
                NavigationStack(path: $coordinator.searchPath) {
                    SearchView()
                }
                .withMiniPlayer()
            }

            Tab("Réglages", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
                .withMiniPlayer()
            }
        }
        .tint(themeManager.currentTheme.primaryColor)
        .environment(themeManager)
        .preferredColorScheme(AppTheme(rawValue: appThemeRawValue)?.colorScheme)
        // Réduit la barre d'onglets à l'icône de l'onglet actif quand on scrolle vers le bas
        // dans le contenu (liste Collection, Wantlist...), et la restaure dès qu'on remonte —
        // comportement standard iOS 26 (Musique, Podcasts...).
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: $showingLaunchPaywall) {
            SpinlogPaywallView()
        }
        .task {
            guard !hasCheckedLaunchPaywall else { return }
            hasCheckedLaunchPaywall = true
            if !premiumStore.isPremium {
                try? await Task.sleep(nanoseconds: 350_000_000)
                showingLaunchPaywall = true
            }
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

    /// Alimente le widget "Album du jour" dès le lancement, sans dépendre du fait que
    /// l'utilisateur visite un onglet particulier (Collection tant qu'il ne consulte pas
    /// spécifiquement le dossier "All", Stats seulement s'il y va) : ces écrans ne
    /// synchronisent la collection complète que dans des conditions spécifiques, ce qui
    /// laissait le widget vide pour beaucoup d'utilisateurs malgré une collection non vide.
    private func refreshWidgetSnapshotIfNeeded() async {
        guard authManager.isAuthenticated, let username = authManager.username else {
            widgetSyncLogger.log("Sync widget ignorée : utilisateur non connecté.")
            return
        }

        // 1. Alimentation IMMÉDIATE depuis le cache local SwiftData :
        // Si le widget est vide ou a moins de disques que le cache local, on le peuple
        // instantanément sans attendre de requête réseau ni risquer de rate limit.
        let localItems = LocalDataStore.shared.getAllCollectionItems(username: username)
        let currentSnapshotCount = WidgetSnapshotStore.loadCollection().count
        if !localItems.isEmpty && (currentSnapshotCount == 0 || localItems.count > currentSnapshotCount) {
            LocalDataStore.shared.updateWidgetSnapshot(localItems)
            widgetSyncLogger.log("Sync widget : instantané immédiatement alimenté depuis le cache local (\(localItems.count) disques).")
        }

        guard let credentials = authManager.credentials else { return }
        guard NetworkMonitor.shared.isConnected else {
            widgetSyncLogger.log("Sync widget réseau ignorée : hors ligne.")
            return
        }
        let isStale = LocalDataStore.shared.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId)
        let snapshotIsEmpty = WidgetSnapshotStore.loadCollection().isEmpty
        guard isStale || snapshotIsEmpty else {
            widgetSyncLogger.log("Sync widget ignorée : cache déjà frais et instantané non vide.")
            return
        }
        widgetSyncLogger.log("Sync widget : récupération de la collection complète (isStale=\(isStale), snapshotIsEmpty=\(snapshotIsEmpty))...")
        do {
            let items = try await DiscogsAPIClient.shared.fetchAllCollectionItems(
                username: username, folderId: DiscogsConstants.allFolderId, credentials: credentials
            )
            widgetSyncLogger.log("Sync widget : \(items.count) exemplaire(s) récupéré(s) depuis Discogs.")
            LocalDataStore.shared.syncCollectionFolder(username: username, folderId: DiscogsConstants.allFolderId, fullItems: items)
            widgetSyncLogger.log("Sync widget : instantané écrit, \(WidgetSnapshotStore.loadCollection().count) disque(s) désormais visibles par le widget.")
        } catch {
            widgetSyncLogger.error("Sync widget : échec de récupération de la collection — \(error.localizedDescription)")
            // En cas d'erreur réseau, si le widget n'a toujours rien, repli gracieux sur le cache local
            if WidgetSnapshotStore.loadCollection().isEmpty {
                let cached = LocalDataStore.shared.getAllCollectionItems(username: username)
                if !cached.isEmpty {
                    LocalDataStore.shared.updateWidgetSnapshot(cached)
                }
            }
        }
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
    var scrollToTopOfCollectionTrigger = 0
    var scrollToTopOfWantlistTrigger = 0
    var scrollToOrganizationSectionTrigger = 0

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

    func openSettings() {
        selectedTab = .settings
    }

    /// Ouvre Réglages directement positionné sur la section "Collection & Rangement" (ex: depuis
    /// "Modifier" dans la méthode de classement du guide de rangement), plutôt qu'en haut de la liste.
    func openSettingsAtOrganizationSection() {
        selectedTab = .settings
        scrollToOrganizationSectionTrigger += 1
    }

    /// Navigation profonde vers une release précise (lien `spinlog://release/{id}` ouvert depuis
    /// la Live Activity ou le widget "Album du jour"), via l'onglet Recherche.
    func openRelease(id: Int, coverURL: String? = nil) {
        searchPath = NavigationPath()
        selectedTab = .search
        searchPath.append(SearchDestination.release(id, coverURL: coverURL))
    }
}

#Preview {
    RootTabView()
}
