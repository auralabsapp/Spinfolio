import SwiftUI

/// Calcul de la plus-value d'un exemplaire (prix payé et cote, dans la même devise).
nonisolated struct GainSummary: Equatable {
    let purchase: Double
    let estimate: Double

    var gain: Double { estimate - purchase }

    /// Plus-value rapportée au prix payé ; `nil` si le prix payé est nul (division impossible).
    var percent: Double? { purchase > 0 ? gain / purchase : nil }

    var isGain: Bool { gain >= 0 }
}

/// Trois pastilles côte à côte : prix payé, cote actuelle, plus-value (verte ou rouge). Réservé au
/// Premium par l'écran appelant.
struct GainSummaryTiles: View {
    let summary: GainSummary
    let currency: String

    var body: some View {
        HStack(spacing: 8) {
            tile(title: "Payé", value: summary.purchase.formatted(.currency(code: currency)))
            tile(title: "Cote", value: summary.estimate.formatted(.currency(code: currency)))
            gainTile
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appSecondaryText)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var gainTile: some View {
        let color = summary.isGain ? Color.gainPositive : Color.gainNegative
        return VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: summary.isGain ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2.weight(.bold))
                Text("Plus-value")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(color)
            Text("\(summary.isGain ? "+" : "")\(summary.gain.formatted(.currency(code: currency).precision(.fractionLength(0))))")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let percent = summary.percent {
                Text(percent.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always())))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
