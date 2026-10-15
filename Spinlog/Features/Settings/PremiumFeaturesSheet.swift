import SwiftUI

/// Description d'une fonctionnalité premium (icône, couleur, titre, résumé), pour l'écran
/// listant l'ensemble de ces fonctionnalités.
private struct PremiumFeatureInfo: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    // `LocalizedStringResource` : les libellés sont extraits dans le catalogue et traduits
    // (en `String`, ils s'affichaient toujours en français).
    let title: LocalizedStringResource
    let description: LocalizedStringResource
}

/// Liste des fonctionnalités actuellement réservées aux comptes premium, tenue à jour
/// manuellement en miroir de chaque `PremiumLockedCard`/`premiumUpsellAlert` posé dans l'app.
private let premiumFeatures: [PremiumFeatureInfo] = [
    PremiumFeatureInfo(
        icon: "banknote.fill",
        color: .green,
        title: "Suivi de cote",
        description: "Renseigne le prix payé pour chaque album et compare-le à sa cote Discogs en temps réel pour voir si tes albums ont pris de la valeur."
    ),
    PremiumFeatureInfo(
        icon: "icloud.fill",
        color: .cyan,
        title: "Synchronisation iCloud",
        description: "Synchronise tags, journal d'écoute sur platine, préférences et personnalisations de tri entre tous tes appareils connectés au même compte."
    ),
    PremiumFeatureInfo(
        icon: "arrow.down.circle.fill",
        color: .teal,
        title: "Mode hors ligne",
        description: "Télécharge toute ta collection et les pochettes en haute résolution pour consulter ta liste d'albums même sans réseau (brocante, voyage...)."
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
        description: "Sois averti quand un disque de ta wantlist apparaît à bon prix sur le marketplace Discogs (vérification à l'ouverture de l'app et occasionnellement en arrière-plan, pas en temps réel)."
    ),
    PremiumFeatureInfo(
        icon: "books.vertical.fill",
        color: .purple,
        title: "Où ranger son album",
        description: "Retrouve instantanément où ranger un album dans ton meuble, avec ses voisins immédiats selon ton tri personnalisé."
    ),
    PremiumFeatureInfo(
        icon: "waveform",
        color: .spinlogPink,
        title: "Palmarès d'écoute sur platine",
        description: "Découvre tes albums et artistes les plus écoutés sur ta platine, tes podiums du mois et de l'année dans Statistiques. Les lectures Apple Music ne sont pas comptées."
    ),
    PremiumFeatureInfo(
        icon: "paintpalette.fill",
        color: .spinlogPink,
        title: "Thèmes et palettes de couleurs",
        description: "Personnalise l'ambiance visuelle de l'app selon tes goûts avec 8 palettes exclusives (Bleu Cobalt, Vert Émeraude, Orange Crépuscule, Rouge Rubis, Violet Améthyste, Cuivre & Or...)."
    ),
    PremiumFeatureInfo(
        icon: "tablecells.fill",
        color: .mint,
        title: "Export CSV complet",
        description: "Exporte toute ta discothèque au format tableur (Excel, Numbers, Sheets) avec métadonnées, notes et tags."
    ),
    PremiumFeatureInfo(
        icon: "doc.richtext",
        color: .indigo,
        title: "Déclaration de collection (PDF)",
        description: "Génère un document PDF listant ta collection avec état et prix d'achat, à présenter par exemple à un assureur."
    )
]

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
                        ForEach(Array(premiumFeatures.enumerated()), id: \.element.id) { index, feature in
                            featureRow(feature)
                            if index < premiumFeatures.count - 1 {
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
