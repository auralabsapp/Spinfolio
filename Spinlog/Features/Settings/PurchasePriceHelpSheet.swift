import SwiftUI

/// Écran explicatif du fonctionnement du suivi de cote : détection des champs prix d'achat et
/// état du disque, sélection manuelle, création d'un champ sur Discogs si besoin, et calcul de
/// l'estimation.
struct PurchasePriceHelpSheet: View {
    @State private var showingSafari = false

    private var discogsSettingsURL: URL {
        DiscogsConstants.websiteURL.appendingPathComponent("settings/collection")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                helpSection(
                    title: "Champs prix d'achat et état du disque",
                    icon: "tag.fill"
                ) {
                    Text("\(AppInfo.name) utilise deux champs personnalisés de ta collection Discogs : un pour le prix d'achat, un pour l'état du disque. Chacun est détecté automatiquement par mot-clé dans le nom du champ — « prix », « prix d'achat », « price », « purchase price », « bought for » ou « cost » pour le prix d'achat ; « Media Condition » ou « état du disque » pour l'état (en excluant « Sleeve Condition », qui concerne la pochette).")
                    Text("Le champ état du disque existe par défaut sur Discogs ; le champ prix d'achat, en revanche, doit être créé une fois manuellement (voir ci-dessous).")
                    Text("Si la détection échoue ou que tu préfères un autre champ, choisis-le manuellement dans les sélecteurs ci-dessus.")
                }

                helpSection(
                    title: "Un champ ne correspond pas ?",
                    icon: "plus.square.on.square"
                ) {
                    Text("Discogs ne crée aucun champ « prix d'achat » par défaut : c'est à toi de le créer une fois, depuis le site discogs.com (pas depuis l'app).")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Va dans Réglages du compte → onglet Collection sur discogs.com")
                        Text("2. Dans « Champs personnalisés », crée un champ de type texte (ex. nommé « Prix d'achat »)")
                        Text("3. Reviens dans \(AppInfo.name) : le nouveau champ apparaît dans le sélecteur")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondaryText)

                    Button {
                        showingSafari = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("Ouvrir les réglages de collection Discogs")
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.spinlogPink)
                    }
                    .fullScreenCover(isPresented: $showingSafari) {
                        SafariView(url: discogsSettingsURL)
                    }

                    Text("Si tu as supprimé le champ « Media Condition » fourni par défaut, recrée-le de la même façon mais en type liste déroulante, avec ces valeurs : Mint (M), Near Mint (NM or M-), Very Good Plus (VG+), Very Good (VG), Good Plus (G+), Good (G), Fair (F), Poor (P).")
                }

                helpSection(
                    title: "Calcul de la cote actuelle",
                    icon: "chart.line.uptrend.xyaxis"
                ) {
                    Text("Discogs n'expose pas de « prix médian » pour une release précise, seulement des suggestions de prix par état du disque (Mint, Near Mint, VG+...). \(AppInfo.name) utilise donc l'état renseigné dans le champ état du disque pour sélectionner la suggestion la plus pertinente.")
                    Text("Si aucun état n'est renseigné (ou si l'état déclaré n'a pas de suggestion disponible), \(AppInfo.name) calcule une moyenne de toutes les suggestions disponibles pour cette release — l'estimation est alors moins précise, mais reste affichée.")
                }

                helpSection(
                    title: "Limites à connaître",
                    icon: "exclamationmark.triangle.fill"
                ) {
                    Text("• Les prix affichés (cote et prix d'achat) n'incluent jamais les frais de port, alors qu'ils font partie de la valeur réelle d'une transaction.")
                    Text("• L'estimation d'une release est recalculée au maximum 1 fois par jour (sauf si tu changes l'état déclaré, qui force un recalcul immédiat).")
                    Text("• La conversion de devises utilise des taux en ligne mis à jour toutes les 24h, avec un repli approximatif si hors ligne.")
                }
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
            }
            .padding()
        }
        .navigationTitle("Suivi de cote")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func helpSection<Content: View>(title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: title, icon: icon)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appleMusicGroupedCard()
        }
    }
}

#Preview {
    NavigationStack {
        PurchasePriceHelpSheet()
    }
}
