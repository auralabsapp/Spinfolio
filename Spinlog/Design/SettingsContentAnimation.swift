import SwiftUI

private struct SettingsContentAnimationModifier<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .settingsContentChange, value: value)
    }
}

extension View {
    /// Une ligne ou un état d'une page de Réglages qui apparaît, disparaît ou change quand `value`
    /// change (réglage qui en révèle un autre, opération en cours…) s'anime en fondu au lieu de sauter.
    /// Sans effet avec « Réduire les animations ».
    func animatesSettingsChanges<Value: Equatable>(value: Value) -> some View {
        modifier(SettingsContentAnimationModifier(value: value))
    }
}
