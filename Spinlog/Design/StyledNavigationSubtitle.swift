import SwiftUI
import UIKit

/// Affiche le sous-titre de navigation (ex: "Tous · 289 éléments") dans une police lisible plutôt
/// que le style système par défaut (à peine plus grand qu'un `caption2`, jugé trop petit) : la
/// modifier SwiftUI native `.navigationSubtitle(_:)` ne permet aucune personnalisation de police,
/// donc on configure directement `UINavigationItem.largeAttributedSubtitle`/`attributedSubtitle`
/// (sous le grand titre / en mode compact) du contrôleur hébergeant cet écran — même principe que
/// `SerifNavigationTitleConfigurator`.
private struct StyledNavigationSubtitleConfigurator: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let item = uiViewController.navigationController?.topViewController?.navigationItem else { return }
            guard !text.isEmpty else {
                item.largeAttributedSubtitle = nil
                item.attributedSubtitle = nil
                return
            }
            var attributed = AttributedString(text)
            attributed.font = .subheadline
            attributed.foregroundColor = .secondary
            item.largeAttributedSubtitle = attributed
            item.attributedSubtitle = attributed
        }
    }
}

extension View {
    /// Voir `StyledNavigationSubtitleConfigurator`.
    func styledNavigationSubtitle(_ text: String) -> some View {
        background(StyledNavigationSubtitleConfigurator(text: text))
    }
}
