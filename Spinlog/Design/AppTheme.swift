import SwiftUI

/// Préférence d'apparence de l'app, persistée via `@AppStorage` et appliquée à la racine
/// (`RootTabView`) avec `.preferredColorScheme(_:)`.
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Système"
    case light = "Clair"
    case dark = "Sombre"

    var id: String { rawValue }

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
