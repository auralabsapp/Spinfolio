import SwiftUI

/// En-tête sticky compact partagé par Collection et Wantlist : le jeton (lettre ou année)
/// aligné sur la même ligne que la valeur complète du groupe (artiste, album, mois...),
/// et le badge avec le nombre d'éléments à droite.
struct LibrarySectionHeader: View {
    let token: String
    let title: String
    let count: Int
    /// Artistes nommés par `title` (tri par artiste ou par meuble) : le titre devient alors un
    /// lien vers leur fiche. Vide pour les autres tris (album, année, label…).
    var artists: [ReleaseArtist] = []

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayToken)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.spinlogPink)

                if displayToken != title && !title.isEmpty {
                    ArtistNameLinks(artists: artists, fallback: title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            Text("\(count)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.buttonPinkTop, Color.buttonPinkBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
        }
        .padding(.vertical, 2)
        .padding(.trailing, 4)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
    }

    /// Si le jeton est une année, s'assure qu'elle est affichée au format AAAA (4 chiffres)
    private var displayToken: String {
        if token.count == 2, let num = Int(token) {
            let fullYear = num <= 50 ? (2000 + num) : (1900 + num)
            return String(fullYear)
        }
        return token
    }
}
