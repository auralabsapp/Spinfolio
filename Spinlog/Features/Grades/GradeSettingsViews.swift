import SwiftUI

/// Badges du grade acquis de chaque parcours, à côté du nom d'utilisateur dans Réglages. Rien tant
/// qu'aucun grade n'est acquis.
struct GradeInlineBadges: View {
    @State private var store = GradeStore.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GradeTrack.allCases) { track in
                let acquired = store.acquiredTiers(for: track)
                if acquired > 0 {
                    GradeBadgeView(track: track, tier: acquired - 1, size: 36)
                        .accessibilityElement()
                        .accessibilityLabel(Text("\(String(localized: track.tierName(acquired - 1))), \(track.titleText)"))
                }
            }
        }
    }
}

/// Ligne « Mes grades » de Réglages : résume les deux grades acquis et mène à la page complète.
struct GradeSummaryRow: View {
    @State private var store = GradeStore.shared

    private var summary: String {
        let names = GradeTrack.allCases.compactMap { track -> String? in
            let acquired = store.acquiredTiers(for: track)
            return acquired > 0 ? String(localized: track.tierName(acquired - 1)) : nil
        }
        return names.isEmpty
            ? String(localized: "Gagne ton premier grade en ajoutant un album.")
            : names.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(systemName: "rosette", backgroundColor: Color.spinlogPink)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mes grades")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
