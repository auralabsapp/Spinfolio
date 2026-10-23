import Foundation

/// Règles de mise à jour locale de la section « Derniers ajouts » (et de la collection analysée par
/// Stats) quand un exemplaire est ajouté, retiré ou déplacé ailleurs dans l'app : l'écran Stats ne
/// recharge Discogs qu'à sa création, il doit donc suivre ces changements sans attendre.
enum RecentAdditionsLogic {
    nonisolated static let limit = 10

    /// Retire l'exemplaire ciblé (`instanceId`), ou tous ceux de la release quand seul `releaseId` est connu.
    nonisolated static func removing(releaseId: Int, instanceId: Int?, from items: [CollectionItem]) -> [CollectionItem] {
        items.filter { item in
            if let instanceId { return item.instanceId != instanceId }
            return item.releaseId != releaseId
        }
    }

    /// Ajoute l'exemplaire en tête (le plus récent) sans doublon, dans la limite de `limit`.
    nonisolated static func inserting(_ item: CollectionItem, into items: [CollectionItem]) -> [CollectionItem] {
        guard !items.contains(where: { $0.instanceId == item.instanceId }) else { return items }
        return Array(([item] + items).prefix(limit))
    }

    /// Remplace un exemplaire par sa nouvelle version (déplacement de dossier : l'identifiant change).
    nonisolated static func replacing(oldInstanceId: Int, with newItem: CollectionItem, in items: [CollectionItem]) -> [CollectionItem] {
        items.map { $0.instanceId == oldInstanceId ? newItem : $0 }
    }

    /// Complète une liste raccourcie par un retrait avec les ajouts les plus récents de la collection
    /// connue (`dateAdded` est de l'ISO 8601, donc triable comme du texte).
    nonisolated static func refilled(_ recents: [CollectionItem], from all: [CollectionItem]) -> [CollectionItem] {
        guard recents.count < limit else { return recents }
        let known = Set(recents.map(\.instanceId))
        let extras = all
            .filter { !known.contains($0.instanceId) }
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(limit - recents.count)
        return recents + extras
    }
}
