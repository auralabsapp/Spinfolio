import SwiftUI
import Foundation
import Observation

@Observable
@MainActor
final class WantlistViewModel {
    static let shared = WantlistViewModel()

    /// Le tri/regroupement est coûteux à refaire à chaque lecture : voir le commentaire sur
    /// `CollectionViewModel.items` — même mécanisme ici, `sections` est recalculé une seule fois
    /// par changement réel via `recomputeSections()`, pas à chaque accès (lu à chaque frappe de
    /// recherche par la vue).
    private(set) var items: [WantlistItem] = [] {
        didSet { recomputeSections() }
    }
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Résultat d'une action (retrait, ajout à la collection…), affiché en alerte par
    /// `WantlistView` — `errorMessage`, lui, n'est visible que lorsque la liste est vide.
    var actionMessage: String?
    private(set) var isOfflineAndStale: Bool = false

    var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            recomputeSections()
        }
    }
    /// Même construction que l'onglet Collection : tri, filtre par support, sections
    /// avec en-têtes et barre de navigation rapide.
    var sortOption: CollectionSortOption = .added {
        didSet {
            guard oldValue != sortOption else { return }
            sortAscending = sortOption.defaultAscending
            recomputeSections()
            Task { await loadFirstPage() }
        }
    }

    var sortAscending: Bool = CollectionSortOption.added.defaultAscending {
        didSet {
            guard oldValue != sortAscending else { return }
            recomputeSections()
            Task { await loadFirstPage() }
        }
    }

    /// Sémantique ET : un élément n'est affiché que s'il porte tous les tags sélectionnés.
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
        !selectedTags.isEmpty || (selectedFormat != nil && !selectedFormat!.isEmpty)
    }

    func clearFilters() {
        selectedTags.removeAll()
        selectedFormat = nil
    }

    func toggleTagFilter(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func reset() {
        items = []
        folders = []
        itemAwaitingFolderChoice = nil
        currentPage = 1
        totalPages = 1
        errorMessage = nil
        isOfflineAndStale = false
        isLoading = false
        searchText = ""
        selectedTags.removeAll()
        selectedFormat = nil
        sortOption = .added
        sortAscending = CollectionSortOption.added.defaultAscending
    }

    func refresh() async {
        await load()
    }

    var availableFormats: [String] {
        var set = Set<String>()
        for item in items {
            if let formats = item.basicInformation.formats {
                for f in formats {
                    let name = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { set.insert(name) }
                }
            }
        }
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Éléments filtrés et regroupés par section, dans un ordre déterministe — identique au
    /// mécanisme de `CollectionViewModel.sections`. Recalculé par `recomputeSections()`
    /// uniquement quand `items`/tri/filtres changent réellement (voir son commentaire).
    private(set) var sections: [(key: String, items: [WantlistItem])] = []
    /// Vrai pendant le calcul détaché des sections : voir `CollectionViewModel.isComputingSections`.
    private(set) var isComputingSections = false
    private let sectionsEngine = LibrarySectionsEngine<WantlistItem>()

    /// Tri + regroupement de la wantlist, délégués à `LibrarySectionsEngine` (partagé avec
    /// `CollectionViewModel`, voir son commentaire détaillé). Le tri `.shelf` est exclu du
    /// sélecteur Wantlist (voir `WantlistView`), donc seul le filtre par tag impose de rester
    /// synchrone : `libraryItemTags` lit `TagStore.shared` via `MainActor.assumeIsolated`, qui
    /// plante si jamais exécuté hors de l'acteur principal.
    private func recomputeSections() {
        sectionsEngine.recompute(
            items: items, sortOption: sortOption, ascending: sortAscending,
            tags: selectedTags, format: selectedFormat, searchText: searchText,
            synchronous: !selectedTags.isEmpty,
            willStartAsync: { [weak self] in self?.isComputingSections = true },
            apply: { [weak self] result in
                self?.sections = result
                self?.isComputingSections = false
            }
        )
    }

    var indexEntries: [(token: String, sectionKey: String)] {
        var seenTokens = Set<String>()
        var result: [(token: String, sectionKey: String)] = []
        for section in sections {
            let token = indexToken(for: section)
            guard !seenTokens.contains(token) else { continue }
            seenTokens.insert(token)
            result.append((token, section.key))
        }
        return result
    }

    func indexToken(for section: (key: String, items: [WantlistItem])) -> String {
        libraryIndexToken(for: section, sort: sortOption)
    }

    func displayTitle(for section: (key: String, items: [WantlistItem])) -> String {
        section.items.first?.sectionDisplayTitle(for: sortOption) ?? section.key
    }

    /// Artistes nommés par l'en-tête de la section, cliquables (voir `LibrarySectionHeader.artists`).
    func headerArtists(for section: (key: String, items: [WantlistItem])) -> [ReleaseArtist] {
        section.items.first?.sectionHeaderArtists(for: sortOption) ?? []
    }

    private let authManager = DiscogsAuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let localStore = LocalDataStore.shared
    private let syncQueue = OfflineSyncQueue.shared

    init() {
        addLibraryObserver(for: .wantlistItemAdded, payloadKey: "item") { [weak self] (item: WantlistItem) in
            self?.handleWantlistItemAdded(item)
        }

        addLibraryObserver(for: .wantlistItemRemoved, payloadKey: "releaseId") { [weak self] (releaseId: Int) in
            self?.handleWantlistItemRemoved(releaseId: releaseId)
        }
    }

    private func handleWantlistItemAdded(_ item: WantlistItem) {
        if !items.contains(where: { $0.id == item.id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                items.insert(item, at: 0)
            }
        }
    }

    private func handleWantlistItemRemoved(releaseId: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            items.removeAll { $0.id == releaseId }
        }
    }

    /// Pagination paresseuse : jamais toute la wantlist en un appel (conformité API Discogs).
    private var currentPage = 1
    private var totalPages = 1

    /// Dossiers proposés lors du déplacement vers la collection ; l'item non-`nil` pilote
    /// le `confirmationDialog` de choix de dossier dans la vue.
    private(set) var folders: [CollectionFolder] = []
    var itemAwaitingFolderChoice: WantlistItem?

    func load(isSilent: Bool = false) async {
        guard let username = authManager.username else { return }

        // Si hors ligne : lecture immédiate du cache SwiftData
        if !networkMonitor.isConnected {
            await loadFromLocalStore(username: username)
            return
        }

        guard let credentials = authManager.credentials else { return }
        if !isSilent {
            isLoading = true
        }
        errorMessage = nil

        do {
            let response = try await DiscogsAPIClient.shared.wantlist(
                username: username, page: 1, sort: sortOption.apiSortValue, sortOrder: sortOption.apiSortOrder(ascending: sortAscending), credentials: credentials
            )
            // Fusionné plutôt que remplacé : voir `mergedWantlistItems`.
            items = mergedWantlistItems(primary: items, secondary: response.wants)
            currentPage = 1
            totalPages = response.pagination.pages
            isOfflineAndStale = false

            // Mise en cache dans SwiftData avec horodatage
            await persistToCache(username: username)
        } catch {
            // Repli sur le cache local
            await loadFromLocalStore(username: username)
            if items.isEmpty && !error.isCancellation {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    /// Recharge la 1re page avec le nouveau critère de tri (déclenché par `sortOption.didSet`).
    private func loadFirstPage() async {
        guard let username = authManager.username else { return }
        guard networkMonitor.isConnected, let credentials = authManager.credentials else {
            await loadFromLocalStore(username: username)
            return
        }
        if items.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        do {
            let response = try await DiscogsAPIClient.shared.wantlist(
                username: username, page: 1, sort: sortOption.apiSortValue, sortOrder: sortOption.apiSortOrder(ascending: sortAscending), credentials: credentials
            )
            // Fusionné (nouvel ordre de tri prioritaire) plutôt que remplacé : voir `mergedWantlistItems`.
            items = mergedWantlistItems(primary: response.wants, secondary: items)
            currentPage = 1
            totalPages = response.pagination.pages
            isOfflineAndStale = false
            await persistToCache(username: username)
        } catch {
            if items.isEmpty && !error.isCancellation {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    /// Fusionne une page fraîchement récupérée avec les éléments déjà affichés plutôt que de les
    /// écraser (dédoublonné par id, `primary` conserve sa version en cas de doublon) : un simple
    /// remplacement faisait brièvement disparaître un item tout juste ajouté à la wantlist si ce
    /// rafraîchissement (déclenché par exemple en rebasculant sur l'onglet Wantlist) arrivait
    /// avant que Discogs n'ait propagé l'ajout côté serveur — voir le même principe déjà en place
    /// dans `CollectionViewModel.fetchPage(append:)`.
    private func mergedWantlistItems(primary: [WantlistItem], secondary: [WantlistItem]) -> [WantlistItem] {
        var seen = Set<Int>()
        var merged: [WantlistItem] = []
        for item in primary + secondary where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }

    private func loadFromLocalStore(username: String) async {
        let cachedItems = await localStore.getWantlistItems(username: username)
        self.items = cachedItems
        self.isOfflineAndStale = localStore.isWantlistStale(username: username)
        self.isLoading = false
    }

    /// Rafraîchissement silencieux si la connexion est rétablie et que le TTL de 6h est dépassé.
    func silentRefreshIfNeeded() async {
        guard let username = authManager.username else { return }
        if networkMonitor.isConnected && localStore.isWantlistStale(username: username) {
            await load(isSilent: true)
        }
    }

    /// Déclenché depuis la ligne affichée près de la fin de la liste : charge la page
    /// suivante uniquement quand c'est nécessaire.
    func loadMoreIfNeeded(current item: WantlistItem) async {
        guard networkMonitor.isConnected else { return }
        guard let username = authManager.username, let credentials = authManager.credentials else { return }
        guard let last = items.last, last.id == item.id, currentPage < totalPages, !isLoading else { return }
        isLoading = true
        do {
            let response = try await DiscogsAPIClient.shared.wantlist(
                username: username, page: currentPage + 1, sort: sortOption.apiSortValue, sortOrder: sortOption.apiSortOrder(ascending: sortAscending), credentials: credentials
            )
            let newItems = items + response.wants
            items = newItems
            currentPage += 1
            totalPages = response.pagination.pages

            await persistToCache(username: username)
        } catch {
            // On garde les éléments déjà affichés
        }
        isLoading = false
    }

    /// Enregistre `items` dans le cache local. Une fois toutes les pages chargées (`items` part
    /// toujours de la page 1 renvoyée par Discogs, jamais du cache), la liste est complète : le
    /// cache est alors remplacé, ce qui en retire les disques sortis de la wantlist ailleurs.
    private func persistToCache(username: String) async {
        if currentPage >= totalPages {
            await localStore.replaceWantlistItems(items, username: username)
        } else {
            await localStore.saveWantlistItems(items, username: username)
        }
    }

    func remove(_ item: WantlistItem) async {
        if DemoMode.isActive {
            actionMessage = AppMessages.demoRemovalBlocked
            return
        }
        guard let username = authManager.username else { return }

        // Si l'appareil est hors ligne et que les données ont plus de 6 heures (Option B) :
        // maintien de l'affichage en lecture seule et blocage des modifications
        if !networkMonitor.isConnected && isOfflineAndStale {
            actionMessage = String(localized: "Mode hors ligne (données de plus de 6 h) : modification bloquée.")
            return
        }

        // Optimistic UI : suppression immédiate de l'UI et du cache local
        items.removeAll { $0.id == item.id }
        localStore.removeWantlistItem(username: username, releaseId: item.id)
        LibraryMembershipStore.shared.markRemovedFromWantlist(item.id)

        if networkMonitor.isConnected, let credentials = authManager.credentials {
            do {
                try await DiscogsAPIClient.shared.removeFromWantlist(username: username, releaseId: item.id, credentials: credentials)
            } catch {
                let action = PendingAction(type: .removeFromWantlist, releaseId: item.id)
                syncQueue.enqueue(action)
            }
        } else {
            let action = PendingAction(type: .removeFromWantlist, releaseId: item.id)
            syncQueue.enqueue(action)
            actionMessage = AppMessages.offlineRemovalQueued
        }
    }

    /// Supprime plusieurs éléments de la wantlist (édition en lot) — même logique que
    /// `remove`, en réutilisant le retrait unitaire et la file hors ligne.
    func removeItems(_ targets: [WantlistItem]) async {
        for item in targets {
            await remove(item)
        }
    }

    func beginMoveToCollection(_ item: WantlistItem) async {
        if DemoMode.isActive {
            actionMessage = AppMessages.demoAddBlocked
            return
        }
        guard let username = authManager.username else { return }

        if !networkMonitor.isConnected && isOfflineAndStale {
            actionMessage = String(localized: "Mode hors ligne (données de plus de 6 h) : modification bloquée.")
            return
        }

        if !networkMonitor.isConnected {
            // Utiliser les dossiers en cache local
            let cachedFolders = localStore.getFolders(username: username).filter { $0.id != 0 }
            if !cachedFolders.isEmpty {
                folders = cachedFolders
                itemAwaitingFolderChoice = item
            } else {
                // Dossier Uncategorized (id 1) par défaut
                folders = [CollectionFolder(id: 1, name: "Uncategorized", count: 0)]
                itemAwaitingFolderChoice = item
            }
            return
        }

        guard let credentials = authManager.credentials else { return }
        do {
            let response = try await DiscogsAPIClient.shared.collectionFolders(username: username, credentials: credentials)
            folders = response.folders.filter { $0.id != 0 }
            itemAwaitingFolderChoice = item
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    func confirmMoveToCollection(_ item: WantlistItem, folderId: Int) async {
        guard let username = authManager.username else { return }
        itemAwaitingFolderChoice = nil

        // Retrait immédiat de la wantlist
        await remove(item)

        // Ajout à la collection (optimistic UI géré par NotificationCenter dans CollectionViewModel)
        if networkMonitor.isConnected, let credentials = authManager.credentials {
            do {
                let response = try await DiscogsAPIClient.shared.addToCollection(
                    username: username, folderId: folderId, releaseId: item.id, credentials: credentials
                )
                let newItem = CollectionItem(
                    releaseId: item.id,
                    folderId: folderId,
                    rating: item.rating,
                    dateAdded: ISO8601DateFormatter().string(from: Date()),
                    basicInformation: item.basicInformation,
                    instanceId: response.instanceId,
                    notes: []
                )
                await localStore.saveCollectionItems([newItem], username: username, folderId: folderId)
                LibraryMembershipStore.shared.markInCollection(item.id)
                NotificationCenter.default.post(
                    name: .collectionItemAdded,
                    object: nil,
                    userInfo: ["item": newItem]
                )
            } catch {
                // `folderId` (et non `targetFolderId`, réservé aux déplacements) : c'est le champ lu
            // par la file pour un ajout — l'autre envoyait le disque dans "Uncategorized".
            let action = PendingAction(type: .addToCollection, releaseId: item.id, folderId: folderId)
                syncQueue.enqueue(action)
            }
        } else {
            // `folderId` (et non `targetFolderId`, réservé aux déplacements) : c'est le champ lu
            // par la file pour un ajout — l'autre envoyait le disque dans "Uncategorized".
            let action = PendingAction(type: .addToCollection, releaseId: item.id, folderId: folderId)
            syncQueue.enqueue(action)
            actionMessage = AppMessages.offlineAddQueued
        }
    }
}
