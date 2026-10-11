import SwiftUI

/// Noms d'artistes cliquables : chacun ouvre sa fiche (`ArtistDetailView`) dans la pile de
/// navigation courante (qui doit déclarer `.searchDestinations()`). Même principe que la ligne
/// d'artistes de la fiche album (`ReleaseDetailView.artistCreditsRow`), mais avec le texte
/// habituel des listes : les noms séparés par des virgules, comme `BasicInformation.artistNames`.
/// Police et couleur viennent de l'environnement ; sans artiste connu, `fallback` s'affiche en
/// texte simple.
struct ArtistNameLinks: View {
    let artists: [ReleaseArtist]
    let fallback: String
    /// Nom affiché pour chaque artiste (par défaut son nom Discogs, tel que dans les listes).
    var displayName: (ReleaseArtist) -> String = \.name

    var body: some View {
        if artists.isEmpty {
            Text(fallback)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                    NavigationLink(value: SearchDestination.artist(artist.id)) {
                        Text(displayName(artist))
                    }
                    .buttonStyle(.plain)

                    if index < artists.count - 1 {
                        Text(verbatim: ", ")
                    }
                }
            }
        }
    }
}
