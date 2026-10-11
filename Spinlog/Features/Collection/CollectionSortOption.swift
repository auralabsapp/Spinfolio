import Foundation

/// Options de tri de la collection. Quand l'API Discogs le permet, le tri se fait côté serveur
/// via `sort`/`sort_order` de `GET /collection/folders/{id}/releases` (valeurs acceptées :
/// `label, artist, title, catno, format, rating, added, year`). Discogs n'a pas de tri "genre" :
/// pour cette option, on garde l'ordre par défaut du serveur (`added`) et on ne fait que
/// regrouper l'affichage par genre, sur les éléments déjà chargés.
///
/// Réutilisé tel quel par l'onglet Wantlist (voir `SortableLibraryItem`) : les deux écrans
/// ont la même construction (tri, filtres, sections, barre d'index).
enum CollectionSortOption: String, CaseIterable, Identifiable, Codable {
    case artist = "Artiste"
    case title = "Album"
    case added = "Date d'ajout"
    case year = "Année"
    case genre = "Genre"
    case format = "Support"
    case label = "Label"
    case rating = "Note"
    case catalogNumber = "Référence"
    case shelf = "Meuble"

    var id: String { rawValue }

    /// Libellé affiché. `rawValue` (en français) reste la valeur persistée dans les préférences
    /// et ne doit pas changer ; l'afficher directement empêchait toute traduction.
    var title: String {
        switch self {
        case .artist: return String(localized: "Artiste")
        case .title: return String(localized: "Album")
        case .added: return String(localized: "Date d'ajout")
        case .year: return String(localized: "Année")
        case .genre: return String(localized: "Genre")
        case .format: return String(localized: "Support")
        case .label: return String(localized: "Label")
        case .rating: return String(localized: "Note")
        case .catalogNumber: return String(localized: "Référence")
        case .shelf: return String(localized: "Meuble")
        }
    }

    var systemImage: String {
        switch self {
        case .artist: return "person"
        case .title: return "opticaldisc"
        case .added: return "calendar.badge.clock"
        case .year: return "calendar"
        case .genre: return "guitars"
        case .format: return "square.stack.3d.up"
        case .label: return "building.2"
        case .rating: return "star"
        case .catalogNumber: return "number"
        case .shelf: return "books.vertical.fill"
        }
    }

    nonisolated var defaultAscending: Bool {
        switch self {
        case .added, .rating:
            return false
        default:
            return true
        }
    }

    /// `nil` pour `.genre` : pas de valeur `sort` Discogs correspondante, on n'envoie rien
    /// (le serveur retombe sur son tri par défaut).
    var apiSortValue: String? {
        switch self {
        case .artist: return "artist"
        case .title: return "title"
        case .added: return "added"
        case .year: return "year"
        case .genre: return nil
        case .format: return "format"
        case .label: return "label"
        case .rating: return "rating"
        case .catalogNumber: return "catno"
        case .shelf: return "artist"
        }
    }

    /// Les disques ajoutés récemment (ou les mieux notés) sont plus pertinents en premier ;
    /// le reste s'affiche A→Z (ou année croissante).
    var apiSortOrder: String {
        (self == .added || self == .rating) ? "desc" : "asc"
    }

    func apiSortOrder(ascending: Bool) -> String {
        ascending ? "asc" : "desc"
    }
}

/// Ce que le tri/regroupement partagé entre Collection et Wantlist a besoin de lire sur un
/// élément — `CollectionItem` et `WantlistItem` s'y conforment, ce qui permet à l'onglet
/// Wantlist de réutiliser exactement la même logique de tri/sections que la Collection.
protocol SortableLibraryItem: Identifiable {
    nonisolated var id: Int { get }
    nonisolated var basicInformation: BasicInformation { get }
    nonisolated var rating: Int { get }
    nonisolated var dateAddedDate: Date? { get }
    nonisolated var libraryItemTags: [String] { get }
}

extension CollectionItem: SortableLibraryItem {
    /// `nonisolated` + `assumeIsolated` : accédé depuis la tâche détachée de
    /// `CollectionViewModel.computeSections()`, mais seulement quand aucun filtre de tag n'est
    /// actif (ce code est alors mort au runtime dans ce contexte) — voir le garde-fou dans
    /// `recomputeSections()`. `TagStore` reste un singleton isolé sur l'acteur principal pour
    /// tous ses autres appelants (édition de tags...).
    nonisolated var libraryItemTags: [String] {
        MainActor.assumeIsolated {
            TagStore.shared.tags(for: instanceId, releaseId: releaseId)
        }
    }
}

extension SortableLibraryItem {
    /// Clé de regroupement : une section par valeur distincte (pas juste par lettre), pour
    /// que la ligne 2 de l'en-tête puisse afficher la valeur complète.
    /// `nonisolated` : voir le commentaire sur `libraryItemTags` — le cas `.shelf` qui touche
    /// `ShelfPreferencesStore` (isolé sur l'acteur principal) n'est jamais atteint depuis la
    /// tâche détachée de `CollectionViewModel.computeSections()`, qui exclut ce tri.
    nonisolated func sectionKey(for sort: CollectionSortOption) -> String {
        switch sort {
        case .artist:
            let name = basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "?" : name
        case .shelf:
            let prefs = MainActor.assumeIsolated {
                (
                    ShelfPreferencesStore.shared.ignoreArticles,
                    ShelfPreferencesStore.shared.sortByLastName,
                    ShelfPreferencesStore.shared.customArtistSortOverrides
                )
            }
            let artist = basicInformation.artistNames.shelfArtistSortKey(
                ignoreArticles: prefs.0,
                sortByLastName: prefs.1,
                overrides: prefs.2
            )
            let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let firstChar = trimmed.first else { return "#" }
            let s = String(firstChar).uppercased()
            guard let scalar = s.unicodeScalars.first, CharacterSet.letters.contains(scalar) else { return "#" }
            return s.folding(options: .diacriticInsensitive, locale: .current)
        case .title:
            let title = basicInformation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "?" : title
        case .added:
            guard let date = dateAddedDate else { return "?" }
            return date.formatted(.dateTime.month(.wide).year())
        case .year:
            guard let year = basicInformation.year, year > 0 else { return "?" }
            return String(year)
        case .genre:
            let genre = basicInformation.genres?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return genre.isEmpty ? String(localized: "Genre inconnu") : genre
        case .format:
            let format = basicInformation.formats?.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return format.isEmpty ? String(localized: "Autre") : format
        case .label:
            let label = basicInformation.labels?.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return label.isEmpty ? String(localized: "Label inconnu") : label
        case .rating:
            return rating > 0 ? String(localized: "\(rating) étoiles") : String(localized: "Sans note")
        case .catalogNumber:
            let catno = basicInformation.labels?.first?.catno?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return catno.isEmpty ? String(localized: "Sans référence") : catno
        }
    }

    /// Compare deux éléments selon le critère de tri choisi afin de garantir un classement
    /// parfait et déterministe tant en local qu'en ligne.
    nonisolated func isOrderedBefore(_ other: Self, for sort: CollectionSortOption) -> Bool {
        isOrderedBefore(other, for: sort, ascending: sort.defaultAscending)
    }

    /// `nonisolated` : voir le commentaire sur `sectionKey` — même garantie pour `.shelf`.
    nonisolated func isOrderedBefore(_ other: Self, for sort: CollectionSortOption, ascending: Bool) -> Bool {
        switch sort {
        case .shelf:
            if ascending {
                return compareShelf(to: other)
            } else {
                return other.compareShelf(to: self)
            }

        case .artist:
            let a1 = basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let a2 = other.basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let cmp = a1.localizedStandardCompare(a2)
            if cmp != .orderedSame {
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            let t1 = basicInformation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let t2 = other.basicInformation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let tCmp = t1.localizedStandardCompare(t2)
            if tCmp != .orderedSame {
                return tCmp == .orderedAscending
            }
            return (basicInformation.year ?? 0) < (other.basicInformation.year ?? 0)

        case .title:
            let t1 = basicInformation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let t2 = other.basicInformation.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cmp = t1.localizedStandardCompare(t2)
            if cmp != .orderedSame {
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            let a1 = basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let a2 = other.basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let aCmp = a1.localizedStandardCompare(a2)
            if aCmp != .orderedSame {
                return aCmp == .orderedAscending
            }
            return (basicInformation.year ?? 0) < (other.basicInformation.year ?? 0)

        case .added:
            let d1 = dateAddedDate ?? .distantPast
            let d2 = other.dateAddedDate ?? .distantPast
            if d1 != d2 {
                return ascending ? (d1 < d2) : (d1 > d2)
            }
            return basicInformation.title.localizedStandardCompare(other.basicInformation.title) == .orderedAscending

        case .year:
            let y1 = basicInformation.year ?? 0
            let y2 = other.basicInformation.year ?? 0
            if y1 != y2 {
                if y1 == 0 { return false }
                if y2 == 0 { return true }
                return ascending ? (y1 < y2) : (y1 > y2)
            }
            return basicInformation.title.localizedStandardCompare(other.basicInformation.title) == .orderedAscending

        case .genre:
            let g1 = basicInformation.genres?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let g2 = other.basicInformation.genres?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if g1.isEmpty && !g2.isEmpty { return false }
            if !g1.isEmpty && g2.isEmpty { return true }
            let cmp = g1.localizedStandardCompare(g2)
            if cmp != .orderedSame {
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            return basicInformation.title.localizedStandardCompare(other.basicInformation.title) == .orderedAscending

        case .format:
            let f1 = basicInformation.formats?.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let f2 = other.basicInformation.formats?.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if f1.isEmpty && !f2.isEmpty { return false }
            if !f1.isEmpty && f2.isEmpty { return true }
            let cmp = f1.localizedStandardCompare(f2)
            if cmp != .orderedSame {
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            return basicInformation.title.localizedStandardCompare(other.basicInformation.title) == .orderedAscending

        case .label:
            let l1 = basicInformation.labels?.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let l2 = other.basicInformation.labels?.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if l1.isEmpty && !l2.isEmpty { return false }
            if !l1.isEmpty && l2.isEmpty { return true }
            let cmp = l1.localizedStandardCompare(l2)
            if cmp != .orderedSame {
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            let a1 = basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let a2 = other.basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let aCmp = a1.localizedStandardCompare(a2)
            if aCmp != .orderedSame {
                return aCmp == .orderedAscending
            }
            return basicInformation.title.localizedStandardCompare(other.basicInformation.title) == .orderedAscending

        case .rating:
            if rating != other.rating {
                return ascending ? (rating < other.rating) : (rating > other.rating)
            }
            let a1 = basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let a2 = other.basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let aCmp = a1.localizedStandardCompare(a2)
            if aCmp != .orderedSame {
                return aCmp == .orderedAscending
            }
            return basicInformation.title.localizedStandardCompare(other.basicInformation.title) == .orderedAscending

        case .catalogNumber:
            let c1 = basicInformation.labels?.first?.catno?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let c2 = other.basicInformation.labels?.first?.catno?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if c1.isEmpty && !c2.isEmpty { return false }
            if !c1.isEmpty && c2.isEmpty { return true }
            let cmp = c1.localizedStandardCompare(c2)
            if cmp != .orderedSame {
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            let a1 = basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let a2 = other.basicInformation.artistNames.trimmingCharacters(in: .whitespacesAndNewlines)
            let aCmp = a1.localizedStandardCompare(a2)
            if aCmp != .orderedSame {
                return aCmp == .orderedAscending
            }
            return basicInformation.title.localizedStandardCompare(other.basicInformation.title) == .orderedAscending
        }
    }

    /// `nonisolated` : voir le commentaire sur `sectionKey` — même garantie pour `.shelf`.
    private nonisolated func compareShelf(to other: Self) -> Bool {
        let (strategy, ignoreArticles, sortByLastName, customOverrides, masterYears) = MainActor.assumeIsolated {
            let strategy = ShelfPreferencesStore.shared.sortStrategy
            return (
                strategy,
                ShelfPreferencesStore.shared.ignoreArticles,
                ShelfPreferencesStore.shared.sortByLastName,
                ShelfPreferencesStore.shared.customArtistSortOverrides,
                strategy.usesMasterYear ? LocalDataStore.shared.getAllMasterYears() : nil
            )
        }

        // Même résolution que `Release.effectiveShelfYear`, utilisée par le guide de rangement
        // physique : comparer directement `basicInformation.year` (l'année du PRESSAGE) donnait
        // un ordre différent du guide dès qu'une réédition portait une année distincte de la
        // sortie originale (ex. deux rééditions de 2009 d'albums sortis en 1979 et 1980 : triées
        // par titre faute de départager sur cette année identique, au lieu de respecter la
        // chronologie réelle des masters).
        func resolvedYear(_ info: BasicInformation) -> Int? {
            if strategy.usesMasterYear, let masterId = info.masterId, masterId > 0,
               let masterYear = masterYears?[masterId], masterYear > 0 {
                return masterYear
            }
            let year = info.year
            return (year != nil && year! > 0) ? year : nil
        }

        return ShelfPlacementService.compare(
            artistA: basicInformation.artistNames,
            titleA: basicInformation.title,
            yearA: resolvedYear(basicInformation),
            idA: id,
            artistB: other.basicInformation.artistNames,
            titleB: other.basicInformation.title,
            yearB: resolvedYear(other.basicInformation),
            idB: other.id,
            strategy: strategy,
            ignoreArticles: ignoreArticles,
            sortByLastName: sortByLastName,
            customOverrides: customOverrides
        )
    }

    /// Valeur affichée sur la 2e ligne de l'en-tête sticky. Identique à `sectionKey` sauf pour
    /// le tri par date, où l'année est déjà sur la 1re ligne (le jeton) et n'a pas besoin d'être répétée.
    func sectionDisplayTitle(for sort: CollectionSortOption) -> String {
        switch sort {
        case .added:
            guard let date = dateAddedDate else { return "?" }
            return date.formatted(.dateTime.month(.wide))
        case .shelf:
            return basicInformation.artistNames
        default:
            return sectionKey(for: sort)
        }
    }
}

extension SortableLibraryItem {
    /// Artistes nommés par l'en-tête de section (voir `sectionDisplayTitle`), pour en faire un
    /// lien vers leur fiche : seulement pour les tris dont l'en-tête affiche l'artiste.
    func sectionHeaderArtists(for sort: CollectionSortOption) -> [ReleaseArtist] {
        switch sort {
        case .artist, .shelf:
            return basicInformation.artists ?? []
        default:
            return []
        }
    }
}

/// Jeton (lettre ou année sur 2 chiffres) pour la 1re ligne de l'en-tête d'une section et pour
/// la barre de navigation rapide — partagé par Collection et Wantlist.
func libraryIndexToken<Item: SortableLibraryItem>(for section: (key: String, items: [Item]), sort: CollectionSortOption) -> String {
    switch sort {
    case .added:
        guard let date = section.items.first?.dateAddedDate else { return "?" }
        let year = Calendar.current.component(.year, from: date) % 100
        return String(format: "%02d", year)
    case .year:
        guard section.key != "?" else { return "?" }
        return String(section.key.suffix(2))
    case .rating:
        guard let rating = section.items.first?.rating, rating > 0 else { return "–" }
        return String(rating)
    case .shelf:
        let folded = section.key.folding(options: .diacriticInsensitive, locale: .current).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstChar = folded.first else { return "#" }
        if firstChar.isLetter {
            return String(firstChar).uppercased()
        }
        return "#"
    case .artist, .title, .format, .genre, .label, .catalogNumber:
        let folded = section.key.folding(options: .diacriticInsensitive, locale: .current).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstChar = folded.first else { return "?" }
        if firstChar.isNumber {
            return "#"
        }
        if firstChar.isLetter {
            return String(firstChar).uppercased()
        }
        return "#"
    }
}

extension SortableLibraryItem {
    /// `nonisolated` : voir le commentaire sur `libraryItemTags`.
    nonisolated func matchesLibraryFilters(tags: Set<String> = [], format: String?, searchText: String) -> Bool {
        if !tags.isEmpty {
            let itemTags = Set(libraryItemTags.map { $0.folding(options: .diacriticInsensitive, locale: .current).lowercased() })
            let normalizedSelectedTags = Set(tags.map { $0.folding(options: .diacriticInsensitive, locale: .current).lowercased() })
            guard normalizedSelectedTags.isSubset(of: itemTags) else { return false }
        }

        if let format, !format.isEmpty {
            let matchesFormat = basicInformation.formats?.contains(where: {
                $0.name.localizedCaseInsensitiveCompare(format) == .orderedSame
                || ($0.descriptions ?? []).contains(where: { $0.localizedCaseInsensitiveCompare(format) == .orderedSame })
            }) ?? false
            guard matchesFormat else { return false }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return basicInformation.title.localizedCaseInsensitiveContains(trimmed)
            || basicInformation.artistNames.localizedCaseInsensitiveContains(trimmed)
    }
}

func tagFilterMenuTitle(_ selectedTags: Set<String>) -> String {
    if selectedTags.isEmpty {
        return String(localized: "Filtrer par tag")
    } else if selectedTags.count == 1 {
        return String(localized: "Tag : \(selectedTags.first!)")
    } else {
        return String(localized: "Tags (\(selectedTags.count))")
    }
}

extension Sequence where Element: SortableLibraryItem {
    var availableLibraryFormats: [String] {
        var set = Set<String>()
        for item in self {
            if let formats = item.basicInformation.formats {
                for f in formats {
                    let name = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { set.insert(name) }
                }
            }
        }
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
