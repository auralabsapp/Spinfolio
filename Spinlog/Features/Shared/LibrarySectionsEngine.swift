import Foundation

/// Moteur de tri + regroupement en sections partagé par `CollectionViewModel` et
/// `WantlistViewModel` : les deux écrans trient/groupent leurs éléments (`CollectionItem`,
/// `WantlistItem`) exactement de la même façon via `SortableLibraryItem`. Le calcul
/// (`localizedStandardCompare` répété sur chaque paire comparée, sans mise en cache) est coûteux
/// et synchrone sur le thread principal : il est donc déporté sur une tâche détachée à partir d'un
/// instantané des données, puis appliqué d'un coup sur l'acteur principal — sauf quand `recompute`
/// est appelé en mode `synchronous` (tri `.shelf` ou filtre par tag actif, qui touchent
/// respectivement `ShelfPreferencesStore` et `TagStore`, isolés sur l'acteur principal).
///
/// Ne porte volontairement que ce calcul pur : `sections`/`isComputingSections` restent des
/// propriétés `@Observable` propres à chaque ViewModel (un type délégué non observable ne
/// déclencherait aucune invalidation SwiftUI), livrées via les closures `willStartAsync`/`apply`.
@MainActor
final class LibrarySectionsEngine<Item: SortableLibraryItem & Sendable> {
    /// Incrémenté à chaque appel de `recompute` : permet au calcul détaché le plus récent de
    /// détecter qu'un appel plus récent l'a entre-temps rendu obsolète, et de ne pas livrer un
    /// résultat périmé.
    private var generation = 0

    func recompute(
        items: [Item], sortOption: CollectionSortOption, ascending: Bool,
        tags: Set<String>, format: String?, searchText: String,
        synchronous: Bool,
        willStartAsync: () -> Void,
        apply: @escaping ([(key: String, items: [Item])]) -> Void
    ) {
        generation += 1
        let currentGeneration = generation

        // Capturé une seule fois ici, sur l'acteur principal, plutôt que relu à chaque comparaison
        // pendant le tri (voir `ShelfSortContext`) — permet au tri `.shelf` de ne plus jamais avoir
        // besoin d'être `synchronous` pour cette seule raison.
        let shelfContext: ShelfSortContext? = sortOption == .shelf ? ShelfPreferencesStore.shared.shelfSortContext : nil

        guard !synchronous else {
            apply(Self.computeSections(
                items: items, sortOption: sortOption, ascending: ascending,
                tags: tags, format: format, searchText: searchText, shelfContext: shelfContext
            ))
            return
        }

        willStartAsync()
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.computeSections(
                items: items, sortOption: sortOption, ascending: ascending,
                tags: tags, format: format, searchText: searchText, shelfContext: shelfContext
            )
            guard let self else { return }
            await self.deliverIfCurrent(result, generation: currentGeneration, apply: apply)
        }
    }

    private func deliverIfCurrent(
        _ result: [(key: String, items: [Item])],
        generation: Int,
        apply: ([(key: String, items: [Item])]) -> Void
    ) {
        guard generation == self.generation else { return }
        apply(result)
    }

    /// `nonisolated` : appelée depuis la tâche détachée de `recompute`.
    private nonisolated static func computeSections(
        items: [Item], sortOption: CollectionSortOption, ascending: Bool,
        tags: Set<String>, format: String?, searchText: String,
        shelfContext: ShelfSortContext?
    ) -> [(key: String, items: [Item])] {
        let filtered = items.filter { $0.matchesLibraryFilters(tags: tags, format: format, searchText: searchText) }
        let sorted = filtered.sorted { $0.isOrderedBefore($1, for: sortOption, ascending: ascending, shelfContext: shelfContext) }
        var order: [String] = []
        var groups: [String: [Item]] = [:]
        for item in sorted {
            let key = item.sectionKey(for: sortOption, shelfContext: shelfContext)
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(item)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}
