import SwiftUI

private struct AnimatedCountModifier: ViewModifier {
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText(value: Double(value)))
            .animation(reduceMotion ? nil : .counterChange, value: value)
    }
}

extension View {
    /// Les chiffres du texte « roulent » quand `value` change (compteur d'écran qui monte ou descend),
    /// au lieu de basculer d'un coup. Sans effet avec « Réduire les animations ».
    func animatedCount(_ value: Int) -> some View {
        modifier(AnimatedCountModifier(value: value))
    }
}
