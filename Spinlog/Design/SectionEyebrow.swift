import SwiftUI

/// Titre de section ("eyebrow"), avec accent rose signature Spinlog et petites majuscules.
/// `.section` marque une section de premier niveau ; `.subsection` marque un sous-titre
/// imbriqué dans une section `.section` déjà affichée au-dessus (ex. "Titres" à l'intérieur
/// de "Infos Discogs sur la release"), avec un poids visuel plus discret pour ne pas être
/// confondu avec le titre de la section parente.
struct SectionEyebrow: View {
    enum Style {
        case section
        case subsection
    }

    let title: LocalizedStringKey
    var icon: String? = nil
    var style: Style = .section
    /// Section d'une fonction Premium : étiquette dorée pendant l'aperçu de la démo
    /// (`DemoPremiumBadge`), invisible sinon.
    var isPremiumFeature = false

    var body: some View {
        switch style {
        case .section:
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.spinlogPink)
                }

                Text(title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.spinlogPink)
                    .kerning(0.5)
                    .textCase(.uppercase)

                if isPremiumFeature {
                    DemoPremiumBadge()
                }
            }
        case .subsection:
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appSecondaryText)
                    .kerning(0.3)
                    .textCase(.uppercase)
            }
        }
    }
}
