import SwiftUI

/// Page « Comment ça fonctionne ? » du suivi de plus-value : un schéma en trois étapes, un exemple
/// chiffré, l'état réel de la configuration du compte, puis les détails repliés (créer le champ
/// sur Discogs, limites). Le calcul de la cote par état est expliqué dans « Limites ».
struct PurchasePriceHelpSheet: View {
    @State private var authManager = DiscogsAuthManager.shared
    @State private var setup = PurchasePriceSetup.load(for: DiscogsAuthManager.shared.username)
    @State private var safariRequest: SafariViewRequest?

    private var discogsSettingsURL: URL {
        DiscogsConstants.websiteURL.appendingPathComponent("settings/collection")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                schemaSection
                exampleSection
                setupSection
                detailsSection
            }
            .padding()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Suivi de plus-value")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: authManager.username) {
            setup = PurchasePriceSetup.load(for: authManager.username)
        }
        .fullScreenCover(item: $safariRequest) { request in
            SafariView(url: request.url)
        }
    }

    // MARK: - 1. Schéma

    private var schemaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Le principe", icon: "arrow.triangle.branch")

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    sourceCard(symbol: "eurosign.circle.fill", color: .green, title: "Ton prix payé")
                    sourceCard(symbol: "opticaldisc.fill", color: .purple, title: "L'état du disque")
                }
                arrow
                resultCard(symbol: "chart.line.uptrend.xyaxis", color: .blue, title: "La cote Discogs", subtitle: "pour cet état")
                arrow
                resultCard(symbol: "arrow.left.arrow.right.circle.fill", color: Color.gainPositive, title: "Plus-value", subtitle: "cote − prix payé")
            }
            .padding(14)
            .appleMusicGroupedCard()
        }
    }

    private func sourceCard(symbol: String, color: Color, title: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            SettingsIcon(systemName: symbol, backgroundColor: color)
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func resultCard(symbol: String, color: Color, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: symbol, backgroundColor: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private var arrow: some View {
        Image(systemName: "arrow.down")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.appTertiaryText)
            .accessibilityHidden(true)
    }

    // MARK: - 2. Exemple chiffré

    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Un exemple", icon: "lightbulb.fill")

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    figure("Prix payé", value: "20 €")
                    Image(systemName: "minus").foregroundStyle(Color.appTertiaryText)
                    figure("Cote actuelle", value: "35 €")
                    Image(systemName: "equal").foregroundStyle(Color.appTertiaryText)
                    figure("Plus-value", value: "+15 €", color: Color.gainPositive)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Acheté 20 €, cote actuelle 35 €, plus-value de 15 €"))

                Text("Acheté 20 €, état VG+, cote VG+ à 35 € : +15 €.")
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondaryText)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .appleMusicGroupedCard()
        }
    }

    private func figure(_ title: LocalizedStringKey, value: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value)
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.appSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. État de la configuration

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Ta configuration", icon: "checklist")

            VStack(alignment: .leading, spacing: 0) {
                statusRow(
                    title: "Champ prix d'achat",
                    isOK: setup.hasPriceField,
                    okText: "Détecté",
                    missingText: "À créer sur Discogs"
                )
                Divider().overlay(Color.appSeparator).opacity(0.15)
                statusRow(
                    title: "Champ état du disque",
                    isOK: setup.hasConditionField,
                    okText: "Détecté",
                    missingText: "Non détecté : cote moyenne"
                )
                Divider().overlay(Color.appSeparator).opacity(0.15)
                HStack {
                    Text("Devise par défaut")
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Text(verbatim: setup.currency)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .appleMusicGroupedCard()

            if !setup.isComplete {
                Button {
                    // Les sélecteurs de champs sont dans la page « Suivi de plus-value » de Réglages.
                    TabNavigationCoordinator.shared.settingsPath = NavigationPath([SettingsDestination.gainTracking])
                } label: {
                    Label("Choisir mes champs dans Réglages", systemImage: "gearshape")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color.spinlogPink)
            }
        }
    }

    private func statusRow(title: LocalizedStringKey, isOK: Bool, okText: LocalizedStringKey, missingText: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            // Le texte dit l'état en toutes lettres : pas d'information portée par la seule couleur.
            Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isOK ? Color.gainPositive : Color.orange)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 0)
            Text(isOK ? okText : missingText)
                .font(.footnote)
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 4. Détails repliés

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            disclosure(title: "Créer le champ prix d'achat", icon: "plus.square.on.square") {
                Text("Discogs ne crée aucun champ « prix d'achat » par défaut : c'est à toi de le créer une fois, depuis le site discogs.com (pas depuis l'app).")
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Va dans Réglages du compte → onglet Collection sur discogs.com")
                    Text("2. Dans « Champs personnalisés », crée un champ de type texte (ex. nommé « Prix d'achat »)")
                    Text("3. Reviens dans \(AppInfo.name) : le nouveau champ apparaît dans le sélecteur")
                }
                .foregroundStyle(Color.appSecondaryText)

                Button {
                    safariRequest = SafariViewRequest(url: discogsSettingsURL)
                } label: {
                    HStack(spacing: 6) {
                        Text("Ouvrir les réglages de collection Discogs")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
                }

                Text("Si tu as supprimé le champ « Media Condition » fourni par défaut, recrée-le de la même façon mais en type liste déroulante, avec ces valeurs : Mint (M), Near Mint (NM or M-), Very Good Plus (VG+), Very Good (VG), Good Plus (G+), Good (G), Fair (F), Poor (P).")
                    .foregroundStyle(Color.appSecondaryText)
            }

            disclosure(title: "Limites à connaître", icon: "exclamationmark.triangle.fill") {
                Text("Discogs ne donne pas de « prix médian » pour un disque précis, seulement des suggestions par état. \(AppInfo.name) prend celle de l'état déclaré ; sans état, il fait la moyenne de toutes les suggestions : l'estimation est alors moins précise.")
                Text("• Les prix (cote et prix d'achat) n'incluent jamais les frais de port.")
                Text("• Une estimation est recalculée au plus une fois par jour (tout de suite si tu changes l'état déclaré).")
                Text("• Les devises sont converties avec des taux mis à jour toutes les 24 h, approximatifs hors ligne.")
            }
        }
    }

    private func disclosure<Content: View>(title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        // Évalué ici : `DisclosureGroup` garde son contenu, qui ne peut donc pas capturer
        // une fermeture non échappante.
        let body = content()
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                body
            }
            .font(.subheadline)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            SectionEyebrow(title: title, icon: icon)
        }
        .tint(Color.appSecondaryText)
        .padding(14)
        .appleMusicGroupedCard()
    }
}

#Preview {
    NavigationStack {
        PurchasePriceHelpSheet()
    }
}
