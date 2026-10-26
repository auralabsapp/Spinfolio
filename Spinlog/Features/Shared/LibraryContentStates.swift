import SwiftUI

// États d'écran partagés par la Collection et la Wantlist (erreur, liste vide, aucun résultat),
// écrits auparavant deux fois à l'identique dans `CollectionView` et `WantlistView`. Chaque état
// garde sa propre vue de défilement, comme avant : le grand titre de navigation s'y attache.

/// Échec du premier chargement, sans rien en cache à afficher.
struct LibraryErrorState: View {
    let message: String
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label("Erreur", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") {
                    Task { await onRefresh() }
                }
                .buttonStyle(.glassProminent)
                .foregroundStyle(Color.onAccent)
            }
            .frame(maxWidth: .infinity, minHeight: 400)
        }
        .libraryRefreshable {
            await onRefresh()
        }
    }
}

/// Bibliothèque vide, avec un bouton vers la recherche.
struct LibraryEmptyLibraryState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            LibraryEmptyState(title: title, message: message, symbol: symbol) {
                Button("Rechercher un disque") {
                    TabNavigationCoordinator.shared.selectedTab = .search
                }
                .buttonStyle(.glassProminent)
                .foregroundStyle(Color.onAccent)
            }
            .frame(maxWidth: .infinity, minHeight: 400)
        }
        .libraryRefreshable {
            await onRefresh()
        }
    }
}

/// Aucun disque ne correspond à la recherche ou aux filtres : bandeau hors ligne éventuel, barre
/// des filtres actifs (fournie par l'écran), puis l'état « aucun résultat » du système.
struct LibraryNoResultsState<FiltersBar: View>: View {
    let isOfflineAndStale: Bool
    let searchText: String
    @ViewBuilder let filtersBar: () -> FiltersBar

    var body: some View {
        VStack(spacing: 0) {
            if isOfflineAndStale {
                LibraryOfflineBanner()
            }
            filtersBar()
            ContentUnavailableView.search(text: searchText)
        }
    }
}

/// Bandeau hors ligne des listes, avec la date et le volume de la dernière synchro complète.
struct LibraryOfflineBanner: View {
    var body: some View {
        OfflineBannerView(
            lastSyncDate: OfflineDownloadManager.shared.lastSyncDate,
            itemCount: OfflineDownloadManager.shared.offlineItemCount
        )
    }
}
