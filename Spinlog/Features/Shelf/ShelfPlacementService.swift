import Foundation

/// Périmètre de la collection pris en compte pour le calcul de rangement physique
enum ShelfScope: Sendable, Equatable {
    /// Rangement comparé à l'ensemble de tous les dossiers de la collection
    case allFolders
    /// Rangement restreint au dossier spécifique auquel appartient le disque
    case specificFolder(name: String, id: Int)
    /// Option de restriction activée mais disque non trouvé dans un sous-dossier particulier
    case unassignedFolder

    var isFolderRestricted: Bool {
        if case .specificFolder = self { return true }
        return false
    }

    var folderName: String? {
        if case .specificFolder(let name, _) = self { return name }
        return nil
    }

    var iconName: String {
        isFolderRestricted ? "folder.fill" : "square.stack.3d.up.fill"
    }

    var badgeText: String {
        switch self {
        case .allFolders:
            return "Tous les dossiers"
        case .specificFolder(let name, _):
            return "Dossier : \(name)"
        case .unassignedFolder:
            return "Tous les dossiers"
        }
    }

    var scopeDescription: String {
        switch self {
        case .allFolders:
            return "Tous les dossiers de la collection"
        case .specificFolder(let name, _):
            return "Limité au dossier « \(name) »"
        case .unassignedFolder:
            return "Tous les dossiers (disque hors dossier)"
        }
    }
}

/// Modèle représentant les voisins d'un vinyle dans le meuble physique
struct ShelfNeighbors: Sendable {
    /// Le disque à ranger
    let target: Release
    /// Le disque immédiatement avant (à gauche dans l'étagère)
    let previous: Release?
    /// Le disque immédiatement après (à droite dans l'étagère)
    let next: Release?
    /// La stratégie de rangement utilisée pour calculer ce voisinage
    let strategy: ShelfSortStrategy
    /// Espace de rangement physique (vinyles 12", CD, cassettes...) auquel appartient `target` :
    /// les voisins ne sont jamais cherchés en dehors de cet espace, voir `findNeighbors`.
    let category: ShelfMediaCategory
    /// Nombre total de disques pris en compte dans le meuble (dans cet espace de rangement)
    let totalCount: Int
    /// Position 1-indexée du disque dans le meuble physique
    let positionIndex: Int
    /// Périmètre de collection pris en compte (tous les dossiers ou dossier spécifique)
    let scope: ShelfScope

    init(
        target: Release,
        previous: Release?,
        next: Release?,
        strategy: ShelfSortStrategy,
        category: ShelfMediaCategory,
        totalCount: Int,
        positionIndex: Int,
        scope: ShelfScope = .allFolders
    ) {
        self.target = target
        self.previous = previous
        self.next = next
        self.strategy = strategy
        self.category = category
        self.totalCount = totalCount
        self.positionIndex = positionIndex
        self.scope = scope
    }

    var isAtBeginning: Bool {
        previous == nil && next != nil
    }

    var isAtEnd: Bool {
        previous != nil && next == nil
    }

    var isSoleRecord: Bool {
        previous == nil && next == nil
    }

    /// Phrase explicative naturelle générée selon le contexte de placement
    @MainActor
    var explanationText: String {
        if isSoleRecord {
            switch scope {
            case .specificFolder(let name, _):
                return "C'est le seul « \(category.lowercasedDisplayName) » de votre dossier « \(name) ». Déposez-le où vous voulez !"
            case .allFolders, .unassignedFolder:
                return "C'est le premier « \(category.lowercasedDisplayName) » de votre collection. Déposez-le où vous voulez dans cet espace de rangement !"
            }
        }
        if let previous, let next {
            return "À ranger entre « \(previous.artistNames) – \(previous.title)\(yearSuffix(for: previous)) » et « \(next.artistNames) – \(next.title)\(yearSuffix(for: next)) »."
        }
        if let next, previous == nil {
            return "À ranger tout au début de votre meuble, juste avant « \(next.artistNames) – \(next.title)\(yearSuffix(for: next)) »."
        }
        if let previous, next == nil {
            return "À ranger tout à la fin de votre meuble, juste après « \(previous.artistNames) – \(previous.title)\(yearSuffix(for: previous)) »."
        }
        return "Emplacement déterminé selon la règle \(strategy.title.lowercased())."
    }

    @MainActor
    private func yearSuffix(for release: Release) -> String {
        guard let year = release.effectiveShelfYear(useOriginalYear: strategy.usesMasterYear), year > 0 else { return "" }
        return " (\(year))"
    }
}

extension Release {
    /// Année pour le classement physique : année originale du Master si connue et demandée,
    /// sinon année de pressage de la release.
    @MainActor
    func effectiveShelfYear(useOriginalYear: Bool = true, masterYears: [Int: Int]? = nil) -> Int? {
        guard useOriginalYear, let masterId, masterId > 0 else {
            return (year != nil && year! > 0) ? year : nil
        }
        if let masterYears {
            if let mYear = masterYears[masterId], mYear > 0 {
                return mYear
            }
        } else if let mYear = LocalDataStore.shared.getMasterYear(for: masterId), mYear > 0 {
            return mYear
        }
        return (year != nil && year! > 0) ? year : nil
    }
}

/// Service pur d'algorithme de tri physique et de recherche des disques voisins.
enum ShelfPlacementService {

    /// Compare deux releases selon la stratégie de rangement choisie.
    /// Renvoie `true` si `a` doit être rangé avant `b`.
    @MainActor
    static func compare(
        _ a: Release,
        _ b: Release,
        strategy: ShelfSortStrategy = .artistThenMasterYear,
        ignoreArticles: Bool = true,
        masterYears: [Int: Int]? = nil
    ) -> Bool {
        let yA = a.effectiveShelfYear(useOriginalYear: strategy.usesMasterYear, masterYears: masterYears)
        let yB = b.effectiveShelfYear(useOriginalYear: strategy.usesMasterYear, masterYears: masterYears)
        return compare(
            artistA: a.sortArtistNames,
            titleA: a.title,
            yearA: yA,
            idA: a.id,
            artistB: b.sortArtistNames,
            titleB: b.title,
            yearB: yB,
            idB: b.id,
            strategy: strategy,
            ignoreArticles: ignoreArticles,
            sortByLastName: ShelfPreferencesStore.shared.sortByLastName,
            customOverrides: ShelfPreferencesStore.shared.customArtistSortOverrides
        )
    }

    /// Compare deux éléments de bibliothèque selon la stratégie de rangement choisie.
    static func compare(
        artistA: String,
        titleA: String,
        yearA: Int?,
        idA: Int,
        artistB: String,
        titleB: String,
        yearB: Int?,
        idB: Int,
        strategy: ShelfSortStrategy = .artistThenMasterYear,
        ignoreArticles: Bool = true,
        sortByLastName: Bool? = nil,
        customOverrides: [String: String]? = nil
    ) -> Bool {
        let activeSortByLastName = sortByLastName ?? false
        let normArtistA = artistA.shelfArtistSortKey(
            ignoreArticles: ignoreArticles,
            sortByLastName: activeSortByLastName,
            overrides: customOverrides
        )
        let normArtistB = artistB.shelfArtistSortKey(
            ignoreArticles: ignoreArticles,
            sortByLastName: activeSortByLastName,
            overrides: customOverrides
        )
        let normTitleA = titleA.normalizedForArtistSorting(ignoreArticles: ignoreArticles)
        let normTitleB = titleB.normalizedForArtistSorting(ignoreArticles: ignoreArticles)

        let yA = yearA ?? Int.max
        let yB = yearB ?? Int.max

        switch strategy {
        case .artistThenMasterYear, .artistThenReleaseYear:
            let artistCmp = normArtistA.localizedCaseInsensitiveCompare(normArtistB)
            if artistCmp != .orderedSame {
                return artistCmp == .orderedAscending
            }
            if yA != yB {
                return yA < yB
            }
            let titleCmp = normTitleA.localizedCaseInsensitiveCompare(normTitleB)
            if titleCmp != .orderedSame {
                return titleCmp == .orderedAscending
            }
            return idA < idB

        case .artistThenTitle:
            let artistCmp = normArtistA.localizedCaseInsensitiveCompare(normArtistB)
            if artistCmp != .orderedSame {
                return artistCmp == .orderedAscending
            }
            let titleCmp = normTitleA.localizedCaseInsensitiveCompare(normTitleB)
            if titleCmp != .orderedSame {
                return titleCmp == .orderedAscending
            }
            if yA != yB {
                return yA < yB
            }
            return idA < idB

        case .chronologicalOnly:
            if yA != yB {
                return yA < yB
            }
            let artistCmp = normArtistA.localizedCaseInsensitiveCompare(normArtistB)
            if artistCmp != .orderedSame {
                return artistCmp == .orderedAscending
            }
            let titleCmp = normTitleA.localizedCaseInsensitiveCompare(normTitleB)
            if titleCmp != .orderedSame {
                return titleCmp == .orderedAscending
            }
            return idA < idB
        }
    }

    /// Recherche les voisins immédiats pour le disque cible dans une liste de releases données.
    @MainActor
    static func findNeighbors(
        for targetRelease: Release,
        in collection: [Release],
        strategy: ShelfSortStrategy = .artistThenMasterYear,
        ignoreArticles: Bool = true,
        scope: ShelfScope = .allFolders
    ) -> ShelfNeighbors {
        let masterYears = strategy.usesMasterYear ? LocalDataStore.shared.getAllMasterYears() : nil
        let category = targetRelease.shelfMediaCategory

        // Déduplication par ID, exclusion du disque cible (s'il s'y trouve déjà) et surtout
        // filtrage au même espace de rangement physique que la cible : un CD ne doit jamais
        // apparaître comme voisin d'un vinyle, ni un 7" au milieu des 12".
        var seenIds = Set<Int>()
        var uniqueCollection: [Release] = []
        for item in collection {
            if item.id != targetRelease.id && !seenIds.contains(item.id) && item.shelfMediaCategory == category {
                seenIds.insert(item.id)
                uniqueCollection.append(item)
            }
        }

        // Tri de la collection de référence selon la stratégie active
        let sortedCollection = uniqueCollection.sorted { a, b in
            compare(
                a,
                b,
                strategy: strategy,
                ignoreArticles: ignoreArticles,
                masterYears: masterYears
            )
        }

        let totalCount = sortedCollection.count + 1

        guard !sortedCollection.isEmpty else {
            return ShelfNeighbors(
                target: targetRelease,
                previous: nil,
                next: nil,
                strategy: strategy,
                category: category,
                totalCount: 1,
                positionIndex: 1,
                scope: scope
            )
        }

        // Trouver l'index où targetRelease s'insère
        var insertIndex = sortedCollection.count
        for (index, item) in sortedCollection.enumerated() {
            if compare(
                targetRelease,
                item,
                strategy: strategy,
                ignoreArticles: ignoreArticles,
                masterYears: masterYears
            ) {
                insertIndex = index
                break
            }
        }

        if insertIndex == 0 {
            // Tout au début du meuble
            return ShelfNeighbors(
                target: targetRelease,
                previous: nil,
                next: sortedCollection.first,
                strategy: strategy,
                category: category,
                totalCount: totalCount,
                positionIndex: 1,
                scope: scope
            )
        } else if insertIndex < sortedCollection.count {
            // Entre deux disques
            let prev = sortedCollection[insertIndex - 1]
            let nxt = sortedCollection[insertIndex]
            return ShelfNeighbors(
                target: targetRelease,
                previous: prev,
                next: nxt,
                strategy: strategy,
                category: category,
                totalCount: totalCount,
                positionIndex: insertIndex + 1,
                scope: scope
            )
        } else {
            // Tout à la fin du meuble
            return ShelfNeighbors(
                target: targetRelease,
                previous: sortedCollection.last,
                next: nil,
                strategy: strategy,
                category: category,
                totalCount: totalCount,
                positionIndex: totalCount,
                scope: scope
            )
        }
    }

    /// Recherche les voisins immédiats dans une liste de `CollectionItem`.
    @MainActor
    static func findNeighbors(
        for targetRelease: Release,
        in collectionItems: [CollectionItem],
        strategy: ShelfSortStrategy = .artistThenMasterYear,
        ignoreArticles: Bool = true,
        scope: ShelfScope = .allFolders
    ) -> ShelfNeighbors {
        let releases = collectionItems.map { Release(from: $0) }
        return findNeighbors(
            for: targetRelease,
            in: releases,
            strategy: strategy,
            ignoreArticles: ignoreArticles,
            scope: scope
        )
    }

    /// Recherche les voisins directement depuis le cache local de l'utilisateur connecté.
    @MainActor
    static func findNeighborsInLocalStore(
        for targetRelease: Release,
        username: String?,
        strategy: ShelfSortStrategy? = nil,
        ignoreArticles: Bool? = nil,
        restrictToSameFolder: Bool? = nil
    ) -> ShelfNeighbors {
        let activeStrategy = strategy ?? ShelfPreferencesStore.shared.sortStrategy
        let activeIgnoreArticles = ignoreArticles ?? ShelfPreferencesStore.shared.ignoreArticles
        let activeRestrictToSameFolder = restrictToSameFolder ?? ShelfPreferencesStore.shared.restrictToSameFolder
        guard let username, !username.isEmpty else {
            return ShelfNeighbors(
                target: targetRelease,
                previous: nil,
                next: nil,
                strategy: activeStrategy,
                category: targetRelease.shelfMediaCategory,
                totalCount: 1,
                positionIndex: 1,
                scope: .allFolders
            )
        }
        var items = LocalDataStore.shared.getAllCollectionItems(username: username)

        var determinedScope: ShelfScope = .allFolders

        // Restreint la recherche de voisins au dossier Discogs contenant le disque ciblé, si
        // l'utilisateur l'a activé dans les réglages et que ce dossier est identifiable.
        if activeRestrictToSameFolder {
            // Cherche le folderId : sur targetRelease ou parmi les exemplaires stockés localement
            var targetFolderId = targetRelease.folderId
            if targetFolderId == nil || targetFolderId == DiscogsConstants.allFolderId {
                if let matchingItem = items.first(where: { $0.basicInformation.id == targetRelease.id && $0.folderId != DiscogsConstants.allFolderId }) {
                    targetFolderId = matchingItem.folderId
                }
            }

            if let folderId = targetFolderId, folderId != DiscogsConstants.allFolderId {
                let folderFiltered = items.filter { $0.folderId == folderId }
                items = folderFiltered
                let folders = LocalDataStore.shared.getFolders(username: username)
                let name = folders.first(where: { $0.id == folderId })?.name ?? "Dossier #\(folderId)"
                determinedScope = .specificFolder(name: name, id: folderId)
            } else {
                determinedScope = .unassignedFolder
            }
        }

        return findNeighbors(
            for: targetRelease,
            in: items,
            strategy: activeStrategy,
            ignoreArticles: activeIgnoreArticles,
            scope: determinedScope
        )
    }
}
