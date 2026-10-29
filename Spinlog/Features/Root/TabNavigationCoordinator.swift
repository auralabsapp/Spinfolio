import SwiftUI

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
    /// Réduction de la barre d'onglets au défilement : `.onScrollDown` en temps normal,
    /// brièvement `.never` quand `expandTabBar()` force son retour.
    private(set) var tabBarMinimizeBehavior: TabBarMinimizeBehavior = .onScrollDown
    private var tabBarRestoreTask: Task<Void, Never>?
    /// Fenêtre de lecture plein écran ouverte depuis le mini-lecteur (`nil` : fermée).
    var nowPlayingPresentation: NowPlayingPresentation?
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
    /// Demande de positionnement sur « Collection & Rangement » pas encore traitée (voir
    /// `openSettingsAtOrganizationSection` et `consumePendingOrganizationScroll`).
    private(set) var hasPendingOrganizationScroll = false
    var scrollToPurchasePriceSectionTrigger = 0
    /// Champ à mettre en évidence à l'arrivée dans Réglages (voir `openSettingsAtPurchaseField`).
    private(set) var pendingSettingsFieldHighlight: SettingsFieldHighlight?

    /// Revient à la racine de Collection et vide les piles de navigation des autres onglets.
    func showCollectionRoot() {
        selectedTab = .collection
        resetNavigationPaths()
    }

    /// Vide la pile de navigation de chaque onglet, sans changer d'onglet. Appelé à la déconnexion
    /// (voir `DiscogsAuthManager.logout`) : une fiche restée ouverte (celle d'un disque de la démo,
    /// par exemple) réapparaissait après la connexion suivante, et la pile de Collection, recréée
    /// à ce moment-là avec cette fiche déjà empilée, perdait sa police serif, son grand titre qui se
    /// réduit au défilement et sa barre opaque.
    func resetNavigationPaths() {
        collectionPath = NavigationPath()
        wantlistPath = NavigationPath()
        statsPath = NavigationPath()
        searchPath = NavigationPath()
        settingsPath = NavigationPath()
    }

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

    /// Rend tout de suite sa taille normale à la barre d'onglets réduite. iOS ne la rétablit que
    /// sur un défilement vers le haut, détecté avec retard quand c'est un simple tirage en
    /// rebond au sommet d'une liste courte : on bascule donc un instant sur `.never` (qui la
    /// rétablit), puis on remet le comportement normal.
    func expandTabBar() {
        guard tabBarRestoreTask == nil else { return }
        tabBarMinimizeBehavior = .never
        tabBarRestoreTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            tabBarMinimizeBehavior = .onScrollDown
            tabBarRestoreTask = nil
        }
    }

    func presentNowPlaying(_ source: NowPlayingPresentation.Source) {
        guard nowPlayingPresentation == nil else { return }
        nowPlayingPresentation = NowPlayingPresentation(source: source)
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

    /// Ouvre « Mes grades » dans Réglages (depuis la célébration d'un grade) : pile ramenée à la
    /// racine d'abord, pour ne pas empiler la page sur un sous-écran resté ouvert.
    func openGrades() {
        settingsPath = NavigationPath()
        settingsPath.append(SettingsDestination.grades)
        selectedTab = .settings
    }

    /// Ouvre la page « Rangement » de Réglages, règle de rangement mise en évidence (depuis « Modifier »
    /// dans la méthode de classement du guide de rangement).
    func openSettingsAtOrganizationSection() {
        // Pile ramenée à la racine d'abord, pour ne pas empiler la page sur un sous-écran resté ouvert.
        settingsPath = NavigationPath()
        settingsPath.append(SettingsDestination.shelving)
        selectedTab = .settings
        hasPendingOrganizationScroll = true
        scrollToOrganizationSectionTrigger += 1
    }

    /// Lit puis efface la demande : traitée une seule fois, que Réglages l'ait vue arriver (changement
    /// du déclencheur) ou la découvre à son apparition (toute première visite de l'onglet).
    func consumePendingOrganizationScroll() -> Bool {
        defer { hasPendingOrganizationScroll = false }
        return hasPendingOrganizationScroll
    }

    /// Ouvre la page « Suivi de plus-value » de Réglages, avec la ligne du champ demandé mise en
    /// évidence (depuis la pastille « Utilisé pour la plus-value » de « Mon exemplaire »).
    func openSettingsAtPurchaseField(_ field: SettingsFieldHighlight) {
        settingsPath = NavigationPath()
        settingsPath.append(SettingsDestination.gainTracking)
        selectedTab = .settings
        pendingSettingsFieldHighlight = field
        scrollToPurchasePriceSectionTrigger += 1
    }

    /// Lit puis efface le champ à mettre en évidence : une demande n'est traitée qu'une fois, que
    /// Réglages l'ait vue arriver (changement du déclencheur) ou la découvre à son apparition.
    func consumePendingSettingsFieldHighlight() -> SettingsFieldHighlight? {
        defer { pendingSettingsFieldHighlight = nil }
        return pendingSettingsFieldHighlight
    }

    /// Navigation profonde vers une release précise (lien `spinlog://release/{id}` ouvert depuis
    /// la Live Activity ou le widget "Album du jour"). Poussée sur l'onglet courant (Collection
    /// depuis Réglages) sans vider sa pile : auparavant, l'onglet Recherche était toujours vidé,
    /// ce qui faisait perdre la recherche ou la fiche en cours de consultation.
    func openRelease(id: Int, coverURL: String? = nil) {
        returnToRelease(releaseId: id, coverURL: coverURL)
    }
}
