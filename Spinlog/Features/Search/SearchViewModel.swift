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

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        currentPage = 1
        do {
            let response = try await DiscogsAPIClient.shared.search(
                query: trimmed,
                type: scope.typeParameter,
                page: currentPage,
                credentials: DiscogsAuthManager.shared.credentials
            )
            results = response.results
            totalPages = response.pagination.pages
        } catch {
            errorMessage = error.localizedDescription
            results = []
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
            results.append(contentsOf: response.results)
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
        isLoading = true
        errorMessage = nil
        currentPage = 1
        do {
            let response = try await DiscogsAPIClient.shared.searchByBarcode(
                code, credentials: DiscogsAuthManager.shared.credentials
            )
            results = response.results
            totalPages = response.pagination.pages
            if results.isEmpty {
                errorMessage = "Aucun disque trouvé pour le code \(code)."
            }
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        isLoading = false
    }
}
