import SwiftUI

/// Retour visuel des boutons d'alerte de prix de la Wantlist (cloche d'une ligne, bouton « Alerte »
/// du carrousel) : sous le doigt, le bouton se tasse et une pastille rose s'allume derrière lui,
/// puis il se relâche avec un petit rebond. Sans « Réduire les animations », seule la pastille
/// s'allume (aucun changement d'échelle).
struct AlertBellButtonStyle: ButtonStyle {
    var shape: AnyShape = AnyShape(Circle())

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                shape
                    .fill(Color.spinlogPink.opacity(configuration.isPressed ? 0.20 : 0))
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.82 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.45),
                value: configuration.isPressed
            )
    }
}
