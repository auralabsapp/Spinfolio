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
        /// Réparations de police déjà faites sur cette barre (plafonnées : voir `configureIfNeeded`).
        var repairs = 0
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = ConfiguratorViewController()
        let coordinator = context.coordinator
        controller.onAppearance = { [weak controller] in
            guard let controller else { return }
            Self.configureIfNeeded(controller, coordinator: coordinator, dynamicTypeSize: controller.latestDynamicTypeSize)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let coordinator = context.coordinator
        let dynamicTypeSize = dynamicTypeSize
        (uiViewController as? ConfiguratorViewController)?.latestDynamicTypeSize = dynamicTypeSize
        DispatchQueue.main.async {
            Self.configureIfNeeded(uiViewController, coordinator: coordinator, dynamicTypeSize: dynamicTypeSize)
        }
    }

    /// Applique la police serif si la barre est nouvelle, si la taille de texte a changé, ou si la barre
    /// a perdu la police (réécrite depuis par UIKit/SwiftUI, par exemple quand la pile est créée alors
    /// que l'onglet n'est pas affiché et mise en place à son premier affichage). Sans réécriture
    /// quand tout est en ordre : voir le commentaire du `Coordinator`.
    private static func configureIfNeeded(
        _ viewController: UIViewController,
        coordinator: Coordinator,
        dynamicTypeSize: DynamicTypeSize
    ) {
        guard let navigationBar = viewController.navigationController?.navigationBar else { return }
        let isNewBar = coordinator.configuredBar !== navigationBar
        let needsRepair = !isNewBar && !hasSerifLargeTitle(navigationBar)
        guard isNewBar || coordinator.configuredDynamicTypeSize != dynamicTypeSize || needsRepair else { return }
        // Plafond : réécrire sans fin les apparences d'une barre qui les réécrit aussi rompait son suivi
        // du défilement (voir le commentaire du `Coordinator`).
        if needsRepair {
            guard coordinator.repairs < 3 else { return }
            coordinator.repairs += 1
        } else if isNewBar {
            coordinator.repairs = 0
        }
        applySerifLargeTitle(to: navigationBar)
        coordinator.configuredBar = navigationBar
        coordinator.configuredDynamicTypeSize = dynamicTypeSize
    }

    private static func hasSerifLargeTitle(_ navigationBar: UINavigationBar) -> Bool {
        let appearances = [navigationBar.standardAppearance, navigationBar.scrollEdgeAppearance].compactMap { $0 }
        let expected = serifLargeTitleFont
        return appearances.allSatisfy { appearance in
            guard let font = appearance.largeTitleTextAttributes[.font] as? UIFont else { return false }
            return font.fontName == expected.fontName && abs(font.pointSize - expected.pointSize) < 0.5
        }
    }

    private static var serifLargeTitleFont: UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withDesign(.serif)
            ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        return UIFont(descriptor: descriptor, size: 0)
    }

    private static func applySerifLargeTitle(to navigationBar: UINavigationBar) {
        let serifLargeTitleFont = Self.serifLargeTitleFont

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

/// Contrôleur de vue du configurateur : prévient aussi quand l'écran apparaît et se met en page, pas
/// seulement quand SwiftUI met la représentation à jour, pour rattraper une barre dont la police a été
/// réécrite après la première application.
private final class ConfiguratorViewController: UIViewController {
    var onAppearance: (() -> Void)?
    var latestDynamicTypeSize: DynamicTypeSize = .large

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppearance?()
        // UIKit peut réécrire l'apparence de la barre peu après l'affichage : on revérifie juste après.
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.onAppearance?()
            }
        }
    }
}

extension View {
    /// Affiche le gros titre de navigation de cet écran en New York (serif) plutôt que la police
    /// système, sans affecter les autres onglets (voir `SerifNavigationTitleConfigurator`).
    func serifNavigationTitle() -> some View {
        background(SerifNavigationTitleConfigurator())
    }
}
