import SwiftUI

/// Entrée échelonnée des disques du guide de rangement : l'élément part décalé et transparent, puis
/// rejoint sa place avec un ressort, après `delay` secondes. Sans « Réduire les animations »,
/// l'élément est affiché directement à sa place.
struct ShelfEntranceModifier: ViewModifier {
    let isVisible: Bool
    let offset: CGSize
    let delay: Double
    var startScale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = isVisible || reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : startScale)
            .offset(shown ? .zero : offset)
            .animation(
                reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.7).delay(delay),
                value: isVisible
            )
    }
}

extension View {
    func shelfEntrance(isVisible: Bool, offset: CGSize, delay: Double, startScale: CGFloat = 1) -> some View {
        modifier(ShelfEntranceModifier(isVisible: isVisible, offset: offset, delay: delay, startScale: startScale))
    }
}
