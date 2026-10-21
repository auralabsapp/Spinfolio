import SwiftUI
import UIKit

/// Prévient dès qu'une feuille commence à se fermer (glissé vers le bas, croix, fermeture par le
/// code) — alors que le `Binding` de `.sheet(item:)` et `onDismiss` n'arrivent qu'à la FIN de
/// l'animation de fermeture. Utile pour préparer l'écran derrière la feuille (remise à zéro d'une
/// sélection, marge) pendant que la feuille descend, plutôt qu'en un seul bloc une fois partie.
///
/// À poser en `.background` de la racine du contenu de la feuille. Ignore les disparitions
/// d'apparence qui ne sont pas une fermeture (ex. navigation vers un écran poussé dans la feuille).
struct SheetWillDisappearObserver: UIViewControllerRepresentable {
    let onWillDisappear: () -> Void

    func makeUIViewController(context: Context) -> ObserverController {
        let controller = ObserverController()
        controller.onWillDisappear = onWillDisappear
        return controller
    }

    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.onWillDisappear = onWillDisappear
    }

    final class ObserverController: UIViewController {
        var onWillDisappear: (() -> Void)?

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // Fermeture réelle seulement : un ancêtre (la feuille présentée) est en cours de dismiss.
            var ancestor: UIViewController? = self
            while let controller = ancestor {
                if controller.isBeingDismissed {
                    onWillDisappear?()
                    return
                }
                ancestor = controller.parent
            }
        }
    }
}
