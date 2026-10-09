import Foundation
import Observation

enum SearchScope: String, CaseIterable, Identifiable {
    case all = "Tout"
    case release = "Releases"
    case artist = "Artistes"
    case label = "Labels"

    var id: String { rawValue }

    var typeParameter: String? {
        switch self {
        case .all: return nil
        case .release: return "release"
        case .artist: return "artist"
        case .label: return "label"
        }
    }
}

@Observable
@MainActor
final class SearchViewModel {
    /// Singleton (voir `CollectionViewModel.shared`) : la vue Recherche reste montée en
    /// permanence dans le `TabView` racine, donc cette instance et sa requête/ses résultats
    /// survivent tels quels à une déconnexion/reconnexion Discogs si personne ne les vide
    /// explicitement — d'où `reset()`, appelé par `DiscogsAuthManager.logout()`.
    static let shared = SearchViewModel()

    var query = ""
    var scope: SearchScope = .all
    private(set) var results: [SearchResult] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var currentPage = 1
    private var totalPages = 1
    /// Empêche la recherche texte débouncée de se relancer juste après avoir renseigné
    /// `query` avec un code-barres scanné (on a déjà les résultats de `searchByBarcode`).
    private var suppressNextAutoSearch = false

    func consumeSuppressFlag() -> Bool {
        guard suppressNextAutoSearch else { return false }
        suppressNextAutoSearch = false
        return true
    }

    /// Vide la requête et les résultats affichés : la recherche Discogs elle-même n'est liée à
    /// aucun compte, mais laisser la requête/les résultats d'un compte visibles après changement
    /// de compte est trompeur (et `searchLocalLibrary` re-mélangerait sinon collection/wantlist
    /// de l'ancien compte avec des résultats obtenus sous le nouveau).
    func reset() {
        query = ""
        results = []
        errorMessage = nil
        isLoading = false
        currentPage = 1
        totalPages = 1
        suppressNextAutoSearch = false
    }

    /// Affiche une erreur venue du scanner (ex: caméra indisponible) dans le même état
    /// d'erreur que la recherche texte, plutôt que de la faire disparaître silencieusement.
    func reportScannerError(_ message: String) {
        suppressNextAutoSearch = true
        errorMessage = message
        results = []
    }

    /// Recherche dans la collection et la wantlist locales les albums dont le titre ou l'artiste
    /// correspondent aux termes de la requête. Permet d'afficher TOUS les disques de l'utilisateur,
    /// même si l'API Discogs ne les renvoie pas dans sa première page de recherche générale.
    private func searchLocalLibrary(query: String) -> (collection: [SearchResult], wantlist: [SearchResult]) {
        guard let username = DiscogsAuthManager.shared.username else { return ([], []) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], []) }

        let keywords = trimmed.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !keywords.isEmpty else { return ([], []) }

        let collectionItems = LocalDataStore.shared.getAllCollectionItems(username: username)
        var matchingCollection: [SearchResult] = []
        var seenReleaseIds = Set<Int>()

        for item in collectionItems {
            guard !seenReleaseIds.contains(item.releaseId) else { continue }
            let title = item.basicInformation.title.lowercased()
            let artists = item.basicInformation.artistNames.lowercased()
            let fullText = "\(artists) \(title)"
            let matches = keywords.allSatisfy { fullText.contains($0) }
            if matches {
                seenReleaseIds.insert(item.releaseId)
                matchingCollection.append(SearchResult(from: item.basicInformation))
            }
        }

        let wantlistItems = LocalDataStore.shared.getWantlistItems(username: username)
        var matchingWantlist: [SearchResult] = []
        for item in wantlistItems {
            guard !seenReleaseIds.contains(item.id) else { continue }
            let title = item.basicInformation.title.lowercased()
            let artists = item.basicInformation.artistNames.lowercased()
            let fullText = "\(artists) \(title)"
            let matches = keywords.allSatisfy { fullText.contains($0) }
            if matches {
                seenReleaseIds.insert(item.id)
                matchingWantlist.append(SearchResult(from: item.basicInformation))
            }
        }

        return (matchingCollection, matchingWantlist)
    }

    /// Réordonne les résultats pour placer en tête de liste ceux déjà présents
    /// dans la collection ou dans la wantlist, tout en préservant l'ordre de
    /// pertinence Discogs à l'intérieur de chaque groupe.
    private func prioritizeLibraryResults(_ items: [SearchResult]) -> [SearchResult] {
        let membership = LibraryMembershipStore.shared
        let inCollection = items.filter { membership.isInCollection($0.id) }
        let inWantlist = items.filter { !membership.isInCollection($0.id) && membership.isInWantlist($0.id) }
        let others = items.filter { !membership.isInCollection($0.id) && !membership.isInWantlist($0.id) }
        return inCollection + inWantlist + others
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            errorMessage = nil
            return
        }
        LibraryMembershipStore.shared.refresh()
        isLoading = true
        errorMessage = nil
        currentPage = 1

        let shouldSearchLocal = (scope == .all || scope == .release)
        let (localCollection, localWantlist) = shouldSearchLocal ? searchLocalLibrary(query: trimmed) : ([], [])
        var seenIds = Set<Int>(localCollection.map(\.id) + localWantlist.map(\.id))

        if !localCollection.isEmpty || !localWantlist.isEmpty {
            results = localCollection + localWantlist
        }

        do {
            let response = try await DiscogsAPIClient.shared.search(
                query: trimmed,
                type: scope.typeParameter,
                page: currentPage,
                credentials: DiscogsAuthManager.shared.credentials
            )

            let newRemote = response.results.filter { !seenIds.contains($0.id) }
            for item in newRemote {
                seenIds.insert(item.id)
            }

            let prioritizedRemote = prioritizeLibraryResults(newRemote)
            results = localCollection + localWantlist + prioritizedRemote
            totalPages = response.pagination.pages
        } catch {
            if results.isEmpty && !error.isCancellation {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func loadMoreIfNeeded(current item: SearchResult) async {
        guard let last = results.last, last.id == item.id, last.type == item.type,
              currentPage < totalPages, !isLoading else { return }
        let nextPage = currentPage + 1
        isLoading = true
        do {
            let response = try await DiscogsAPIClient.shared.search(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                type: scope.typeParameter,
                page: nextPage,
                credentials: DiscogsAuthManager.shared.credentials
            )
            let existingIds = Set(results.map(\.id))
            let newItems = response.results.filter { !existingIds.contains($0.id) }
            results.append(contentsOf: prioritizeLibraryResults(newItems))
            currentPage = nextPage
        } catch {
            // On garde les résultats déjà affichés ; une prochaine tentative de scroll réessaiera.
        }
        isLoading = false
    }

    /// Recherche par code-barres scanné : remplace le contenu du champ pour montrer ce qui a
    /// été scanné, sans déclencher la recherche texte débouncée derrière (`suppressNextAutoSearch`).
    func searchByBarcode(_ code: String) async {
        suppressNextAutoSearch = true
        query = code
        LibraryMembershipStore.shared.refresh()
        isLoading = true
        errorMessage = nil
        currentPage = 1
        do {
            let response = try await DiscogsAPIClient.shared.searchByBarcode(
                code, credentials: DiscogsAuthManager.shared.credentials
            )
            results = prioritizeLibraryResults(response.results)
            totalPages = response.pagination.pages
            if results.isEmpty {
                errorMessage = String(localized: "Aucun disque trouvé pour le code \(code).")
            }
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        isLoading = false
    }
}
