import Foundation
import Observation

@Observable
@MainActor
final class CollectionViewModel {
    private(set) var folders: [CollectionFolder] = []
    private(set) var selectedFolderId: Int?
    private(set) var fields: [CollectionField] = []
    private(set) var items: [CollectionItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var searchText = ""
    var sortOption: CollectionSortOption = .artist {
        didSet {
            guard oldValue != sortOption, let folderId = selectedFolderId else { return }
            Task { await loadFirstPage(folderId: folderId) }
        }
    }

    private let authManager = DiscogsAuthManager.shared
    /// Pagination paresseuse : la 1re page s'affiche tout de suite (jamais toute la collection
    /// d'un coup), puis `backgroundSyncTask` continue de charger les pages suivantes en tâche
    /// de fond — c'est la seconde option explicitement permise par l'API Discogs pour les
    /// grosses collections, et c'est nécessaire pour que la barre de navigation rapide (lettres/
    /// années) reflète tout le dossier plutôt que seulement ce qui a déjà défilé à l'écran.
    private var currentPage = 1
    private var totalPages = 1
    private var backgroundSyncTask: Task<Void, Never>?

    /// Éléments filtrés par la recherche, regroupés par section pour l'en-tête sticky
    /// (ordre de groupes préservé tel que renvoyé par le tri serveur).
    var sections: [(key: String, items: [CollectionItem])] {
        var order: [String] = []
        var groups: [String: [CollectionItem]] = [:]
        for item in filteredItems {
            let key = item.sectionKey(for: sortOption)
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(item)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Jetons pour la barre de navigation rapide sur le bord droit : lettres pour un tri
    /// alphabétique, années sur 2 chiffres pour un tri par date d'ajout. Chaque jeton est
    /// associé à la clé de la première section correspondante, pour y faire défiler la liste.
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

    /// Jeton (lettre ou année sur 2 chiffres) pour la 1re ligne de l'en-tête d'une section,
    /// cohérent avec le jeton affiché dans la barre de navigation rapide.
    func indexToken(for section: (key: String, items: [CollectionItem])) -> String {
        switch sortOption {
        case .added:
            guard let date = section.items.first?.dateAddedDate else { return "?" }
            let year = Calendar.current.component(.year, from: date) % 100
            return String(format: "%02d", year)
        case .year:
            return String(section.key.suffix(2))
        case .artist, .title, .format, .genre, .label:
            return String(section.key.prefix(1)).uppercased()
        }
    }

    /// Valeur affichée en 2e ligne de l'en-tête (voir `CollectionItem.sectionDisplayTitle`).
    func displayTitle(for section: (key: String, items: [CollectionItem])) -> String {
        section.items.first?.sectionDisplayTitle(for: sortOption) ?? section.key
    }

    private var filteredItems: [CollectionItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.basicInformation.title.localizedCaseInsensitiveContains(trimmed)
                || $0.basicInformation.artistNames.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func loadFoldersAndItems() async {
        guard let username = authManager.username, let credentials = authManager.credentials else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let foldersRequest = DiscogsAPIClient.shared.collectionFolders(username: username, credentials: credentials)
            async let fieldsRequest = DiscogsAPIClient.shared.collectionFields(username: username, credentials: credentials)
            let (foldersResponse, fieldsResponse) = try await (foldersRequest, fieldsRequest)
            folders = foldersResponse.folders
            fields = fieldsResponse.fields

            let folderId = selectedFolderId ?? folders.first?.id ?? 0
            selectedFolderId = folderId
            try await fetchPage(1, username: username, folderId: folderId, credentials: credentials, append: false)
            startBackgroundSync(username: username, folderId: folderId, credentials: credentials)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func selectFolder(_ folderId: Int) async {
        selectedFolderId = folderId
        await loadFirstPage(folderId: folderId)
    }

    /// Déclenché depuis la ligne affichée près de la fin de la liste : par sécurité si la
    /// synchronisation de fond n'a pas encore rattrapé le défilement (ne double-charge pas,
    /// `startBackgroundSync` s'en charge déjà dans l'immense majorité des cas).
    func loadMoreIfNeeded(current item: CollectionItem) async {
        guard let username = authManager.username, let credentials = authManager.credentials,
              let folderId = selectedFolderId else { return }
        guard let last = items.last, last.id == item.id, currentPage < totalPages, backgroundSyncTask == nil else { return }
        do {
            try await fetchPage(currentPage + 1, username: username, folderId: folderId, credentials: credentials, append: true)
        } catch {
            // On garde les éléments déjà affichés ; le prochain passage en fin de liste réessaiera.
        }
    }

    private func loadFirstPage(folderId: Int) async {
        guard let username = authManager.username, let credentials = authManager.credentials else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await fetchPage(1, username: username, folderId: folderId, credentials: credentials, append: false)
            startBackgroundSync(username: username, folderId: folderId, credentials: credentials)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Continue de charger les pages suivantes une par une derrière l'écran (chaque appel
    /// passe par le throttle Discogs), jusqu'à couvrir tout le dossier ou jusqu'à ce qu'un
    /// changement de dossier/tri annule cette tâche pour la remplacer par une nouvelle.
    private func startBackgroundSync(username: String, folderId: Int, credentials: DiscogsCredentials) {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let page = await self.currentPage
                let total = await self.totalPages
                guard page < total else { break }
                do {
                    try await self.fetchPage(page + 1, username: username, folderId: folderId, credentials: credentials, append: true)
                } catch {
                    break
                }
            }
            if !Task.isCancelled {
                self.backgroundSyncTask = nil
            }
        }
    }

    private func fetchPage(
        _ page: Int,
        username: String,
        folderId: Int,
        credentials: DiscogsCredentials,
        append: Bool
    ) async throws {
        let response = try await DiscogsAPIClient.shared.collectionItems(
            username: username,
            folderId: folderId,
            page: page,
            sort: sortOption.apiSortValue,
            sortOrder: sortOption.apiSortOrder,
            credentials: credentials
        )
        items = append ? items + response.releases : response.releases
        currentPage = page
        totalPages = response.pagination.pages
    }

    func remove(_ item: CollectionItem) async {
        guard let username = authManager.username, let credentials = authManager.credentials else { return }
        do {
            try await DiscogsAPIClient.shared.removeFromCollection(
                username: username,
                folderId: item.folderId,
                releaseId: item.releaseId,
                instanceId: item.instanceId,
                credentials: credentials
            )
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reflète localement une note/des champs personnalisés déjà enregistrés par
    /// `CollectionItemEditSheet` (qui gère lui-même les appels réseau).
    func applyEditedValues(for item: CollectionItem, rating: Int, notes: [CollectionFieldValue]) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].rating = rating
        items[index].notes = notes
    }
}
