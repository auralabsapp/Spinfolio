import SwiftUI

/// Bandeau persistant affiché en haut des vues de collection et wantlist lorsque l'appareil est
/// hors ligne et que les données en cache dépassent le TTL de 6 heures (Option B).
struct OfflineBannerView: View {
    let message: String

    init(message: String = "Mode hors ligne — Données en cache non actualisées depuis plus de 6h") {
        self.message = message
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
                .font(.subheadline)

            Text(message)
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
