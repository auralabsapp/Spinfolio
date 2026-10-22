import SwiftUI

/// Tuile de chiffre de la feuille « Alerte de prix » (nombre d'annonces, annonce la moins chère).
/// Avec `action`, la tuile est un bouton (flèche ↗ en haut à droite) ; sinon, un simple bloc d'information.
struct MarketTile: View {
    let title: LocalizedStringKey
    let value: Text
    let icon: String
    var highlighted: Bool = false
    var action: (() -> Void)? = nil

    private var tile: some View {
        VStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appSecondaryText)
            value
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(highlighted ? Color.spinlogPink : Color.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if action != nil {
                // Indique que la tuile s'ouvre (comme les lignes qui renvoient vers Discogs).
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appTertiaryText)
                    .padding(10)
            }
        }
    }

    @ViewBuilder
    var body: some View {
        if let action {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                tile.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre les annonces sur Discogs.com")
        } else {
            tile.accessibilityElement(children: .combine)
        }
    }
}
