import Testing
import UIKit
@testable import Spinlog

/// Palette des graphiques en parts : aucune teinte confondue avec l'accent du thème.
@MainActor
struct ChartPaletteTests {
    @Test func blueAccentDropsBlue() {
        let hues = ChartPalette.availableHues(accent: AppColorTheme.cobalt.primaryUIColor)
        #expect(!hues.contains(.blue))
    }

    @Test func greenAccentDropsGreen() {
        let hues = ChartPalette.availableHues(accent: AppColorTheme.emerald.primaryUIColor)
        #expect(!hues.contains(.green))
    }

    @Test func orangeAccentDropsOrange() {
        let hues = ChartPalette.availableHues(accent: AppColorTheme.amber.primaryUIColor)
        #expect(!hues.contains(.orange))
    }

    @Test func greyAccentKeepsEveryHue() {
        #expect(ChartPalette.availableHues(accent: .gray) == ChartPalette.Hue.allCases)
    }

    /// Le cercle chromatique boucle : 350° et 10° ne sont qu'à 20° l'un de l'autre.
    @Test func hueDistanceWrapsAround() {
        let nearRed = UIColor(hue: 350.0 / 360, saturation: 1, brightness: 1, alpha: 1)
        let distance = ChartPalette.hueDistance(nearRed, 10.0 / 360)
        #expect(abs(distance - 20.0 / 360) < 0.001)
    }

    /// Dans chaque thème, il reste assez de teintes pour les parts (accent + au moins 5).
    @Test(arguments: AppColorTheme.allCases)
    func everyThemeKeepsEnoughHues(theme: AppColorTheme) {
        let hues = ChartPalette.availableHues(accent: theme.primaryUIColor)
        #expect(hues.count >= 5)
        let accent = theme.primaryUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        accent.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation >= ChartPalette.minimumAccentSaturation {
            for kept in hues {
                #expect(ChartPalette.hueDistance(kept.uiColor, hue) >= ChartPalette.minimumHueDistance)
            }
        }
    }
}
