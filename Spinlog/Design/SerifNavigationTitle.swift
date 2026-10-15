import SwiftUI
import UIKit

/// Applique la police New York (serif) au gros titre de navigation de l'écran courant, sans
/// affecter les autres onglets : contrairement à `UINavigationBar.appearance()` (global), on
/// configure directement le `UINavigationBar` du `UINavigationController` qui héberge cet écran —
/// même principe que `DisableContentPopGesture`.
private struct SerifNavigationTitleConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let navigationBar = uiViewController.navigationController?.navigationBar else { return }
            Self.applySerifLargeTitle(to: navigationBar)
        }
    }

    private static func applySerifLargeTitle(to navigationBar: UINavigationBar) {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withDesign(.serif)
            ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        let serifLargeTitleFont = UIFont(descriptor: descriptor, size: 0)

        let appearance = navigationBar.standardAppearance.copy()
        var largeTitleAttributes = appearance.largeTitleTextAttributes
        largeTitleAttributes[.font] = serifLargeTitleFont
        appearance.largeTitleTextAttributes = largeTitleAttributes

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
