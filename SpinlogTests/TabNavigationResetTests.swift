import Testing
import SwiftUI
@testable import Spinlog

/// Piles de navigation des onglets à la déconnexion : aucune fiche ne doit survivre au compte
/// (ou à la démo) qui l'avait ouverte.
@MainActor
struct TabNavigationResetTests {
    @Test func resetEmptiesEveryTabPathAndKeepsTheSelectedTab() {
        let coordinator = TabNavigationCoordinator()
        coordinator.selectedTab = .settings
        coordinator.collectionPath.append(SearchDestination.release(42))
        coordinator.wantlistPath.append(SearchDestination.master(7))
        coordinator.statsPath.append(SearchDestination.artist(3))
        coordinator.searchPath.append(SearchDestination.label(9))
        coordinator.settingsPath.append(SearchDestination.release(1))

        coordinator.resetNavigationPaths()

        #expect(coordinator.collectionPath.isEmpty)
        #expect(coordinator.wantlistPath.isEmpty)
        #expect(coordinator.statsPath.isEmpty)
        #expect(coordinator.searchPath.isEmpty)
        #expect(coordinator.settingsPath.isEmpty)
        #expect(coordinator.selectedTab == .settings)
    }

    @Test func showCollectionRootAlsoSelectsCollection() {
        let coordinator = TabNavigationCoordinator()
        coordinator.selectedTab = .stats
        coordinator.collectionPath.append(SearchDestination.release(42))

        coordinator.showCollectionRoot()

        #expect(coordinator.collectionPath.isEmpty)
        #expect(coordinator.selectedTab == .collection)
    }
}
