import SwiftUI
import UIKit

/// Désactive `interactiveContentPopGestureRecognizer` (iOS 18+) sur l'écran courant : ce geste
/// système déclenche un retour interactif dès qu'on pan horizontalement n'importe où dans le
/// contenu (pas seulement depuis le bord), ce qui donne l'impression que la pochette ou la
/// tracklist "glissent" puis reviennent en place. Le swipe-back classique depuis le bord
/// (`interactivePopGestureRecognizer`) reste actif.
private struct DisableContentPopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = false
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        uiViewController.navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = true
    }
}

extension View {
    func disablesContentPopGesture() -> some View {
        background(DisableContentPopGesture())
    }
}
