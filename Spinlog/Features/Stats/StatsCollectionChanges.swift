import Foundation

/// Report dans l'onglet Stats d'un ajout, d'un retrait ou d'un remplacement d'exemplaire fait
/// ailleurs dans l'app, sans recharger depuis Discogs. Fonctions pures : `StatsViewModel`
/// applique le résultat.
enum StatsCollectionChanges {
    /// Ce que l'onglet Stats garde de la collection et que ces changements modifient.
    struct State {
        var allItems: [CollectionItem]
        var recentAdditions: [CollectionItem]
        var totalCount: Int?
        /// Exemplaires retirés pendant la session : Discogs peut encore les renvoyer quelques
        /// instants dans la liste des derniers ajouts.
        var locallyRemovedInstanceIds: Set<Int>
        /// La collection complète a changé : les répartitions sont à recalculer.
        var allItemsChanged = false
    }

    static func adding(_ item: CollectionItem, to state: State) -> State {
        var state = state
        state.locallyRemovedInstanceIds.remove(item.instanceId)
        state.recentAdditions = RecentAdditionsLogic.inserting(item, into: state.recentAdditions)
        if let total = state.totalCount { state.totalCount = total + 1 }
        // Collection pas encore chargée : rien à compléter, elle arrivera entière.
        if !state.allItems.isEmpty, !state.allItems.contains(where: { $0.instanceId == item.instanceId }) {
            state.allItems = [item] + state.allItems
            state.allItemsChanged = true
        }
        return state
    }

    /// Sans `instanceId` (retrait de tous les exemplaires d'un disque), tous ceux qu'on connaît
    /// sont retenus comme retirés. Les derniers ajouts sont complétés depuis la collection.
    static func removing(releaseId: Int, instanceId: Int?, from state: State) -> State {
        var state = state
        let remainingAll = RecentAdditionsLogic.removing(releaseId: releaseId, instanceId: instanceId, from: state.allItems)
        let remainingRecent = RecentAdditionsLogic.removing(releaseId: releaseId, instanceId: instanceId, from: state.recentAdditions)
        let removedCount = max(state.allItems.count - remainingAll.count, state.recentAdditions.count - remainingRecent.count)

        if let instanceId {
            state.locallyRemovedInstanceIds.insert(instanceId)
        } else {
            state.locallyRemovedInstanceIds.formUnion(
                (state.allItems + state.recentAdditions).filter { $0.releaseId == releaseId }.map(\.instanceId)
            )
        }
        if remainingAll.count != state.allItems.count {
            state.allItems = remainingAll
            state.allItemsChanged = true
        }
        state.recentAdditions = RecentAdditionsLogic.refilled(remainingRecent, from: state.allItems)
        if removedCount > 0, let total = state.totalCount {
            state.totalCount = max(0, total - removedCount)
        }
        return state
    }

    /// Exemplaire temporaire remplacé par celui que Discogs a créé (ajout synchronisé).
    static func replacing(oldInstanceId: Int, with newItem: CollectionItem, in state: State) -> State {
        var state = state
        state.recentAdditions = RecentAdditionsLogic.replacing(oldInstanceId: oldInstanceId, with: newItem, in: state.recentAdditions)
        if state.allItems.contains(where: { $0.instanceId == oldInstanceId }) {
            state.allItems = RecentAdditionsLogic.replacing(oldInstanceId: oldInstanceId, with: newItem, in: state.allItems)
            state.allItemsChanged = true
        }
        return state
    }
}
