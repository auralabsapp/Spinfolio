import SwiftUI

/// Pastille de statut d'une œuvre de la discographie d'un artiste par rapport à la collection
/// locale de l'utilisateur (voir `ArtistDetailViewModel.OwnershipStatus`). Pas de pastille pour
/// une œuvre ni possédée ni en wantlist : son absence suffit.
struct StatusBadgeView: View {
    let status: ArtistDetailViewModel.OwnershipStatus

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var text: String {
        switch status {
        case .owned: String(localized: "Collection")
        case .inWantlist: String(localized: "Wantlist")
        }
    }

    private var icon: String {
        switch status {
        case .owned: "checkmark.circle.fill"
        case .inWantlist: "heart.fill"
        }
    }

    private var color: Color {
        switch status {
        case .owned: Color.tagForeground
        case .inWantlist: Color.spinlogPink
        }
    }
}
