import SwiftUI

/// Halo rose flou qui « respire » derrière un élément mis en avant (carte des écoutes pendant une
/// écoute, disque cible du guide de rangement). Très discret : seule l'opacité oscille. Sans
/// « Réduire les animations », halo fixe. À poser en `background`, à la taille de l'élément.
struct BreathingGlow: View {
    var cornerRadius: CGFloat = 24
    var blurRadius: CGFloat = 16
    var color: Color = Color.spinlogPink
    /// Opacité du halo au plus discret et au plus intense de sa respiration.
    var minOpacity: Double = 0.12
    var maxOpacity: Double = 0.30

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
            .opacity(isBreathing ? maxOpacity : minOpacity)
            .blur(radius: blurRadius)
            .padding(-4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}
