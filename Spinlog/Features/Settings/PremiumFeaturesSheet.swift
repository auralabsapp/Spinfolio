import SwiftUI

/// Écran listant toutes les fonctionnalités premium avec un court descriptif.
/// Présenté sous forme de feuille modale (Sheet) avec sa barre de navigation et son bouton Fermer,
/// identique partout dans l'application.
struct PremiumFeaturesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Le compte premium débloque ces fonctionnalités sur cet appareil :")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)

                    VStack(spacing: 0) {
                        ForEach(Array(PremiumFeatureCatalog.all.enumerated()), id: \.element.id) { index, feature in
                            featureRow(feature)
                            if index < PremiumFeatureCatalog.all.count - 1 {
                                Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 58)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .appleMusicGroupedCard()
                }
                .padding()
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Fonctionnalités premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton {
                        dismiss()
                    }
                }
            }
        }
    }

    private func featureRow(_ feature: PremiumFeatureInfo) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(systemName: feature.icon, backgroundColor: feature.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(feature.description)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

#Preview {
    PremiumFeaturesSheet()
}
