import UIKit

/// Verrou d'orientation global consulté par `AppDelegate`. L'app est bloquée en portrait sur
/// iPhone (réglage du projet), sauf pendant la lecture d'une vidéo en plein écran où le paysage
/// doit être autorisé pour un visionnage confortable.
final class OrientationLock {
    static let shared = OrientationLock()

    var mask: UIInterfaceOrientationMask = .portrait

    private init() {}

    /// Autorise temporairement le paysage et force la scène courante à réévaluer les
    /// orientations supportées (sans quoi iOS continue d'appliquer le verrou déjà en vigueur).
    func allowLandscape() {
        mask = .allButUpsideDown
        requestUpdate(preferring: .landscapeRight)
    }

    /// Revient au portrait strict et fait pivoter la scène en conséquence.
    func restorePortrait() {
        mask = .portrait
        requestUpdate(preferring: .portrait)
    }

    private func requestUpdate(preferring orientation: UIInterfaceOrientationMask) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        windowScene.windows.first(where: \.isKeyWindow)?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// Délégué minimal requis pour que `supportedInterfaceOrientationsFor` puisse consulter
/// `OrientationLock` : SwiftUI seul n'expose aucun point d'entrée pour cette API UIKit.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}
