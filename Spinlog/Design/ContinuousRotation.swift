import SwiftUI

/// Vitesse d'un 33 tours, partagée par tous les disques qui tournent dans l'app.
enum RecordSpin {
    static let rpm33: Double = 100.0 / 3.0
}

/// Fait tourner une vue en continu tant que `isActive` est vrai (par défaut à la vitesse d'un 33
/// tours). Animation linéaire répétée, portée par le moteur de rendu : pas de recalcul SwiftUI à
/// chaque image. À l'arrêt, la vue reprend sa position d'origine sans animation de retour (une
/// animation rejouée à l'envers serait bien plus visible que le simple retour à la verticale).
/// Avec « Réduire les animations », la vue ne tourne jamais.
struct ContinuousRotationModifier: ViewModifier {
    let isActive: Bool
    var rpm: Double = RecordSpin.rpm33

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear(perform: update)
            .onChange(of: isActive) { update() }
    }

    private func update() {
        if isActive && !reduceMotion {
            guard angle == 0 else { return }
            withAnimation(.linear(duration: 60.0 / rpm).repeatForever(autoreverses: false)) {
                angle = 360
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { angle = 0 }
        }
    }
}

extension View {
    func continuousRotation(isActive: Bool, rpm: Double = RecordSpin.rpm33) -> some View {
        modifier(ContinuousRotationModifier(isActive: isActive, rpm: rpm))
    }
}
