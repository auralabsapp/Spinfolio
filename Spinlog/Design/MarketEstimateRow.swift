import SwiftUI

/// Ligne « Cote actuelle » d'un exemplaire, dans la devise d'affichage. Visible par tous les
/// comptes : seule la plus-value (comparaison au prix d'achat) est réservée au Premium.
/// Une cote de plus de 6 h servie hors ligne affiche sa date plutôt que « actuelle » (CGU Discogs).
struct MarketEstimateRow: View {
    let price: Double
    let currency: String
    let staleSince: Date?
    var showsChevron = false

    var body: some View {
        HStack {
            Group {
                if let staleSince {
                    Text("Cote du \(staleSince.formatted(.dateTime.day().month(.abbreviated)))")
                } else {
                    Text("Cote actuelle")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            Spacer()
            Text(price.formatted(.currency(code: currency)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.spinlogPink)
                .monospacedDigit()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appTertiaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
