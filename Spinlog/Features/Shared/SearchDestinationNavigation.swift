import SwiftUI

extension View {
    /// Résout la navigation vers le détail d'une release/master/artiste/label.
    /// À appliquer à la racine de chaque `NavigationStack` qui peut pousser un `SearchDestination`
    /// (chaque onglet a sa propre pile de navigation, donc sa propre déclaration).
    func searchDestinations() -> some View {
        navigationDestination(for: SearchDestination.self) { destination in
            switch destination {
            case .release(let id, let coverURL):
                ReleaseDetailView(releaseId: id, initialCoverURL: coverURL)
            case .master(let id):
                MasterDetailView(masterId: id)
            case .artist(let id):
                ArtistDetailView(artistId: id)
            case .label(let id):
                LabelDetailView(labelId: id)
            }
        }
    }
}
