import SwiftUI

/// Préférence d'apparence de l'app, persistée via `@AppStorage` et appliquée à la racine
/// (`RootTabView`) avec `.preferredColorScheme(_:)`.
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Système"
    case light = "Clair"
    case dark = "Sombre"

    var id: String { rawValue }

    /// Libellé affiché. Le `rawValue` (français) reste la valeur persistée dans les réglages.
    var title: String {
        switch self {
        case .system: return String(localized: "Système")
        case .light: return String(localized: "Clair")
        case .dark: return String(localized: "Sombre")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.righthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

/// Thèmes de couleurs d'accentuation pour l'application.
///
/// Le thème `.signature` (Rose néon / Magenta) est gratuit pour tous les utilisateurs.
/// Les 9 thèmes alternatifs sont réservés aux comptes Premium et couvrent tous les goûts et univers musicaux.
enum AppColorTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case signature = "signature" // Spinlog Rose Néon (défaut)
    case cobalt = "cobalt"       // Bleu Électrique
    case emerald = "emerald"     // Vert Émeraude / Sauge
    case amber = "amber"         // Orange Crépuscule / Sunset
    case ruby = "ruby"           // Rouge Rubis / Carmin
    case velvet = "velvet"       // Violet Améthyste / Améthyste
    case gold = "gold"           // Cuivre & Or Hifi
    case pacific = "pacific"     // Turquoise Pacifique
    case slate = "slate"         // Ardoise Titane
    case espresso = "espresso"   // Marron Espresso / Beige Vinyle Vintage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .signature: return String(localized: "\(AppInfo.name) Signature")
        case .cobalt: return String(localized: "Bleu Électrique")
        case .emerald: return String(localized: "Vert Émeraude")
        case .amber: return String(localized: "Orange Crépuscule")
        case .ruby: return String(localized: "Rouge Rubis")
        case .velvet: return String(localized: "Violet Améthyste")
        case .gold: return String(localized: "Cuivre & Or Hifi")
        case .pacific: return String(localized: "Turquoise Pacifique")
        case .slate: return String(localized: "Ardoise Titane")
        case .espresso: return String(localized: "Marron Espresso")
        }
    }

    var subtitle: String {
        switch self {
        case .signature: return String(localized: "Rose néon vibrant & iconique")
        case .cobalt: return String(localized: "Bleu cobalt moderne & universel")
        case .emerald: return String(localized: "Sauge & forêt apaisant")
        case .amber: return String(localized: "Tangerine chaleureuse & coucher de soleil")
        case .ruby: return String(localized: "Carmin intense & rock")
        case .velvet: return String(localized: "Pourpre feutré & jazz lounge")
        case .gold: return String(localized: "Ambre doré & esprit audiophile")
        case .pacific: return String(localized: "Lagon aéré, frais & estival")
        case .slate: return String(localized: "Monochrome chic & intemporel")
        case .espresso: return String(localized: "Beige vinyle & pochette vintage")
        }
    }

    var iconName: String {
        switch self {
        case .signature: return "sparkles"
        case .cobalt: return "bolt.fill"
        case .emerald: return "leaf.fill"
        case .amber: return "sun.max.fill"
        case .ruby: return "flame.fill"
        case .velvet: return "opticaldisc"
        case .gold: return "crown.fill"
        case .pacific: return "water.waves"
        case .slate: return "circle.lefthalf.striped.horizontal"
        case .espresso: return "cup.and.saucer.fill"
        }
    }

    var isPremiumOnly: Bool {
        self != .signature
    }

    var primaryColor: Color {
        Color(uiColor: primaryUIColor)
    }

    var lightColor: Color {
        Color(uiColor: lightUIColor)
    }

    var deepColor: Color {
        Color(uiColor: deepUIColor)
    }

    var badgeColor: Color {
        primaryColor.opacity(0.12)
    }

    var primaryUIColor: UIColor {
        UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let base: UIColor
            switch self {
            case .signature:
                base = isDark
                    ? UIColor(red: 0.79, green: 0.42, blue: 0.97, alpha: 1.0)
                    : UIColor(red: 0.62, green: 0.24, blue: 0.81, alpha: 1.0)
            case .cobalt:
                base = isDark
                    ? UIColor(red: 0.24, green: 0.58, blue: 1.0, alpha: 1.0)
                    : UIColor(red: 0.04, green: 0.36, blue: 0.82, alpha: 1.0)
            case .emerald:
                base = isDark
                    ? UIColor(red: 0.28, green: 0.82, blue: 0.54, alpha: 1.0)
                    : UIColor(red: 0.06, green: 0.46, blue: 0.28, alpha: 1.0)
            case .amber:
                base = isDark
                    ? UIColor(red: 1.0, green: 0.56, blue: 0.20, alpha: 1.0)
                    : UIColor(red: 0.72, green: 0.32, blue: 0.02, alpha: 1.0)
            case .ruby:
                base = isDark
                    ? UIColor(red: 0.95, green: 0.32, blue: 0.40, alpha: 1.0)
                    : UIColor(red: 0.84, green: 0.16, blue: 0.24, alpha: 1.0)
            case .velvet:
                base = isDark
                    ? UIColor(red: 0.64, green: 0.48, blue: 1.0, alpha: 1.0)
                    : UIColor(red: 0.48, green: 0.30, blue: 0.90, alpha: 1.0)
            case .gold:
                base = isDark
                    ? UIColor(red: 0.95, green: 0.74, blue: 0.32, alpha: 1.0)
                    : UIColor(red: 0.58, green: 0.40, blue: 0.04, alpha: 1.0)
            case .pacific:
                base = isDark
                    ? UIColor(red: 0.22, green: 0.78, blue: 0.86, alpha: 1.0)
                    : UIColor(red: 0.02, green: 0.42, blue: 0.50, alpha: 1.0)
            case .slate:
                base = isDark
                    ? UIColor(red: 0.76, green: 0.80, blue: 0.86, alpha: 1.0)
                    : UIColor(red: 0.35, green: 0.40, blue: 0.48, alpha: 1.0)
            case .espresso:
                base = isDark
                    ? UIColor(red: 0.78, green: 0.60, blue: 0.42, alpha: 1.0)
                    : UIColor(red: 0.45, green: 0.30, blue: 0.18, alpha: 1.0)
            }
            // Les thèmes Premium (hors Signature) adoptent une patine légère — désaturée et
            // assombrie — pour un rendu "pochette vinyle vintage" plutôt qu'une couleur vive
            // sortie d'usine.
            return base.aged()
        }
    }

    var lightUIColor: UIColor {
        UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let base: UIColor
            switch self {
            case .signature:
                base = isDark
                    ? UIColor(red: 0.86, green: 0.54, blue: 0.99, alpha: 1.0)
                    : UIColor(red: 0.82, green: 0.48, blue: 0.96, alpha: 1.0)
            case .cobalt:
                base = isDark
                    ? UIColor(red: 0.42, green: 0.70, blue: 1.0, alpha: 1.0)
                    : UIColor(red: 0.28, green: 0.56, blue: 0.96, alpha: 1.0)
            case .emerald:
                base = isDark
                    ? UIColor(red: 0.40, green: 0.88, blue: 0.64, alpha: 1.0)
                    : UIColor(red: 0.22, green: 0.70, blue: 0.48, alpha: 1.0)
            case .amber:
                base = isDark
                    ? UIColor(red: 1.0, green: 0.68, blue: 0.36, alpha: 1.0)
                    : UIColor(red: 0.96, green: 0.54, blue: 0.18, alpha: 1.0)
            case .ruby:
                base = isDark
                    ? UIColor(red: 1.0, green: 0.46, blue: 0.52, alpha: 1.0)
                    : UIColor(red: 0.90, green: 0.28, blue: 0.36, alpha: 1.0)
            case .velvet:
                base = isDark
                    ? UIColor(red: 0.74, green: 0.62, blue: 1.0, alpha: 1.0)
                    : UIColor(red: 0.60, green: 0.44, blue: 0.95, alpha: 1.0)
            case .gold:
                base = isDark
                    ? UIColor(red: 1.0, green: 0.82, blue: 0.45, alpha: 1.0)
                    : UIColor(red: 0.88, green: 0.65, blue: 0.20, alpha: 1.0)
            case .pacific:
                base = isDark
                    ? UIColor(red: 0.38, green: 0.86, blue: 0.92, alpha: 1.0)
                    : UIColor(red: 0.18, green: 0.66, blue: 0.74, alpha: 1.0)
            case .slate:
                base = isDark
                    ? UIColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1.0)
                    : UIColor(red: 0.46, green: 0.52, blue: 0.60, alpha: 1.0)
            case .espresso:
                base = isDark
                    ? UIColor(red: 0.88, green: 0.74, blue: 0.56, alpha: 1.0)
                    : UIColor(red: 0.72, green: 0.56, blue: 0.38, alpha: 1.0)
            }
            return base.aged()
        }
    }

    var deepUIColor: UIColor {
        UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let base: UIColor
            switch self {
            case .signature:
                base = isDark
                    ? UIColor(red: 0.74, green: 0.36, blue: 0.92, alpha: 1.0)
                    : UIColor(red: 0.68, green: 0.30, blue: 0.86, alpha: 1.0)
            case .cobalt:
                base = isDark
                    ? UIColor(red: 0.16, green: 0.48, blue: 0.92, alpha: 1.0)
                    : UIColor(red: 0.04, green: 0.36, blue: 0.82, alpha: 1.0)
            case .emerald:
                base = isDark
                    ? UIColor(red: 0.20, green: 0.72, blue: 0.46, alpha: 1.0)
                    : UIColor(red: 0.08, green: 0.50, blue: 0.30, alpha: 1.0)
            case .amber:
                base = isDark
                    ? UIColor(red: 0.90, green: 0.46, blue: 0.12, alpha: 1.0)
                    : UIColor(red: 0.80, green: 0.34, blue: 0.02, alpha: 1.0)
            case .ruby:
                base = isDark
                    ? UIColor(red: 0.84, green: 0.22, blue: 0.30, alpha: 1.0)
                    : UIColor(red: 0.72, green: 0.10, blue: 0.18, alpha: 1.0)
            case .velvet:
                base = isDark
                    ? UIColor(red: 0.54, green: 0.38, blue: 0.90, alpha: 1.0)
                    : UIColor(red: 0.40, green: 0.22, blue: 0.80, alpha: 1.0)
            case .gold:
                base = isDark
                    ? UIColor(red: 0.85, green: 0.64, blue: 0.22, alpha: 1.0)
                    : UIColor(red: 0.70, green: 0.46, blue: 0.05, alpha: 1.0)
            case .pacific:
                base = isDark
                    ? UIColor(red: 0.14, green: 0.66, blue: 0.74, alpha: 1.0)
                    : UIColor(red: 0.02, green: 0.46, blue: 0.55, alpha: 1.0)
            case .slate:
                base = isDark
                    ? UIColor(red: 0.66, green: 0.70, blue: 0.76, alpha: 1.0)
                    : UIColor(red: 0.26, green: 0.30, blue: 0.38, alpha: 1.0)
            case .espresso:
                base = isDark
                    ? UIColor(red: 0.62, green: 0.44, blue: 0.26, alpha: 1.0)
                    : UIColor(red: 0.32, green: 0.20, blue: 0.10, alpha: 1.0)
            }
            return base.aged()
        }
    }
}

extension UIColor {
    /// Patine légère : désature et assombrit un peu la couleur, pour un rendu "pochette vinyle
    /// vintage" plutôt qu'une teinte vive sortie d'usine — utilisée par tous les thèmes de
    /// couleur Premium, à l'exception du Signature (rose néon) qui garde son éclat d'origine.
    func aged() -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation * 0.72, brightness: brightness * 0.90, alpha: alpha)
    }
}

/// Gestionnaire réactif du thème de couleur actif dans toute l'application.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private let storageKey = "appColorTheme"
    private let defaults = UserDefaults.standard

    var currentTheme: AppColorTheme {
        didSet {
            defaults.set(currentTheme.rawValue, forKey: storageKey)
            if !isApplyingRemoteTheme {
                CloudSyncEngine.shared.markAppPreferencesDirty()
            }
        }
    }

    /// Empêche `applyRemoteTheme` de redéclencher un envoi vers CloudKit : cette donnée en vient
    /// déjà (même principe que `ShelfPreferencesStore.isApplyingRemoteShelfPreferences`).
    private var isApplyingRemoteTheme = false

    private init() {
        var initialTheme: AppColorTheme = .signature
        if let raw = defaults.string(forKey: storageKey),
           let theme = AppColorTheme(rawValue: raw) {
            initialTheme = theme
        }
        self.currentTheme = initialTheme

        // Écoute automatique de la perte ou modification du statut premium
        NotificationCenter.default.addObserver(
            forName: .premiumStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let isPremium = UserDefaults(suiteName: "group.com.auralabs.Spinlog")?.bool(forKey: "com.spinlog.isPremium")
                ?? UserDefaults.standard.bool(forKey: "com.spinlog.isPremium")
            self.revertToDefaultIfNeeded(isPremium: isPremium)
        }
    }

    /// Change de thème de couleur de manière sécurisée en vérifiant le statut premium si nécessaire.
    @discardableResult
    func selectTheme(_ theme: AppColorTheme, isPremium: Bool) -> Bool {
        if theme.isPremiumOnly && !isPremium {
            return false
        }
        currentTheme = theme
        return true
    }

    /// Si l'utilisateur n'est plus premium et utilise un thème réservé aux membres premium,
    /// on le réinitialise automatiquement sur le thème de base (.signature).
    func revertToDefaultIfNeeded(isPremium: Bool) {
        if currentTheme.isPremiumOnly && !isPremium {
            currentTheme = .signature
        }
    }

    /// Applique un thème reçu d'iCloud. N'écrit qu'en local.
    func applyRemoteTheme(_ theme: AppColorTheme) {
        isApplyingRemoteTheme = true
        currentTheme = theme
        isApplyingRemoteTheme = false
    }
}

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

    /// Teintes pour les boutons et pastilles avec texte blanc.
    static var buttonPinkTop: Color { spinlogPinkLight }
    static var buttonPinkBottom: Color { spinlogPink }

    /// Dégradé pour les boutons d'action sélectionnés (Collection, Wantlist).
    static var spinlogPinkButtonGradient: LinearGradient {
        LinearGradient(
            colors: [buttonPinkTop, buttonPinkBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
    static var spinlogPurpleBadge: Color { spinlogPinkBadge }
    static var spinlogPurpleGradient: LinearGradient { spinlogPinkGradient }
    static var chartPurpleSoftTop: Color { buttonPinkTop }
    static var chartPurpleSoftBottom: Color { buttonPinkBottom }
    static var spinlogPurpleButtonGradient: LinearGradient { spinlogPinkButtonGradient }

    static var spinlogBlue: Color { spinlogPink }
    static var spinlogBlueLight: Color { spinlogPinkLight }
    static var spinlogBlueDeep: Color { spinlogPinkDeep }
    static var spinlogBlueBadge: Color { spinlogPinkBadge }
    static var spinlogBlueGradient: LinearGradient { spinlogPinkGradient }
    static var chartBlueSoftTop: Color { buttonPinkTop }
    static var chartBlueSoftBottom: Color { buttonPinkBottom }
    static var spinlogBlueButtonGradient: LinearGradient { spinlogPinkButtonGradient }

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

    /// Gris "secondaire" plus soutenu dans toute l'app : le `.secondary` système est jugé trop
    /// pâle en thème clair. Le thème sombre garde exactement le gris système par défaut, inchangé.
    static let appSecondaryText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.secondaryLabel : UIColor(white: 0.32, alpha: 1.0)
    })

    /// Idem pour le niveau "tertiaire" (chevrons de navigation, libellés très discrets) :
    /// le `.tertiary` système (~30% de noir) devient quasi illisible en thème clair.
    static let appTertiaryText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.tertiaryLabel : UIColor(white: 0.45, alpha: 1.0)
    })

    /// Fond uni de l'app en thème clair (remplace le blanc système, jugé trop froid) ; le thème
    /// sombre garde le fond système par défaut, inchangé. Volontairement PAS utilisée là où le
    /// fond est calculé à partir de la couleur moyenne de la pochette (`UIColor.infoBackgroundColor`,
    /// fiches artiste/master/release) : ces écrans gardent leur propre teinte dynamique.
    static let appBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.systemBackground
            : UIColor(red: 247.0 / 255.0, green: 245.0 / 255.0, blue: 240.0 / 255.0, alpha: 1.0)
    })

    /// Trame de fond unie des en-têtes de section épinglés (Liste/Mosaïque de la Collection et de
    /// la Wantlist) en thème clair, à la place du flou `.regularMaterial` précédent. Dérivée de la
    /// teinte du thème de couleur actif (variante claire, `lightColor`) plutôt que figée en rose,
    /// pour suivre les thèmes Premium alternatifs (bleu, émeraude, etc.) — légèrement désaturée
    /// pour rester discrète derrière le texte plutôt qu'une teinte trop vive.
    static var appHeaderBackground: Color {
        let resolvedLight = ThemeManager.shared.currentTheme.lightUIColor
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        return Color(uiColor: resolvedLight.desaturated(by: 0.7)).opacity(0.25)
    }

    /// Séparateurs (`Divider()`, traits de `List`) en thème clair ; le thème sombre garde le gris
    /// système par défaut, inchangé.
    static let appSeparator = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.separator
            : UIColor(red: 239.0 / 255.0, green: 236.0 / 255.0, blue: 228.0 / 255.0, alpha: 1.0)
    })
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
    /// Trame de fond des en-têtes de section épinglés (Liste/Mosaïque) : teinte unie
    /// (`Color.appHeaderBackground`) en thème clair, flou `.regularMaterial` system inchangé en
    /// thème sombre — `AnyShapeStyle` efface la différence de type entre les deux styles.
    static func libraryHeaderBackground(for colorScheme: ColorScheme) -> AnyShapeStyle {
        colorScheme == .dark ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.appHeaderBackground)
    }
}

extension View {
    /// Rendu discret et moderne style Apple Music pour les sections groupées
    /// (fond translucide très subtil sans bordure agressive, fondant naturellement dans la couleur d'ambiance)
    func appleMusicGroupedCard(cornerRadius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

extension UIColor {
    /// Adapte la couleur moyenne d'une pochette pour créer un arrière-plan d'informations immersif,
    /// vibrant et moderne (style Apple Music), compatible avec les modes clair et sombre.
    func infoBackgroundColor(for colorScheme: ColorScheme) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        if self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            if colorScheme == .dark {
                // Mode sombre : ambiance lumineuse et profonde style Apple Music
                return Color(hue: hue, saturation: min(saturation * 0.8, 0.65), brightness: 0.12)
            } else {
                // Mode clair : teinte pastel très claire et lumineuse assurant un contraste optimal
                return Color(hue: hue, saturation: min(saturation * 0.12, 0.08), brightness: 0.98)
            }
        }
        return colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.98)
    }
}

/// Cache mémoire haute performance pour les couleurs dominantes/moyennes des releases
@MainActor
final class ReleaseColorCache {
    static let shared = ReleaseColorCache()

    private var colorsByReleaseId: [Int: UIColor] = [:]
    private var colorsByURL: [String: UIColor] = [:]

    func color(forReleaseId id: Int) -> UIColor? {
        colorsByReleaseId[id]
    }

    func color(forURL url: String) -> UIColor? {
        colorsByURL[url]
    }

    func register(color: UIColor, forReleaseId id: Int? = nil, url: String? = nil) {
        if let id {
            colorsByReleaseId[id] = color
        }
        if let url {
            colorsByURL[url] = color
        }
    }
}
