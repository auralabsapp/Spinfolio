import SwiftUI

/// Point rose de la pastille « Écoute en cours » : un halo s'élargit et s'estompe en boucle, comme
/// un voyant de platine. Sans « Réduire les animations », le point reste fixe (l'état se lit dans le
/// texte de la pastille).
struct ListeningPulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.spinlogPink.opacity(0.4))
                .frame(width: 7, height: 7)
                .scaleEffect(isPulsing ? 2.8 : 1)
                .opacity(isPulsing ? 0 : 0.9)
            Circle()
                .fill(Color.spinlogPink)
                .frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}
