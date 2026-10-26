import Foundation

/// Types et lectures dérivées de la section « Discographie Discogs » de la page artiste.
extension ArtistDetailViewModel {
    /// État de la section « Discographie Discogs » : œuvres principales de l'artiste, avec
    /// possession rapprochée par identifiant de master/release.
    enum DiscogsDiscographyState: Equatable {
        /// Aucune page encore reçue.
        case loading
        /// Au moins une page reçue. `isLoadingMore` : pages suivantes en cours ; `isTruncated` :
        /// liste partielle (plafond de pages atteint, ou échec d'une page suivante).
        case loaded(isLoadingMore: Bool, isTruncated: Bool)
        /// Échec avant la première page (erreur réseau, hors ligne).
        case unavailable
    }

    struct DiscogsWorkEntry: Identifiable {
        let work: ArtistReleaseItem
        let isOwned: Bool
        let isInWantlist: Bool
        let destination: SearchDestination?
        var id: String { work.id }
    }

    /// Choix du sélecteur de la discographie Discogs : une section, ou l'option temporaire
    /// « Tri en cours » qui regroupe les œuvres pas encore ventilées. Distinct de
    /// `DiscogsWorkCategory`, dont les valeurs sont persistées (cache, iCloud) : une œuvre n'est
    /// jamais « classée » en cours de tri.
    enum DiscogsSectionFilter: Hashable, Identifiable {
        case category(DiscogsWorkCategory)
        case pending

        var id: String {
            switch self {
            case .category(let category): category.rawValue
            case .pending: "pending"
            }
        }
    }

    struct ClassificationProgress: Equatable {
        let done: Int
        let total: Int
    }

    /// Œuvres pas encore ventilées dans une section.
    var pendingDiscogsCount: Int {
        discogsWorks.reduce(0) { count, work in discogsCategories[work.id] == nil ? count + 1 : count }
    }

    /// Les quatre sections, puis « Tri en cours » tant qu'il reste des œuvres à ventiler : elle
    /// se vide au fil du classement et disparaît une fois vide.
    var discogsFilterOptions: [DiscogsSectionFilter] {
        let categories = DiscogsWorkCategory.allCases.map(DiscogsSectionFilter.category)
        return pendingDiscogsCount > 0 ? categories + [.pending] : categories
    }

    func title(for filter: DiscogsSectionFilter) -> String {
        switch filter {
        case .category(let category):
            return category.title
        case .pending:
            // Après un classement interrompu (erreurs réseau), les œuvres restantes ne sont plus
            // « en cours » de tri : on le dit plutôt que de laisser croire que ça avance.
            return isSortingDiscogsWorks ? String(localized: "Tri en cours") : String(localized: "Non classées")
        }
    }

    /// Vrai tant que des œuvres peuvent encore être ventilées : pages en cours de chargement, ou
    /// classement en cours.
    var isSortingDiscogsWorks: Bool {
        if discogsClassificationProgress != nil { return true }
        switch discogsDiscographyState {
        case .loading, .loaded(isLoadingMore: true, isTruncated: _): return true
        default: return false
        }
    }
}
