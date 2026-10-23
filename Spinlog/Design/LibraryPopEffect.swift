import SwiftUI

/// Petit « pop » élastique (la vue grossit puis reprend sa taille) à chaque changement de
/// `trigger`. Sert de retour visuel à un ajout (collection, wantlist) ; sans « Réduire les
/// animations », la vue ne bouge pas.
private struct LibraryPopModifier: ViewModifier {
    let trigger: Int
    let peak: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(peak, duration: 0.16, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
            }
        }
    }
}

extension View {
    /// `peak` : échelle maximale atteinte (1,08 pour un bouton, 1,04 pour une grande pochette).
    func libraryPop(trigger: Int, peak: CGFloat = 1.08) -> some View {
        modifier(LibraryPopModifier(trigger: trigger, peak: peak))
    }
}
