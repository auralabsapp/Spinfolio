import SwiftUI

/// Description d'une fonctionnalité premium (icône, couleur, titre, résumé), pour l'écran
/// listant l'ensemble de ces fonctionnalités depuis Réglages.
private struct PremiumFeatureInfo: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let description: String
}

/// Liste des fonctionnalités actuellement réservées aux comptes premium, tenue à jour
/// manuellement en miroir de chaque `PremiumLockedCard`/`premiumUpsellAlert` posé dans l'app.
private let premiumFeatures: [PremiumFeatureInfo] = [
    PremiumFeatureInfo(
        icon: "banknote.fill",
        color: .green,
        title: "Suivi de cote",
        description: "Prix d'achat, plus-value latente et comparaison « investi vs cote actuelle », dans Réglages et Statistiques."
    ),
    PremiumFeatureInfo(
        icon: "waveform",
        color: .spinlogPink,
        title: "Compteur de lecture",
        description: "Enregistre chaque écoute d'un vinyle et retrouve le nombre total d'écoutes et la date de la dernière."
    ),
    PremiumFeatureInfo(
        icon: "rectangle.stack.badge.plus",
        color: .blue,
        title: "Scan par lot",
        description: "Scanne plusieurs codes-barres à la suite (brocante, disquaire) et ajoute-les en une fois à ta collection ou ta wantlist."
    ),
    PremiumFeatureInfo(
        icon: "bell.fill",
        color: .orange,
        title: "Alertes de prix sur la wantlist",
        description: "Reçois une notification dès qu'un disque de ta wantlist apparaît à bon prix sur le marketplace Discogs."
    ),
    PremiumFeatureInfo(
        icon: "books.vertical.fill",
        color: .purple,
        title: "Guide de rangement physique",
        description: "Retrouve instantanément où ranger un vinyle dans ton meuble, avec ses voisins immédiats selon ton tri personnalisé."
    ),
    PremiumFeatureInfo(
        icon: "shuffle",
        color: .indigo,
        title: "Widget « Album du jour »",
        description: "Un disque de ta collection tiré au hasard chaque jour, directement sur l'écran d'accueil."
    )
]

/// Écran listant toutes les fonctionnalités premium avec un court descriptif, accessible depuis
/// Réglages pour que l'utilisateur sache précisément ce que débloque l'interrupteur premium.
struct PremiumFeaturesSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Le compte premium débloque ces fonctionnalités sur cet appareil :")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)

                    VStack(spacing: 0) {
                        ForEach(Array(premiumFeatures.enumerated()), id: \.element.id) { index, feature in
                            featureRow(feature)
                            if index < premiumFeatures.count - 1 {
                                Divider().opacity(0.15).padding(.leading, 58)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .appleMusicGroupedCard()
                }
                .padding()
            }
            .navigationTitle("Fonctionnalités premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
