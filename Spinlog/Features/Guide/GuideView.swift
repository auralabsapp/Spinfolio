import SwiftUI

/// Page d'accueil du guide (Réglages > Guide) : une ligne par section, qui ouvre sa page.
/// Les destinations passent par `SettingsDestination`, comme les autres écrans de Réglages, pour
/// que le re-tap sur l'onglet puisse revenir à la racine.
struct GuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Découvre les fonctions de l'app, section par section. Le guide ne modifie rien : il explique, et te mène là où ça se passe.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondaryText)

                VStack(spacing: 0) {
                    ForEach(GuideSection.allCases) { section in
                        NavigationLink(value: SettingsDestination.guideSection(section)) {
                            sectionRow(section)
                        }
                        .buttonStyle(.plain)

                        if section != GuideSection.allCases.last {
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
        .navigationTitle("Guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionRow(_ section: GuideSection) -> some View {
        HStack(spacing: 14) {
            SettingsIcon(systemName: section.symbol, backgroundColor: section.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(section.summary)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.appTertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        GuideView()
    }
}
