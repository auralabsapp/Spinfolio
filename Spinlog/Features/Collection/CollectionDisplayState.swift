import Foundation
import Observation
import SwiftUI

/// Ce que l'écran Collection affiche de la liste chargée : recherche, tri, filtres, sections et
/// valeurs dérivées (barre d'index, badges d'exemplaires, tags). Extrait de `CollectionViewModel`,
/// qui possède la liste (`items`) et ce sous-objet ; il réagit aux changements de tri par
/// `onSortChanged` (préférences du compte, rechargement depuis Discogs).
@Observable
@MainActor
final class CollectionDisplayState {
    /// Liste chargée, fournie par `CollectionViewModel`.
    @ObservationIgnored var currentItems: () -> [CollectionItem] = { [] }
    /// Appelé après un changement de critère (`criterionChanged`) ou de sens de tri par
    /// l'utilisateur.
    @ObservationIgnored var onSortChanged: (_ criterionChanged: Bool) -> Void = { _ in }

    init() {
        // Réglages du tri par artiste ou du meuble modifiés : l'ordre et les sections changent.
        addLibraryObserver(for: .shelfPreferencesChanged) { [weak self] in
            guard let self, sortOption == .shelf || sortOption == .artist else { return }
            recomputeSections()
            resolveMissingMastersIfNeeded()
        }
        addLibraryObserver(for: .masterYearResolved) { [weak self] in
            guard let self, sortsByMasterYear else { return }
            recomputeSections()
        }
        addLibraryObserver(for: .tagsChanged) { [weak self] in
            self?.recomputeSections()
            self?.recomputeTagsIndex()
        }
    }

    /// Tri « meuble » rangé selon l'année du master.
    private var sortsByMasterYear: Bool {
        sortOption == .shelf && ShelfPreferencesStore.shared.sortStrategy.usesMasterYear
    }

    /// Tri « meuble » sur l'année du master : années manquantes demandées à Discogs en fond (les
    /// sections suivent `.masterYearResolved`).
    func resolveMissingMastersIfNeeded() {
        guard sortsByMasterYear else { return }
        MasterResolutionService.resolveUnknownMasters(of: currentItems(), subscriberKey: "collection")
    }

    var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            recomputeSections()
        }
    }

    var sortOption: CollectionSortOption = .artist {
        didSet {
            guard oldValue != sortOption else { return }
            // Réinitialise le sens au défaut du nouveau critère sans repasser par le setter
            // public de `sortAscending` (qui déclencherait un second rechargement réseau en
            // plus de celui déjà lancé pour ce changement de critère).
            sortAscendingStorage = sortOption.defaultAscending
            recomputeSections()
            onSortChanged(true)
        }
    }

    private var sortAscendingStorage: Bool = CollectionSortOption.artist.defaultAscending

    /// Sens du tri courant (croissant/décroissant). Se réinitialise au défaut du critère choisi
    /// à chaque changement de `sortOption` ; peut ensuite être basculé indépendamment.
    var sortAscending: Bool {
        get { sortAscendingStorage }
        set {
            guard sortAscendingStorage != newValue else { return }
            sortAscendingStorage = newValue
            recomputeSections()
            onSortChanged(false)
        }
    }

    /// Sens mémorisé restauré au chargement, sans rechargement ni enregistrement.
    func restoreSortAscending(_ ascending: Bool) {
        sortAscendingStorage = ascending
    }

    /// Sémantique ET : un exemplaire n'est affiché que s'il porte tous les tags sélectionnés.
    /// Les filtres sont volatils (valables pour la session courante) : aucun filtre n'est appliqué au démarrage.
    var selectedTags: Set<String> = [] {
        didSet {
            guard oldValue != selectedTags else { return }
            recomputeSections()
        }
    }

    var selectedFormat: String? = nil {
        didSet {
            guard oldValue != selectedFormat else { return }
            recomputeSections()
        }
    }

    var hasActiveFilters: Bool {
        !selectedTags.isEmpty || !(selectedFormat ?? "").isEmpty
    }

    func clearFilters() {
        selectedTags = []
        selectedFormat = nil
    }

    func toggleTagFilter(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    /// Recherche et filtres vidés (changement de compte).
    func resetFilters() {
        searchText = ""
        selectedTags = []
        selectedFormat = nil
    }

    // MARK: - Sections

    /// Éléments filtrés par la recherche et les filtres actifs, regroupés par section dans un ordre
    /// rigoureusement déterministe (même en cache ou hors-ligne). Recalculé par
    /// `recomputeSections()` uniquement quand la liste, le tri ou les filtres changent réellement.
    private(set) var sections: [(key: String, items: [CollectionItem])] = [] {
        didSet {
            indexEntries = libraryIndexEntries(for: sections, sort: sortOption)
            visibleItemCount = sections.reduce(0) { $0 + $1.items.count }
        }
    }
    /// Jetons de la barre de navigation rapide et nombre de disques affichés, recalculés avec
    /// `sections` plutôt qu'à chaque lecture (plusieurs par passage de `body`).
    private(set) var indexEntries: [(token: String, sectionKey: String)] = []
    private(set) var visibleItemCount = 0
    /// Vrai pendant le calcul détaché des sections (voir `recomputeSections`) : `sections` est
    /// alors vide ou périmé sans que la recherche soit en cause. Au lancement, la vue affiche un
    /// indicateur de chargement plutôt que « Aucun résultat » le temps du premier tri.
    private(set) var isComputingSections = false
    /// Armé juste avant un retrait : le prochain calcul de sections s'applique avec animation.
    @ObservationIgnored var animatesNextSectionsUpdate = false
    /// Stockées comme propriétés `@Observable` ci-dessus (pas déléguées au moteur) pour que
    /// SwiftUI soit bien invalidé à chaque mise à jour — voir le commentaire sur
    /// `LibrarySectionsEngine`.
    @ObservationIgnored private let sectionsEngine = LibrarySectionsEngine<CollectionItem>()

    /// Tri + regroupement de la collection, délégués à `LibrarySectionsEngine` (partagé avec
    /// `WantlistViewModel`). Pendant la synchro de pages en arrière-plan juste après le lancement
    /// (`CollectionPagination`), ce recalcul se redéclenchait à chaque page reçue — ~une fois par
    /// seconde, au rythme du débit imposé par l'API Discogs — pour un coût mesuré de 300-400ms à
    /// chaque fois, provoquant des saccades si l'utilisateur faisait défiler la liste pendant
    /// cette fenêtre ; d'où le calcul détaché du moteur. Le tri `.shelf` capture son
    /// `ShelfSortContext` une seule fois en amont (voir `LibrarySectionsEngine.recompute`) et peut
    /// donc lui aussi être détaché ; seul le filtrage par tag reste synchrone (lit `TagStore`,
    /// isolé sur l'acteur principal, mais en O(n) donc déjà bon marché).
    func recomputeSections() {
        sectionsEngine.recompute(
            items: currentItems(), sortOption: sortOption, ascending: sortAscending,
            tags: selectedTags, format: selectedFormat, searchText: searchText,
            synchronous: !selectedTags.isEmpty,
            willStartAsync: { [weak self] in self?.isComputingSections = true },
            apply: { [weak self] result in
                guard let self else { return }
                // Voir `WantlistViewModel` : le recalcul est asynchrone, donc le retrait est animé ici.
                if animatesNextSectionsUpdate, !UIAccessibility.isReduceMotionEnabled {
                    withAnimation(.libraryRowRemoval) { sections = result }
                } else {
                    sections = result
                }
                animatesNextSectionsUpdate = false
                isComputingSections = false
            }
        )
    }

    /// Jeton (lettre ou année sur 2 chiffres) pour la 1re ligne de l'en-tête d'une section,
    /// cohérent avec le jeton affiché dans la barre de navigation rapide.
    func indexToken(for section: (key: String, items: [CollectionItem])) -> String {
        libraryIndexToken(for: section, sort: sortOption)
    }

    /// Valeur affichée en 2e ligne de l'en-tête (voir `CollectionItem.sectionDisplayTitle`).
    func displayTitle(for section: (key: String, items: [CollectionItem])) -> String {
        section.items.first?.sectionDisplayTitle(for: sortOption) ?? section.key
    }

    /// Artistes nommés par l'en-tête de la section, cliquables (voir `LibrarySectionHeader.artists`).
    func headerArtists(for section: (key: String, items: [CollectionItem])) -> [ReleaseArtist] {
        section.items.first?.sectionHeaderArtists(for: sortOption) ?? []
    }

    // MARK: - Badges et tags des lignes

    /// Badge « Ex. 2/3 » de chaque exemplaire possédé en plusieurs fois, par `id` d'exemplaire.
    /// Recalculé une seule fois par changement réel de la liste (comme `sections`) : la vue le
    /// relisait auparavant en reparcourant toute la collection à chaque passage de `body`, y
    /// compris à chaque changement de section pendant le défilement.
    private(set) var copyBadgesByItemId: [Int: String] = [:]

    /// Tags de chaque exemplaire affiché, par `instanceId`, recalculés quand la liste ou les tags
    /// changent. Les lignes reçoivent ce dictionnaire plutôt que de lire `TagStore` elles-mêmes :
    /// lu depuis CHAQUE ligne, son dictionnaire observé faisait refaire le rendu de toutes les
    /// lignes visibles dès qu'un seul disque changeait de tag.
    private(set) var tagsByInstanceId: [Int: [String]] = [:]

    /// À appeler à chaque changement de la liste : sections, badges et tags.
    func itemsChanged() {
        recomputeSections()
        copyBadgesByItemId = Self.copyBadges(for: currentItems())
        recomputeTagsIndex()
    }

    func recomputeTagsIndex() {
        var result: [Int: [String]] = [:]
        for item in currentItems() {
            let tags = TagStore.shared.tags(for: item.instanceId, releaseId: item.releaseId)
            if !tags.isEmpty {
                result[item.instanceId] = tags
            }
        }
        tagsByInstanceId = result
    }

    /// Badge « Ex. n/total » des disques possédés en plusieurs exemplaires, dans l'ordre de la
    /// liste. Fonction pure, testée dans `LibraryCachesTests`.
    nonisolated static func copyBadges(for items: [CollectionItem]) -> [Int: String] {
        var result: [Int: String] = [:]
        for copies in Dictionary(grouping: items, by: \.releaseId).values where copies.count > 1 {
            for (index, copy) in copies.enumerated() {
                result[copy.id] = "Ex. \(index + 1)/\(copies.count)"
            }
        }
        return result
    }
}
