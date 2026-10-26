import Testing
import UIKit
@testable import Spinlog

/// Texte posé sur la teinte du thème : blanc ou presque-noir, le plus lisible des deux.
@MainActor
struct AccentContrastTests {
    private static let light = UITraitCollection(userInterfaceStyle: .light)
    private static let dark = UITraitCollection(userInterfaceStyle: .dark)

    @Test func contrastBetweenBlackAndWhiteIsMaximal() {
        let ratio = AccentContrast.contrastRatio(
            AccentContrast.luminance(of: .white),
            AccentContrast.luminance(of: .black)
        )
        #expect(abs(ratio - 21) < 0.01)
    }

    @Test func picksDarkTextOnLightBackground() {
        #expect(AccentContrast.text(on: .white) == AccentContrast.darkText)
        #expect(AccentContrast.text(on: UIColor(red: 0.98, green: 0.78, blue: 0.28, alpha: 1)) == AccentContrast.darkText)
    }

    @Test func picksWhiteTextOnDarkBackground() {
        #expect(AccentContrast.text(on: .black) == AccentContrast.lightText)
        #expect(AccentContrast.text(on: UIColor(red: 0.10, green: 0.20, blue: 0.55, alpha: 1)) == AccentContrast.lightText)
    }

    /// Pour un dégradé, le pire contraste compte : une teinte très claire suffit à imposer le noir.
    @Test func gradientUsesWorstContrast() {
        let text = AccentContrast.text(on: .black, .white, .white)
        #expect(text == AccentContrast.darkText)
    }

    /// Dans les 10 thèmes, clair comme sombre, le texte retenu sur l'accent atteint au moins 4,5:1
    /// (seuil WCAG du texte courant) — le blanc fixe descendait à environ 1,6:1.
    @Test(arguments: AppColorTheme.allCases)
    func onAccentIsReadableInEveryTheme(theme: AppColorTheme) {
        for trait in [Self.light, Self.dark] {
            let accent = theme.primaryUIColor.resolvedColor(with: trait)
            let text = theme.onAccentUIColor.resolvedColor(with: trait)
            let ratio = AccentContrast.contrastRatio(
                AccentContrast.luminance(of: accent),
                AccentContrast.luminance(of: text)
            )
            #expect(ratio >= 4.5, "\(theme.rawValue) \(trait.userInterfaceStyle == .dark ? "sombre" : "clair") : \(ratio)")
        }
    }
}
