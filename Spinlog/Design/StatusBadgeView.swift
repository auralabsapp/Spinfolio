import SwiftUI

/// Statut d'une œuvre par rapport à la bibliothèque locale de l'utilisateur. Type générique
/// (pas lié à un écran précis) : avant lui, `StatusBadgeView` référençait directement
/// `ArtistDetailViewModel.OwnershipStatus`, une violation de la séparation Design/Features
/// (un composant censé être réutilisable dépendait d'un type propre à un seul écran) — et le
/// même badge visuel était réimplémenté séparément dans `SearchResultRow` avec des constantes
/// légèrement différentes (padding, graisse de police).
enum MembershipStatus {
    case collection
    case wantlist
}

/// Pastille de statut (collection / wantlist), utilisée par la fiche artiste et les résultats
/// de recherche. Pas de pastille pour une œuvre ni possédée ni en wantlist : son absence suffit.
struct StatusBadgeView: View {
    let status: MembershipStatus

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var text: String {
        switch status {
        case .collection: String(localized: "Collection")
        case .wantlist: String(localized: "Wantlist")
        }
    }

    private var icon: String {
        switch status {
        case .collection: "checkmark.circle.fill"
        case .wantlist: "heart.fill"
        }
    }

    private var color: Color {
        switch status {
        case .collection: Color.tagForeground
        case .wantlist: Color.spinlogPink
        }
    }
}
