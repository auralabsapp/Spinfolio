import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult

    private var membership = LibraryMembershipStore.shared

    /// Seuls les résultats "release" ont une correspondance directe en collection/wantlist
    /// (masters/artistes/labels n'ont pas d'identifiant de release à vérifier).
    private var isRelease: Bool { result.type == "release" }

    var body: some View {
        ZStack(alignment: .leading) {
            // `NavigationLink` invisible mais couvrant toute la ligne. Le libellé doit être une
            // vue qui s'étend pour remplir l'espace proposé (`Color.clear`) : `EmptyView()` a une
            // taille intrinsèque nulle et ne s'étend pas, ce qui réduisait la zone cliquable à
            // (quasiment) rien une fois ce lien sorti de la position "contenu direct de la ligne"
            // (seul cas où `List` étend automatiquement un `NavigationLink` à toute la ligne).
            NavigationLink(value: SearchDestination(from: result)) {
                Color.clear
            }
            .opacity(0)

            HStack(spacing: 12) {
                AsyncCoverImage(url: result.thumb ?? result.coverImage, cornerRadius: AppLayout.coverCornerRadius, targetSize: 56)
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.body)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        if let year = result.year, !year.isEmpty {
                            Text(year)
                        }
                        if let format = result.format?.first {
                            Text("· \(format)")
                        }
                        if let label = result.label?.first {
                            Text("· \(label)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)

                    if isRelease && (membership.isInCollection(result.id) || membership.isInWantlist(result.id)) {
                        HStack(spacing: 6) {
                            if membership.isInCollection(result.id) {
                                StatusBadgeView(status: .collection)
                            }
                            if membership.isInWantlist(result.id) {
                                StatusBadgeView(status: .wantlist)
                            }
                        }
                        .padding(.top, 1)
                    }
                }

                Spacer(minLength: 0)

                // Chevron ajouté manuellement : `List` ne l'ajoute plus automatiquement
                // puisque le `NavigationLink` n'est plus le contenu direct de la ligne.
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appSecondaryText.opacity(0.5))
            }
            .padding(.vertical, 2)
            .allowsHitTesting(false)
        }
    }
}
