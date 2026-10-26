import Foundation

/// Mises à jour optimistes de la liste et des compteurs de dossiers de la Collection, en
/// fonctions pures (`CollectionViewModel` applique le résultat, avec animation).
enum CollectionLocalChanges {
    /// Compteurs de dossiers ajustés : `deltas[folderId]` est ajouté au compte (jamais sous 0).
    static func adjustingCounts(of folders: [CollectionFolder], by deltas: [Int: Int]) -> [CollectionFolder] {
        folders.map { folder in
            guard let delta = deltas[folder.id], delta != 0 else { return folder }
            return CollectionFolder(id: folder.id, name: folder.name, count: max(0, folder.count + delta), resourceURL: folder.resourceURL)
        }
    }

    /// Exemplaire ajouté ailleurs dans l'app (fiche, scan) : affiché en tête si le dossier courant
    /// le contient (`items` vaut `nil` sinon, ou s'il y est déjà) ; compteurs de son dossier et de
    /// « Tous » augmentés.
    static func afterExternalAdd(
        of item: CollectionItem,
        items: [CollectionItem],
        folders: [CollectionFolder],
        selectedFolderId: Int?
    ) -> (items: [CollectionItem]?, folders: [CollectionFolder]) {
        let shows = selectedFolderId == nil || selectedFolderId == DiscogsConstants.allFolderId || selectedFolderId == item.folderId
        let newItems = shows && !items.contains(where: { $0.id == item.id }) ? [item] + items : nil
        return (newItems, adjustingCounts(of: folders, by: [item.folderId: 1, DiscogsConstants.allFolderId: 1]))
    }

    /// Exemplaire (ou, sans `instanceId`, tous les exemplaires du disque) retiré ailleurs dans
    /// l'app ; compteurs du dossier courant et de « Tous » diminués.
    static func afterExternalRemoval(
        releaseId: Int,
        instanceId: Int?,
        items: [CollectionItem],
        folders: [CollectionFolder],
        selectedFolderId: Int?
    ) -> (items: [CollectionItem], folders: [CollectionFolder]) {
        let remaining = items.filter { item in
            instanceId.map { item.instanceId != $0 } ?? (item.releaseId != releaseId)
        }
        var deltas = [DiscogsConstants.allFolderId: -1]
        if let selectedFolderId { deltas[selectedFolderId] = -1 }
        return (remaining, adjustingCounts(of: folders, by: deltas))
    }

    /// Liste après un déplacement : si la vue est filtrée sur le dossier de départ, l'exemplaire
    /// n'y appartient plus ; sinon (vue « Tous » ou déjà filtrée sur le nouveau dossier), il est
    /// juste mis à jour en place.
    static func itemsAfterMove(
        _ items: [CollectionItem],
        original: CollectionItem,
        moved: CollectionItem,
        selectedFolderId: Int?
    ) -> [CollectionItem] {
        var items = items
        guard let index = items.firstIndex(where: { $0.id == original.id }) else { return items }
        if selectedFolderId == original.folderId {
            items.remove(at: index)
        } else {
            items[index] = moved
        }
        return items
    }

    /// Inverse exact de `itemsAfterMove` (refus définitif de Discogs).
    static func itemsAfterRevertingMove(
        _ items: [CollectionItem],
        original: CollectionItem,
        moved: CollectionItem,
        selectedFolderId: Int?
    ) -> [CollectionItem] {
        var items = items
        if let index = items.firstIndex(where: { $0.id == original.id }) {
            // Vue filtrée sur le dossier de destination : l'exemplaire n'y a plus sa place.
            if selectedFolderId == moved.folderId {
                items.remove(at: index)
            } else {
                items[index] = original
            }
        } else if selectedFolderId == original.folderId {
            // Retiré de la vue filtrée sur le dossier de départ : on l'y remet.
            items.append(original)
        }
        return items
    }

    /// Fusion d'une page Discogs avec la liste affichée : `append` garde ce qui est déjà affiché
    /// (cache ou pages précédentes) et ajoute les nouveaux exemplaires, sans doublon. Les
    /// exemplaires fantômes (identifiant nul ou égal à celui de la release) sont écartés.
    static func merging(page: [CollectionItem], into items: [CollectionItem], append: Bool) -> [CollectionItem] {
        var seen = Set<Int>()
        return (append ? items + page : page).filter { item in
            item.instanceId > 0 && item.instanceId != item.releaseId && seen.insert(item.instanceId).inserted
        }
    }
}

extension CollectionItem {
    /// Le même exemplaire, rangé dans un autre dossier.
    func moved(toFolderId folderId: Int) -> CollectionItem {
        CollectionItem(
            releaseId: releaseId,
            folderId: folderId,
            rating: rating,
            dateAdded: dateAdded,
            basicInformation: basicInformation,
            instanceId: instanceId,
            notes: notes
        )
    }
}

extension [CollectionFieldValue] {
    /// Champs d'un exemplaire avec cette valeur pour ce champ (remplacée ou ajoutée).
    func settingValue(_ value: String, forFieldId fieldId: Int) -> [CollectionFieldValue] {
        var notes = self
        if let index = notes.firstIndex(where: { $0.fieldId == fieldId }) {
            notes[index] = CollectionFieldValue(fieldId: fieldId, value: value)
        } else {
            notes.append(CollectionFieldValue(fieldId: fieldId, value: value))
        }
        return notes
    }
}

extension CollectionItem {
    /// Exemplaire tout juste ajouté à la collection (note et champs vides, daté d'aujourd'hui).
    init(addedRelease release: Release, releaseId: Int, folderId: Int, instanceId: Int) {
        self.init(
            releaseId: releaseId,
            folderId: folderId,
            rating: 0,
            dateAdded: ISO8601DateFormatter().string(from: Date()),
            basicInformation: release.basicInformation,
            instanceId: instanceId,
            notes: []
        )
    }
}
