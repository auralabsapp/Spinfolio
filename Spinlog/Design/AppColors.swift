import SwiftUI

// Palette de couleurs de l'app (teintes du thème actif, fonds, ombres de pochette) et
// modificateurs visuels partagés qui s'appuient dessus.
extension Color {
    /// Teinte signature ou personnalisée selon le thème actif dans l'application.
    static var spinlogPink: Color {
        ThemeManager.shared.currentTheme.primaryColor
    }

    /// Teinte plus claire et aérienne pour le sommet des dégradés.
    static var spinlogPinkLight: Color {
        ThemeManager.shared.currentTheme.lightColor
    }

    /// Teinte profonde pour la base des dégradés de boutons.
    static var spinlogPinkDeep: Color {
        ThemeManager.shared.currentTheme.deepColor
    }

    /// Arrière-plan subtil pour les boutons sélectionnés et badges actifs.
    static var spinlogPinkBadge: Color {
        spinlogPink.opacity(0.12)
    }

    /// Dégradé signature pour les visualisations.
    static var spinlogPinkGradient: LinearGradient {
        LinearGradient(
            colors: [spinlogPinkLight, spinlogPink, spinlogPinkDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Sommet des barres de graphique.
    static var chartPinkSoftTop: Color { spinlogPinkLight }

    /// Base des barres de graphique avec fondu plus marqué.
    static var chartPinkSoftBottom: Color { spinlogPink.opacity(0.20) }

    /// Teinte haute (sommet) pour les boutons d'action et pastilles à dégradé.
    static var buttonPinkTop: Color { spinlogPinkLight }

    /// Teinte basse (base) pour les boutons d'action et pastilles à dégradé :
    /// - En clair : teinte primaire (déjà soutenue).
    /// - En sombre : teinte profonde `deepColor` pour garantir un dégradé lumineux, tactile
    ///   et richement contrasté, évitant tout aspect plat ou uniforme.
    static var buttonPinkBottom: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? ThemeManager.shared.currentTheme.deepUIColor.resolvedColor(with: trait)
                : ThemeManager.shared.currentTheme.primaryUIColor.resolvedColor(with: trait)
        })
    }

    /// Dégradé pour les boutons d'action sélectionnés (Collection, Wantlist).
    static var spinlogPinkButtonGradient: LinearGradient {
        LinearGradient(
            colors: [buttonPinkTop, buttonPinkBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Ombre portée / halo de relief pour les boutons actifs à dégradé :
    /// - En clair : ombre portée teintée douce sous le bouton (22% d'opacité).
    /// - En sombre : halo d'ambiance coloré (38% d'opacité) qui détache la capsule du fond sombre.
    static var buttonPinkShadow: Color {
        Color(uiColor: UIColor { trait in
            let theme = ThemeManager.shared.currentTheme
            return trait.userInterfaceStyle == .dark
                ? theme.primaryUIColor.resolvedColor(with: trait).withAlphaComponent(0.38)
                : theme.primaryUIColor.resolvedColor(with: trait).withAlphaComponent(0.22)
        })
    }

    /// Dégradé accentué pour l'histogramme (sommet lumineux et base douce en fondu).
    static var spinlogChartGradient: LinearGradient {
        LinearGradient(
            colors: [chartPinkSoftTop, chartPinkSoftBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Dégradé estompé pour les barres non sélectionnées.
    static var spinlogChartDimmedGradient: LinearGradient {
        LinearGradient(
            colors: [spinlogPink.opacity(0.22), spinlogPink.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Aliases de rétro-compatibilité
    static var spinlogPurple: Color { spinlogPink }
    static var spinlogPurpleLight: Color { spinlogPinkLight }
    static var spinlogPurpleDeep: Color { spinlogPinkDeep }

    // MARK: - Palette "Or Hifi / Ambre Collector" (habillage premium)
    //
    // Avant cette centralisation, `SpinlogPaywallView`, `SettingsPremiumHeroBanner` et
    // `PremiumGate` retapaient chacun les mêmes valeurs RGB indépendamment — avec une divergence
    // passée inaperçue (opacité du badge à 0.18 dans un fichier, 0.16 dans les deux autres),
    // unifiée ici à 0.16.
    static let goldAccent = Color(red: 0.95, green: 0.68, blue: 0.18)
    static let goldWarm = Color(red: 0.88, green: 0.52, blue: 0.12)
    static let goldDeep = Color(red: 0.72, green: 0.40, blue: 0.08)
    static let goldLight = Color(red: 0.98, green: 0.78, blue: 0.28)
    static let goldBadgeBg = goldAccent.opacity(0.16)
    static var goldButtonGradient: LinearGradient {
        LinearGradient(colors: [goldLight, goldWarm], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Vert plus soutenu et contrasté pour le texte de plus-value (évite le vert fluo clair illisible).
    static let gainPositive = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.80, blue: 0.45, alpha: 1.0)
            : UIColor(red: 0.12, green: 0.52, blue: 0.22, alpha: 1.0)
    })

    /// Rouge contrasté et lisible pour le texte de moins-value (corail lumineux en mode sombre, soutenu en mode clair).
    static let gainNegative = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0)
            : UIColor(red: 0.78, green: 0.14, blue: 0.14, alpha: 1.0)
    })

    /// Vert doux et élégant pour les tags (non-flashy, adapté aux modes clair et sombre).
    static let tagForeground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.78, blue: 0.56, alpha: 1.0)
            : UIColor(red: 0.18, green: 0.50, blue: 0.32, alpha: 1.0)
    })
    /// Arrière-plan subtil vert sauge pour les pastilles de tags.
    static let tagBackground = Color.tagForeground.opacity(0.14)

    /// Luminosité (0 = noir, 1 = blanc) des gris de texte en thème clair, centralisée ici : seule
    /// valeur à modifier pour assombrir/éclaircir `appSecondaryText`/`appTertiaryText` en un point
    /// unique plutôt que de rechercher des `UIColor(white:)` éparpillés dans le fichier.
    private static let lightSecondaryTextBrightness: CGFloat = 0.18
    private static let lightTertiaryTextBrightness: CGFloat = 0.28

    /// Gris "secondaire" plus soutenu dans toute l'app : le `.secondary` système est jugé trop
    /// pâle en thème clair. Le thème sombre garde exactement le gris système par défaut, inchangé.
    static let appSecondaryText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.secondaryLabel : UIColor(white: lightSecondaryTextBrightness, alpha: 1.0)
    })

    /// Idem pour le niveau "tertiaire" (chevrons de navigation, libellés très discrets) :
    /// le `.tertiary` système (~30% de noir) devient quasi illisible en thème clair.
    static let appTertiaryText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.tertiaryLabel : UIColor(white: lightTertiaryTextBrightness, alpha: 1.0)
    })

    /// Fond uni de l'app :
    /// - Thème clair : beige vinyle / crème papier (#F7F5F0) chaleureux au lieu du blanc froid.
    /// - Thème sombre : anthracite chaud salon Hi-Fi (#141316, 20/19/22) au lieu du noir froid,
    ///   permettant aux ombres portées des pochettes de conserver tout leur relief et leur profondeur physique.
    static let appBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 20.0 / 255.0, green: 19.0 / 255.0, blue: 22.0 / 255.0, alpha: 1.0)
            : UIColor(red: 247.0 / 255.0, green: 245.0 / 255.0, blue: 240.0 / 255.0, alpha: 1.0)
    })

    /// Trame de fond des en-têtes de section épinglés (Liste/Mosaïque de la Collection et de la Wantlist) :
    /// - En thème clair : dérivée de la teinte du thème de couleur actif (variante claire), légèrement désaturée.
    /// - En thème sombre : capsule feutrée sombre (#201E24) offrant un détachement net et doux sur l'anthracite.
    static var appHeaderBackground: Color {
        Color(uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 32.0 / 255.0, green: 30.0 / 255.0, blue: 36.0 / 255.0, alpha: 0.92)
            } else {
                let resolvedLight = ThemeManager.shared.currentTheme.lightUIColor
                    .resolvedColor(with: trait)
                return resolvedLight.desaturated(by: 0.7).withAlphaComponent(0.25)
            }
        })
    }

    /// Séparateurs (`Divider()`, traits de `List`) :
    /// - Thème clair : beige doux (#EFECE4).
    /// - Thème sombre : ardoise douce (#26242B, 38/36/43) pour une séparation fine et élégante.
    static let appSeparator = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 38.0 / 255.0, green: 36.0 / 255.0, blue: 43.0 / 255.0, alpha: 1.0)
            : UIColor(red: 239.0 / 255.0, green: 236.0 / 255.0, blue: 228.0 / 255.0, alpha: 1.0)
    })

    /// Les 3 états (repos / sélection active+cochée / sélection active+décochée) de l'ombre de
    /// contact, précalculés une seule fois (`static let`, comme `appSecondaryText` ci-dessus) :
    /// `coverContactShadow` reconstruisait un `UIColor { trait in ... }` neuf à chaque appel, soit
    /// à chaque ligne/cellule visible et à chaque frame pendant le défilement de la Collection —
    /// une allocation répétée inutile puisque seuls ces 3 cas existent réellement.
    private static let coverContactShadowResting = Color(uiColor: UIColor { trait in
        UIColor.black.withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.45 : 0.22)
    })
    private static let coverContactShadowSelected = Color(uiColor: UIColor { trait in
        let base: CGFloat = trait.userInterfaceStyle == .dark ? 0.45 : 0.22
        return UIColor.black.withAlphaComponent(min(base * 1.35, 1.0))
    })
    private static let coverContactShadowDeselected = Color(uiColor: UIColor { trait in
        let base: CGFloat = trait.userInterfaceStyle == .dark ? 0.45 : 0.22
        return UIColor.black.withAlphaComponent(base * 0.55)
    })

    /// Ombre de contact pour les pochettes de vinyle (proche et dense), adaptée dynamiquement en clair et sombre.
    static func coverContactShadow(isSelecting: Bool = false, isSelected: Bool = false) -> Color {
        guard isSelecting else { return coverContactShadowResting }
        return isSelected ? coverContactShadowSelected : coverContactShadowDeselected
    }

    private static let coverAmbientShadowResting = Color(uiColor: UIColor { trait in
        UIColor.black.withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.65 : 0.35)
    })
    private static let coverAmbientShadowSelected = Color(uiColor: UIColor { trait in
        let base: CGFloat = trait.userInterfaceStyle == .dark ? 0.65 : 0.35
        return UIColor.black.withAlphaComponent(min(base * 1.3, 1.0))
    })
    private static let coverAmbientShadowDeselected = Color(uiColor: UIColor { trait in
        let base: CGFloat = trait.userInterfaceStyle == .dark ? 0.65 : 0.35
        return UIColor.black.withAlphaComponent(base * 0.5)
    })

    /// Ombre d'ambiance flottante pour les pochettes de vinyle (large et diffuse), adaptée dynamiquement en clair et sombre.
    static func coverAmbientShadow(isSelecting: Bool = false, isSelected: Bool = false) -> Color {
        guard isSelecting else { return coverAmbientShadowResting }
        return isSelected ? coverAmbientShadowSelected : coverAmbientShadowDeselected
    }
}

private extension UIColor {
    /// Réduit la saturation de la couleur de `amount` (0 = inchangée, 1 = niveaux de gris).
    func desaturated(by amount: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation * (1 - amount), brightness: brightness, alpha: alpha)
    }
}

extension ShapeStyle where Self == AnyShapeStyle {
    /// Trame de fond des en-têtes de section épinglés (Liste/Mosaïque) :
    /// Applique `Color.appHeaderBackground` de manière cohérente en thèmes clair et sombre.
    static func libraryHeaderBackground(for colorScheme: ColorScheme) -> AnyShapeStyle {
        AnyShapeStyle(Color.appHeaderBackground)
    }
}

extension View {
    /// Applique les deux ombres de pochette vinyle (contact + ambiance) adaptées dynamiquement
    /// aux thèmes clair et sombre pour préserver le relief physique de l'objet vinyle.
    func vinylCoverShadow(isSelecting: Bool = false, isSelected: Bool = false) -> some View {
        self
            .shadow(color: .coverContactShadow(isSelecting: isSelecting, isSelected: isSelected), radius: 5, x: 0, y: 3)
            .shadow(color: .coverAmbientShadow(isSelecting: isSelecting, isSelected: isSelected), radius: 16, x: 0, y: 10)
    }

    /// Rendu discret et moderne style Apple Music pour les sections groupées
    /// (fond translucide très subtil sans bordure agressive, fondant naturellement dans la couleur d'ambiance)
    func appleMusicGroupedCard(cornerRadius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
