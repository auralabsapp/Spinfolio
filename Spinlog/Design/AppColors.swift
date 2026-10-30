import SwiftUI

// Palette de couleurs de l'app (teintes du thème actif, fonds, ombres de pochette) et
// modificateurs visuels partagés qui s'appuient dessus.
//
// Toutes les couleurs dynamiques sont des `UIColor { @Sendable trait in ... }` : sans `@Sendable`,
// la closure hérite de l'isolation MainActor du module, alors que SwiftUI la résout aussi sur son
// fil de rendu asynchrone (`AsyncRenderer`) — l'app s'arrêtait (`dispatch_assert_queue_fail`) à
// l'animation d'apparition du mini-lecteur. Ces closures ne doivent donc lire aucun état MainActor.
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

    /// Texte et icônes sur un fond plein de `spinlogPink` (boutons, pastilles sélectionnées) :
    /// blanc ou presque-noir selon la teinte du thème, pour rester lisible (voir `AccentContrast`).
    static var onAccent: Color {
        Color(uiColor: ThemeManager.shared.currentTheme.onAccentUIColor)
    }

    /// Texte et icônes sur `spinlogPinkButtonGradient`.
    static var onAccentGradient: Color {
        Color(uiColor: ThemeManager.shared.currentTheme.onAccentGradientUIColor)
    }

    /// Texte posé sur le dégradé des boutons et pastilles (compteur des en-têtes de section, capsule des
    /// barres d'index, boutons « En collection » / « En wantlist » de la fiche disque, sélection de
    /// thème, visuels du guide) : en thème clair, la couleur du fond de l'app (choix
    /// esthétique assumé, contraste AA non garanti) ; en sombre, le choix automatique d'`onAccentGradient`.
    static var onAccentGradientLabel: Color {
        let automatic = ThemeManager.shared.currentTheme.onAccentGradientUIColor
        let background = UIColor(appBackground)
        return Color(uiColor: UIColor { @Sendable trait in
            trait.userInterfaceStyle == .dark
                ? automatic.resolvedColor(with: trait)
                : background.resolvedColor(with: trait)
        })
    }

    /// Avertissement (doublon, limite atteinte, accès refusé…) : orange système en sombre, orange
    /// foncé en clair, où l'orange système ne donnait qu'environ 2,2:1 sur fond clair.
    static let appWarning = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? .systemOrange
            : UIColor(red: 0.72, green: 0.32, blue: 0.0, alpha: 1)
    })

    /// Teinte des données hors ligne : sarcelle système en sombre, sarcelle foncée en clair (même
    /// raison que `appWarning`).
    static let appOffline = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? .systemTeal
            : UIColor(red: 0.0, green: 0.42, blue: 0.48, alpha: 1)
    })

    /// Étoiles de note : une seule teinte partout (`.yellow` d'un côté, `.orange` de l'autre avant).
    static let ratingStar = Color.orange

    /// Arrière-plan subtil pour les boutons sélectionnés et badges actifs.
    static var spinlogPinkBadge: Color {
        spinlogPink.opacity(0.12)
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
        // Thème lu ici (fil principal), pas dans la closure : voir l'en-tête du fichier.
        let theme = ThemeManager.shared.currentTheme
        let deep = theme.deepUIColor
        let primary = theme.primaryUIColor
        return Color(uiColor: UIColor { @Sendable trait in
            trait.userInterfaceStyle == .dark
                ? deep.resolvedColor(with: trait)
                : primary.resolvedColor(with: trait)
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
        let primary = ThemeManager.shared.currentTheme.primaryUIColor
        return Color(uiColor: UIColor { @Sendable trait in
            trait.userInterfaceStyle == .dark
                ? primary.resolvedColor(with: trait).withAlphaComponent(0.38)
                : primary.resolvedColor(with: trait).withAlphaComponent(0.22)
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
    /// Haut et bas du dégradé d'en-tête du paywall (or plus profond que `goldAccent`).
    static let goldHeaderTop = Color(red: 0.65, green: 0.36, blue: 0.07)
    static let goldHeaderMiddle = Color(red: 0.85, green: 0.50, blue: 0.12)
    /// Piédestaux du podium (Stats > Écoutes) : or, argent, bronze.
    static let podiumGold = [Color(red: 1.0, green: 0.85, blue: 0.4), Color(red: 0.82, green: 0.62, blue: 0.13)]
    static let podiumSilver = [Color(white: 0.85), Color(white: 0.64)]
    static let podiumBronze = [Color(red: 0.80, green: 0.55, blue: 0.35), Color(red: 0.62, green: 0.40, blue: 0.24)]
    /// Or des TEXTES (prix, mention « PREMIUM », liens dorés) : `goldWarm` ne faisait que 2,6:1
    /// sur le fond clair, sous le seuil de lisibilité (4,5:1). Or plus profond en mode clair
    /// (5,1:1 sur le fond, 4,6:1 sur la carte dorée), `goldWarm` inchangé en mode sombre (6,6:1).
    /// Les fonds, dégradés et ombres dorés gardent les teintes ci-dessus.
    static let goldText = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.88, green: 0.52, blue: 0.12, alpha: 1.0)
            : UIColor(red: 0.62, green: 0.34, blue: 0.04, alpha: 1.0)
    })
    /// Teinte du anneau d'un badge de grade, du plus modeste au plus haut : l'or n'apparaît qu'au
    /// dernier grade, comme signe distinctif. Fixes (identiques en clair et sombre) : ce sont des
    /// ornements, jamais du texte.
    static func gradeTier(_ tier: Int) -> Color {
        switch tier {
        case 0: Color(red: 0.55, green: 0.62, blue: 0.70)
        case 1: Color(red: 0.20, green: 0.66, blue: 0.62)
        case 2: Color(red: 0.25, green: 0.52, blue: 0.90)
        case 3: Color(red: 0.55, green: 0.38, blue: 0.88)
        case 4: Color(red: 0.86, green: 0.30, blue: 0.60)
        case 5: Color(red: 0.92, green: 0.45, blue: 0.22)
        default: goldLight
        }
    }

    /// Étiquette du disque du parcours « Écoute » (celle du parcours « Collection » est `spinlogPink`).
    static let gradeListeningLabel = Color(red: 0.25, green: 0.52, blue: 0.90)

    static var goldButtonGradient: LinearGradient {
        LinearGradient(colors: [goldLight, goldWarm], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Vert plus soutenu et contrasté pour le texte de plus-value (évite le vert fluo clair illisible).
    static let gainPositive = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.80, blue: 0.45, alpha: 1.0)
            : UIColor(red: 0.12, green: 0.52, blue: 0.22, alpha: 1.0)
    })

    /// Disque sous une cloche d'alerte posée sur une jaquette : clair en thème clair, sombre en thème
    /// sombre, pour que les couleurs de la cloche (qui s'éclaircissent en sombre) restent lisibles.
    static let coverBellDisc = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.08, alpha: 0.82)
            : UIColor(white: 1.0, alpha: 0.9)
    })

    /// Orange soutenu du champ « prix d'achat » (nom, pastille « Utilisé pour la plus-value » et ligne
    /// de Réglages). Voisin de `gainFieldCondition`, qui s'en distingue par un orange plus brûlé.
    static let gainFieldPurchase = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.62, blue: 0.20, alpha: 1.0)
            : UIColor(red: 0.88, green: 0.45, blue: 0.04, alpha: 1.0)
    })

    /// Orange brûlé du champ « état du disque » : même famille que `gainFieldPurchase`, plus profond.
    static let gainFieldCondition = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.46, blue: 0.18, alpha: 1.0)
            : UIColor(red: 0.72, green: 0.28, blue: 0.04, alpha: 1.0)
    })

    /// Rouge contrasté et lisible pour le texte de moins-value (corail lumineux en mode sombre, soutenu en mode clair).
    static let gainNegative = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0)
            : UIColor(red: 0.78, green: 0.14, blue: 0.14, alpha: 1.0)
    })

    /// Vert doux et élégant pour les tags (non-flashy, adapté aux modes clair et sombre).
    static let tagForeground = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.78, blue: 0.56, alpha: 1.0)
            : UIColor(red: 0.18, green: 0.50, blue: 0.32, alpha: 1.0)
    })
    /// Arrière-plan subtil vert sauge pour les pastilles de tags.
    static let tagBackground = Color.tagForeground.opacity(0.14)

    /// Luminosité (0 = noir, 1 = blanc) des gris de texte en thème clair, centralisée ici : seule
    /// valeur à modifier pour assombrir/éclaircir `appSecondaryText`/`appTertiaryText` en un point
    /// unique plutôt que de rechercher des `UIColor(white:)` éparpillés dans le fichier.
    nonisolated private static let lightSecondaryTextBrightness: CGFloat = 0.18
    nonisolated private static let lightTertiaryTextBrightness: CGFloat = 0.28
    nonisolated private static let darkTertiaryTextOpacity: CGFloat = 0.55

    /// Gris "secondaire" plus soutenu dans toute l'app : le `.secondary` système est jugé trop
    /// pâle en thème clair. Le thème sombre garde exactement le gris système par défaut, inchangé.
    static let appSecondaryText = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark ? UIColor.secondaryLabel : UIColor(white: lightSecondaryTextBrightness, alpha: 1.0)
    })

    /// Idem pour le niveau "tertiaire" (chevrons de navigation, libellés très discrets) :
    /// le `.tertiary` système (~30% de noir) devient quasi illisible en thème clair.
    static let appTertiaryText = Color(uiColor: UIColor { @Sendable trait in
        // Mode sombre : même teinte que `tertiaryLabel` mais à 55 % au lieu de 30 % d'opacité
        // (5,4:1 au lieu de 2,5:1 sur le fond) — utilisé par de vrais textes (dates, mentions).
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 245.0 / 255.0, alpha: darkTertiaryTextOpacity)
            : UIColor(white: lightTertiaryTextBrightness, alpha: 1.0)
    })

    /// Fond uni de l'app :
    /// - Thème clair : beige vinyle / crème papier (#F7F5F0) chaleureux au lieu du blanc froid.
    /// - Thème sombre : anthracite chaud salon Hi-Fi (#141316, 20/19/22) au lieu du noir froid,
    ///   permettant aux ombres portées des pochettes de conserver tout leur relief et leur profondeur physique.
    static let appBackground = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 20.0 / 255.0, green: 19.0 / 255.0, blue: 22.0 / 255.0, alpha: 1.0)
            : UIColor(red: 247.0 / 255.0, green: 245.0 / 255.0, blue: 240.0 / 255.0, alpha: 1.0)
    })

    /// Trame de fond des en-têtes de section épinglés (Liste/Mosaïque de la Collection et de la Wantlist) :
    /// - En thème clair : dérivée de la teinte du thème de couleur actif (variante claire), légèrement désaturée.
    /// - En thème sombre : capsule feutrée sombre (#201E24) offrant un détachement net et doux sur l'anthracite.
    static var appHeaderBackground: Color {
        let light = ThemeManager.shared.currentTheme.lightUIColor
        return Color(uiColor: UIColor { @Sendable trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 32.0 / 255.0, green: 30.0 / 255.0, blue: 36.0 / 255.0, alpha: 0.92)
            } else {
                let resolvedLight = light
                    .resolvedColor(with: trait)
                return resolvedLight.desaturated(by: 0.7).withAlphaComponent(0.25)
            }
        })
    }

    /// Séparateurs (`Divider()`, traits de `List`) :
    /// - Thème clair : beige doux (#EFECE4).
    /// - Thème sombre : ardoise douce (#26242B, 38/36/43) pour une séparation fine et élégante.
    static let appSeparator = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 38.0 / 255.0, green: 36.0 / 255.0, blue: 43.0 / 255.0, alpha: 1.0)
            : UIColor(red: 239.0 / 255.0, green: 236.0 / 255.0, blue: 228.0 / 255.0, alpha: 1.0)
    })

    /// Les 3 états (repos / sélection active+cochée / sélection active+décochée) de l'ombre de
    /// contact, précalculés une seule fois (`static let`, comme `appSecondaryText` ci-dessus) :
    /// `coverContactShadow` reconstruisait un `UIColor { trait in ... }` neuf à chaque appel, soit
    /// à chaque ligne/cellule visible et à chaque frame pendant le défilement de la Collection —
    /// une allocation répétée inutile puisque seuls ces 3 cas existent réellement.
    private static let coverContactShadowResting = Color(uiColor: UIColor { @Sendable trait in
        UIColor.black.withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.45 : 0.22)
    })
    private static let coverContactShadowSelected = Color(uiColor: UIColor { @Sendable trait in
        let base: CGFloat = trait.userInterfaceStyle == .dark ? 0.45 : 0.22
        return UIColor.black.withAlphaComponent(min(base * 1.35, 1.0))
    })
    private static let coverContactShadowDeselected = Color(uiColor: UIColor { @Sendable trait in
        let base: CGFloat = trait.userInterfaceStyle == .dark ? 0.45 : 0.22
        return UIColor.black.withAlphaComponent(base * 0.55)
    })

    /// Ombre de contact pour les pochettes de vinyle (proche et dense), adaptée dynamiquement en clair et sombre.
    static func coverContactShadow(isSelecting: Bool = false, isSelected: Bool = false) -> Color {
        guard isSelecting else { return coverContactShadowResting }
        return isSelected ? coverContactShadowSelected : coverContactShadowDeselected
    }

    private static let coverAmbientShadowResting = Color(uiColor: UIColor { @Sendable trait in
        UIColor.black.withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.65 : 0.35)
    })
    private static let coverAmbientShadowSelected = Color(uiColor: UIColor { @Sendable trait in
        let base: CGFloat = trait.userInterfaceStyle == .dark ? 0.65 : 0.35
        return UIColor.black.withAlphaComponent(min(base * 1.3, 1.0))
    })
    private static let coverAmbientShadowDeselected = Color(uiColor: UIColor { @Sendable trait in
        let base: CGFloat = trait.userInterfaceStyle == .dark ? 0.65 : 0.35
        return UIColor.black.withAlphaComponent(base * 0.5)
    })

    /// Ombre d'ambiance flottante pour les pochettes de vinyle (large et diffuse), adaptée dynamiquement en clair et sombre.
    static func coverAmbientShadow(isSelecting: Bool = false, isSelected: Bool = false) -> Color {
        guard isSelecting else { return coverAmbientShadowResting }
        return isSelected ? coverAmbientShadowSelected : coverAmbientShadowDeselected
    }

    /// Rouge Apple Music des boutons de lecture : adouci en sombre, plus lumineux en clair pour ne
    /// pas paraître terne sur fond clair.
    static let appleMusicRed = Color(uiColor: UIColor { @Sendable trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 222 / 255, green: 56 / 255, blue: 72 / 255, alpha: 1)
            : UIColor(red: 246 / 255, green: 66 / 255, blue: 84 / 255, alpha: 1)
    })

    /// Part « Autres » / « Non précisé » des graphiques en parts.
    static let chartNeutral = Color(white: 0.55)

    /// Couleurs des parts des graphiques (Stats) : l'accent du thème, puis les teintes de
    /// `ChartPalette` qui s'en distinguent. Mises en cache par thème (lues pour chaque part).
    static var chartPalette: [Color] {
        let theme = ThemeManager.shared.currentTheme
        if let cached = chartPaletteCache[theme] { return cached }
        let palette = [spinlogPink] + ChartPalette.availableHues(accent: theme.primaryUIColor).map(\.color)
        chartPaletteCache[theme] = palette
        return palette
    }

    /// Première teinte disponible (non confondue avec l'accent) parmi `preferred`, pour une part
    /// qui garde une couleur fixe d'un affichage à l'autre (CD, cassette).
    static func chartColor(preferring preferred: [ChartPalette.Hue]) -> Color {
        let available = ChartPalette.availableHues(accent: ThemeManager.shared.currentTheme.primaryUIColor)
        return (preferred.first(where: available.contains) ?? preferred.first)?.color ?? chartNeutral
    }

    private static var chartPaletteCache: [AppColorTheme: [Color]] = [:]
}

private extension UIColor {
    /// Réduit la saturation de la couleur de `amount` (0 = inchangée, 1 = niveaux de gris).
    nonisolated func desaturated(by amount: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation * (1 - amount), brightness: brightness, alpha: alpha)
    }
}

/// Teintes des graphiques en parts, à côté de l'accent du thème. L'accent ouvrait une palette fixe
/// qui contenait aussi un bleu, un vert, un orange et un rouge : avec les thèmes de ces teintes
/// (et déjà en rose, proche du rouge), deux parts voisines se confondaient. Les teintes trop
/// proches de l'accent sont donc écartées. Testé dans `ChartPaletteTests`.
nonisolated enum ChartPalette {
    /// Dans l'ordre d'attribution aux parts.
    enum Hue: CaseIterable, Sendable {
        case violet, blue, teal, orange, yellow, green, red

        var uiColor: UIColor {
            switch self {
            case .violet: UIColor(red: 0.58, green: 0.35, blue: 0.88, alpha: 1)
            case .blue: UIColor(red: 0.28, green: 0.52, blue: 0.95, alpha: 1)
            case .teal: UIColor(red: 0.16, green: 0.72, blue: 0.74, alpha: 1)
            case .orange: UIColor(red: 0.98, green: 0.58, blue: 0.22, alpha: 1)
            case .yellow: UIColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 1)
            case .green: UIColor(red: 0.30, green: 0.78, blue: 0.55, alpha: 1)
            case .red: UIColor(red: 0.88, green: 0.30, blue: 0.45, alpha: 1)
            }
        }

        var color: Color { Color(uiColor: uiColor) }
    }

    /// Écart minimal de teinte avec l'accent (fraction du cercle chromatique, ici 25°).
    static let minimumHueDistance: CGFloat = 25.0 / 360
    /// Sous cette saturation (Ardoise, Espresso), l'accent est presque gris : sa teinte ne se
    /// confond avec aucune part, rien n'est écarté.
    static let minimumAccentSaturation: CGFloat = 0.25

    /// Teintes conservées à côté de `accent`, résolu en mode clair (la teinte varie peu en sombre).
    static func availableHues(accent: UIColor) -> [Hue] {
        let resolved = accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha),
              saturation >= minimumAccentSaturation else {
            return Hue.allCases
        }
        return Hue.allCases.filter { hueDistance($0.uiColor, hue) >= minimumHueDistance }
    }

    /// Distance sur le cercle chromatique (0 à 0,5).
    static func hueDistance(_ color: UIColor, _ otherHue: CGFloat) -> CGFloat {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let distance = abs(hue - otherHue)
        return min(distance, 1 - distance)
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
