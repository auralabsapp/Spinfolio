import SwiftUI
import UIKit

/// Applique la police New York (serif) au gros titre de navigation de l'écran courant, sans
/// affecter les autres onglets : contrairement à `UINavigationBar.appearance()` (global), on
/// configure directement le `UINavigationBar` du `UINavigationController` qui héberge cet écran —
/// même principe que `DisableContentPopGesture`.
private struct SerifNavigationTitleConfigurator: UIViewControllerRepresentable {
    /// Dernière configuration appliquée. Réécrire les apparences d'une barre de navigation à
    /// chaque mise à jour de la vue (ce qui arrivait pendant le défilement de la Collection)
    /// peut, sur certaines versions d'iOS 26, la faire repasser en grand titre et rompre son
    /// suivi du défilement : on n'applique donc qu'une fois par barre, et de nouveau seulement si
    /// la taille de texte change (la police du titre en dépend).
    final class Coordinator {
        weak var configuredBar: UINavigationBar?
        var configuredDynamicTypeSize: DynamicTypeSize?
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let coordinator = context.coordinator
        let dynamicTypeSize = dynamicTypeSize
        DispatchQueue.main.async {
            guard let navigationBar = uiViewController.navigationController?.navigationBar else { return }
            guard coordinator.configuredBar !== navigationBar
                || coordinator.configuredDynamicTypeSize != dynamicTypeSize else { return }
            Self.applySerifLargeTitle(to: navigationBar)
            coordinator.configuredBar = navigationBar
            coordinator.configuredDynamicTypeSize = dynamicTypeSize
        }
    }

    private static func applySerifLargeTitle(to navigationBar: UINavigationBar) {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withDesign(.serif)
            ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        let serifLargeTitleFont = UIFont(descriptor: descriptor, size: 0)

        let titleColor = UIColor { @Sendable trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 242.0 / 255.0, green: 239.0 / 255.0, blue: 235.0 / 255.0, alpha: 1.0)
                : UIColor.label
        }

        let appearance = navigationBar.standardAppearance.copy()
        var largeTitleAttributes = appearance.largeTitleTextAttributes
        largeTitleAttributes[.font] = serifLargeTitleFont
        largeTitleAttributes[.foregroundColor] = titleColor
        appearance.largeTitleTextAttributes = largeTitleAttributes

        var titleAttributes = appearance.titleTextAttributes
        titleAttributes[.foregroundColor] = titleColor
        appearance.titleTextAttributes = titleAttributes

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }
}

extension View {
    /// Affiche le gros titre de navigation de cet écran en New York (serif) plutôt que la police
    /// système, sans affecter les autres onglets (voir `SerifNavigationTitleConfigurator`).
    func serifNavigationTitle() -> some View {
        background(SerifNavigationTitleConfigurator())
    }
}
