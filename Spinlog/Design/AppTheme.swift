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
            // Patine vinyle vintage : appliquée en mode clair comme en mode sombre,
            // avec un effet adouci en mode sombre pour préserver l'éclat des couleurs.
            return base.aged(isDark: isDark)
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
            return base.aged(isDark: isDark)
        }
    }

    var deepUIColor: UIColor {
        UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let base: UIColor
            switch self {
            case .signature:
                base = isDark
                    ? UIColor(red: 0.52, green: 0.18, blue: 0.72, alpha: 1.0)
                    : UIColor(red: 0.68, green: 0.30, blue: 0.86, alpha: 1.0)
            case .cobalt:
                base = isDark
                    ? UIColor(red: 0.08, green: 0.34, blue: 0.78, alpha: 1.0)
                    : UIColor(red: 0.04, green: 0.36, blue: 0.82, alpha: 1.0)
            case .emerald:
                base = isDark
                    ? UIColor(red: 0.10, green: 0.52, blue: 0.32, alpha: 1.0)
                    : UIColor(red: 0.08, green: 0.50, blue: 0.30, alpha: 1.0)
            case .amber:
                base = isDark
                    ? UIColor(red: 0.75, green: 0.32, blue: 0.06, alpha: 1.0)
                    : UIColor(red: 0.80, green: 0.34, blue: 0.02, alpha: 1.0)
            case .ruby:
                base = isDark
                    ? UIColor(red: 0.68, green: 0.14, blue: 0.22, alpha: 1.0)
                    : UIColor(red: 0.72, green: 0.10, blue: 0.18, alpha: 1.0)
            case .velvet:
                base = isDark
                    ? UIColor(red: 0.38, green: 0.22, blue: 0.72, alpha: 1.0)
                    : UIColor(red: 0.40, green: 0.22, blue: 0.80, alpha: 1.0)
            case .gold:
                base = isDark
                    ? UIColor(red: 0.65, green: 0.42, blue: 0.06, alpha: 1.0)
                    : UIColor(red: 0.70, green: 0.46, blue: 0.05, alpha: 1.0)
            case .pacific:
                base = isDark
                    ? UIColor(red: 0.04, green: 0.46, blue: 0.54, alpha: 1.0)
                    : UIColor(red: 0.02, green: 0.46, blue: 0.55, alpha: 1.0)
            case .slate:
                base = isDark
                    ? UIColor(red: 0.32, green: 0.36, blue: 0.44, alpha: 1.0)
                    : UIColor(red: 0.26, green: 0.30, blue: 0.38, alpha: 1.0)
            case .espresso:
                base = isDark
                    ? UIColor(red: 0.38, green: 0.22, blue: 0.12, alpha: 1.0)
                    : UIColor(red: 0.32, green: 0.20, blue: 0.10, alpha: 1.0)
            }
            return base.aged(isDark: isDark)
        }
    }
}

extension UIColor {
    /// Patine vinyle vintage :
    /// - En thème clair : désature (-28%) et assombrit (-10%) pour un rendu "pochette vinyle d'époque" avec bon contraste sur fond crème/beige.
    /// - En thème sombre : effet fortement diminué (légère désaturation de -8% seulement, luminosité préservée à 98%)
    ///   pour éviter tout aspect terne, délavé ou fade sur le fond anthracite chaud (#141316).
    func aged(isDark: Bool = false) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        if isDark {
            return UIColor(hue: hue, saturation: saturation * 0.92, brightness: min(brightness * 0.98, 1.0), alpha: alpha)
        } else {
            return UIColor(hue: hue, saturation: saturation * 0.72, brightness: brightness * 0.90, alpha: alpha)
        }
    }
}
