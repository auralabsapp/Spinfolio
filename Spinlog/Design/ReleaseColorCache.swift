import SwiftUI

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
