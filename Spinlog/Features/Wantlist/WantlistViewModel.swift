import Foundation
import Observation

@Observable
@MainActor
final class WantlistViewModel {
    private(set) var items: [WantlistItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isOfflineAndStale: Bool = false

    var searchText = ""
    /// Même construction que l'onglet Collection : tri, filtres par tag/support, sections
    /// avec en-têtes et barre de navigation rapide.
    var sortOption: CollectionSortOption = .added {
        didSet {
            guard oldValue != sortOption else { return }
            Task { await loadFirstPage() }
        }
    }
    var selectedTag: String? = nil
    var selectedFormat: String? = nil

    var hasActiveFilters: Bool {
        (selectedTag != nil && !selectedTag!.isEmpty) ||
        (selectedFormat != nil && !selectedFormat!.isEmpty)
    }

    func clearFilters() {
        selectedTag = nil
        selectedFormat = nil
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

    private var filteredItems: [WantlistItem] {
        var list = items

        if let selectedTag, !selectedTag.isEmpty {
            list = list.filter { item in
                TagStore.shared.tags(for: item.id).contains(selectedTag)
            }
        }

        if let selectedFormat, !selectedFormat.isEmpty {
            list = list.filter { item in
                item.basicInformation.formats?.contains(where: {
                    $0.name.localizedCaseInsensitiveCompare(selectedFormat) == .orderedSame
                    || ($0.descriptions ?? []).contains(where: { $0.localizedCaseInsensitiveCompare(selectedFormat) == .orderedSame })
                }) ?? false
            }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        return list.filter {
            $0.basicInformation.title.localizedCaseInsensitiveContains(trimmed)
                || $0.basicInformation.artistNames.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Éléments filtrés et regroupés par section, dans un ordre déterministe — identique au
    /// mécanisme de `CollectionViewModel.sections`.
    var sections: [(key: String, items: [WantlistItem])] {
        let sorted = filteredItems.sorted { $0.isOrderedBefore($1, for: sortOption) }
        var order: [String] = []
        var groups: [String: [WantlistItem]] = [:]
        for item in sorted {
            let key = item.sectionKey(for: sortOption)
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(item)
        }
        return order.map { ($0, groups[$0] ?? []) }
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

    private let authManager = DiscogsAuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let localStore = LocalDataStore.shared
    private let syncQueue = OfflineSyncQueue.shared

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
            loadFromLocalStore(username: username)
            return
        }

        guard let credentials = authManager.credentials else { return }
        if !isSilent {
            isLoading = true
        }
        errorMessage = nil

        do {
            let response = try await DiscogsAPIClient.shared.wantlist(
                username: username, page: 1, sort: sortOption.apiSortValue, sortOrder: sortOption.apiSortOrder, credentials: credentials
            )
            items = response.wants
            currentPage = 1
            totalPages = response.pagination.pages
            isOfflineAndStale = false

            // Mise en cache dans SwiftData avec horodatage
            localStore.saveWantlistItems(items, username: username)
        } catch {
            // Repli sur le cache local
            loadFromLocalStore(username: username)
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    /// Recharge la 1re page avec le nouveau critère de tri (déclenché par `sortOption.didSet`).
    private func loadFirstPage() async {
        guard let username = authManager.username else { return }
        guard networkMonitor.isConnected, let credentials = authManager.credentials else {
            loadFromLocalStore(username: username)
            return
        }
        if items.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        do {
            let response = try await DiscogsAPIClient.shared.wantlist(
                username: username, page: 1, sort: sortOption.apiSortValue, sortOrder: sortOption.apiSortOrder, credentials: credentials
            )
            items = response.wants
            currentPage = 1
            totalPages = response.pagination.pages
            isOfflineAndStale = false
            localStore.saveWantlistItems(items, username: username)
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func loadFromLocalStore(username: String) {
        let cachedItems = localStore.getWantlistItems(username: username)
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
                username: username, page: currentPage + 1, sort: sortOption.apiSortValue, sortOrder: sortOption.apiSortOrder, credentials: credentials
            )
            let newItems = items + response.wants
            items = newItems
            currentPage += 1
            totalPages = response.pagination.pages

            localStore.saveWantlistItems(newItems, username: username)
        } catch {
            // On garde les éléments déjà affichés
        }
        isLoading = false
    }

    func remove(_ item: WantlistItem) async {
        guard let username = authManager.username else { return }

        // Si l'appareil est hors ligne et que les données ont plus de 6 heures (Option B) :
        // maintien de l'affichage en lecture seule et blocage des modifications
        if !networkMonitor.isConnected && isOfflineAndStale {
            errorMessage = "Mode hors ligne (données de plus de 6h) : modification bloquée."
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
        }
    }

    /// Charge les dossiers disponibles puis ouvre le sélecteur ; `confirmMoveToCollection`
    /// termine le déplacement une fois le dossier choisi.
    func beginMoveToCollection(_ item: WantlistItem) async {
        guard let username = authManager.username else { return }

        if !networkMonitor.isConnected && isOfflineAndStale {
            errorMessage = "Mode hors ligne (données de plus de 6h) : modification bloquée."
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
            errorMessage = error.localizedDescription
        }
    }

    func confirmMoveToCollection(_ item: WantlistItem, folderId: Int) async {
        guard let username = authManager.username else { return }

        if !networkMonitor.isConnected && isOfflineAndStale {
            errorMessage = "Mode hors ligne (données de plus de 6h) : modification bloquée."
            itemAwaitingFolderChoice = nil
            return
        }

        // Optimistic UI
        items.removeAll { $0.id == item.id }
        localStore.removeWantlistItem(username: username, releaseId: item.id)
        LibraryMembershipStore.shared.markRemovedFromWantlist(item.id)
        LibraryMembershipStore.shared.markInCollection(item.id)
        itemAwaitingFolderChoice = nil

        if networkMonitor.isConnected, let credentials = authManager.credentials {
            do {
                _ = try await DiscogsAPIClient.shared.addToCollection(
                    username: username, folderId: folderId, releaseId: item.id, credentials: credentials
                )
                try await DiscogsAPIClient.shared.removeFromWantlist(username: username, releaseId: item.id, credentials: credentials)
            } catch {
                syncQueue.enqueue(PendingAction(type: .addToCollection, releaseId: item.id, folderId: folderId))
                syncQueue.enqueue(PendingAction(type: .removeFromWantlist, releaseId: item.id))
            }
        } else {
            syncQueue.enqueue(PendingAction(type: .addToCollection, releaseId: item.id, folderId: folderId))
            syncQueue.enqueue(PendingAction(type: .removeFromWantlist, releaseId: item.id))
        }
    }
}
