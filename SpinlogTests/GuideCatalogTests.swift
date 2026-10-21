import Foundation
import SwiftUI
import Testing
@testable import Spinlog

/// Le guide est un tableau de données : ces tests protègent sa cohérence (identifiants uniques,
/// fiches complètes) pour qu'ajouter une section n'abîme pas les précédentes.
@MainActor
struct GuideCatalogTests {
    @Test func entryIdsAreUnique() {
        let ids = GuideCatalog.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everySectionHasEntries() {
        for section in GuideSection.allCases {
            #expect(!section.entries.isEmpty, "La section \(section) n'a aucune fiche")
        }
    }

    @Test func everyEntryIsComplete() {
        for entry in GuideCatalog.entries {
            #expect(!String(localized: entry.title).isEmpty, "Titre vide : \(entry.id)")
            #expect(!String(localized: entry.summary).isEmpty, "Accroche vide : \(entry.id)")
            #expect(!entry.steps.isEmpty, "Aucune étape : \(entry.id)")
            // Une fiche lisible d'un coup d'œil : 2 étapes au plus sous « Détails ».
            #expect(entry.steps.count <= 2, "Trop d'étapes : \(entry.id)")
        }
    }

    @Test func stepsAreNumberedFromOne() {
        let entry = GuideEntry(
            id: "test",
            section: .gettingStarted,
            visual: .signIn,
            title: "Titre",
            summary: "Accroche",
            steps: ["A", "B", "C"]
        )
        #expect(entry.numberedSteps.map(\.number) == [1, 2, 3])
    }

    @Test func openingATabSelectsIt() {
        let coordinator = TabNavigationCoordinator()
        GuideDestination.tab(.search).open(using: coordinator)
        #expect(coordinator.selectedTab == .search)
    }

    @Test func openingSettingsReturnsToItsRoot() {
        let coordinator = TabNavigationCoordinator()
        coordinator.selectedTab = .settings
        coordinator.settingsPath.append(SettingsDestination.guide)
        #expect(!coordinator.settingsPath.isEmpty)

        GuideDestination.tab(.settings).open(using: coordinator)

        #expect(coordinator.settingsPath.isEmpty)
        #expect(coordinator.selectedTab == .settings)
    }

    @Test func openingAnotherTabKeepsTheSettingsStack() {
        let coordinator = TabNavigationCoordinator()
        coordinator.settingsPath.append(SettingsDestination.guide)

        GuideDestination.tab(.search).open(using: coordinator)

        #expect(!coordinator.settingsPath.isEmpty)
    }
}
