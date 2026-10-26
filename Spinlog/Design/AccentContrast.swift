import UIKit

/// Choix du texte posé sur un fond plein de la teinte du thème (boutons, pastilles sélectionnées) :
/// blanc, ou presque-noir quand le blanc ne contraste pas assez. En thème sombre, les teintes
/// claires (or, émeraude, turquoise, orange, ardoise) ne donnaient qu'environ 1,6 à 2,3:1 avec du
/// blanc, loin des 4,5:1 recommandés. Calcul WCAG 2 (luminance relative), testé dans
/// `AccentContrastTests`.
nonisolated enum AccentContrast {
    /// Presque-noir plutôt que noir pur, plus doux sur une teinte vive.
    static let darkText = UIColor(white: 0.08, alpha: 1)
    static let lightText = UIColor.white

    /// Luminance relative d'une couleur sRGB (composantes de 0 à 1).
    static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    static func contrastRatio(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    static func luminance(of color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return relativeLuminance(red: red, green: green, blue: blue)
    }

    /// Texte le plus lisible (blanc ou presque-noir) sur ce fond déjà résolu. Pour un dégradé,
    /// passer toutes ses teintes : le texte retenu est celui dont le pire contraste est le meilleur.
    static func text(on backgrounds: UIColor...) -> UIColor {
        let luminances = backgrounds.map(luminance(of:))
        let worstWithLight = luminances.map { contrastRatio($0, luminance(of: lightText)) }.min() ?? 0
        let worstWithDark = luminances.map { contrastRatio($0, luminance(of: darkText)) }.min() ?? 0
        return worstWithLight >= worstWithDark ? lightText : darkText
    }
}
