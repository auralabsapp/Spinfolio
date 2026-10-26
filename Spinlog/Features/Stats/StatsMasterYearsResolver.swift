import Foundation
import Observation
import SwiftUI

/// Années originales de la collection pour l'onglet Stats : répartition calculée tout de suite
/// avec les années de masters déjà connues, puis complétée au fil de la résolution de fond des
/// masters manquants (`MasterResolutionService`). Extrait de `StatsViewModel`, qui le possède et
/// en expose l'état.
@Observable
@MainActor
final class StatsMasterYearsResolver {
    /// Répartition par année originale, années décroissantes.
    private(set) var distribution: [(year: Int, count: Int)] = []
    /// Part des disques dont l'année originale est connue (de 0 à 1).
    private(set) var progress: Double = 1.0
    private(set) var isResolving = false
    private(set) var missingCount = 0
    /// Années connues [masterId: année originale].
    private(set) var masterYears: [Int: Int] = [:]

    @ObservationIgnored private var items: [CollectionItem] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Relit les années déjà résolues (cache local pérenne), avant tout calcul qui en dépend.
    func reloadKnownYears() {
        masterYears = LocalDataStore.shared.getAllMasterYears()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Recalcule la répartition pour cette collection, puis lance la résolution des masters
    /// dont l'année manque encore.
    func update(for items: [CollectionItem]) {
        guard !items.isEmpty else { return }
        self.items = items
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            distribution = StatsViewModel.originalYears(of: items, masterYears: masterYears)
        }

        let missing = StatsViewModel.missingMasterIds(in: items, masterYears: masterYears)
        missingCount = missing.count
        guard !missing.isEmpty else {
            isResolving = false
            progress = 1.0
            return
        }

        isResolving = true
        progress = StatsViewModel.masterResolutionProgress(of: items, masterYears: masterYears)

        task?.cancel()
        let missingList = Array(missing)
        task = Task { [weak self] in
            await MasterResolutionService.shared.resolveMasters(missingMasterIds: missingList, subscriberKey: "stats") { [weak self] resolved, total, masterId, year in
                self?.record(year: year, forMasterId: masterId, resolved: resolved, total: total)
            }
        }
    }

    private func record(year: Int, forMasterId masterId: Int, resolved: Int, total: Int) {
        masterYears[masterId] = year
        missingCount = max(0, total - resolved)
        progress = StatsViewModel.masterResolutionProgress(of: items, masterYears: masterYears)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            distribution = StatsViewModel.originalYears(of: items, masterYears: masterYears)
        }
        if resolved >= total {
            isResolving = false
            progress = 1.0
        }
    }
}
