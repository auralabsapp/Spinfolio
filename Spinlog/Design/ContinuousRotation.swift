import SwiftUI

/// Vitesse d'un 33 tours, partagée par tous les disques qui tournent dans l'app.
enum RecordSpin {
    static let rpm33: Double = 100.0 / 3.0
}

/// Fait tourner une vue en continu tant que `isActive` est vrai (par défaut à la vitesse d'un 33
/// tours). L'angle est calculé à chaque image à partir de l'heure (`TimelineView`), comme les autres
/// éléments animés de l'app : mise en pause, le disque s'arrête net et reprend sans animation de
/// retour. Une animation répétée à l'infini (`repeatForever`) ne s'arrêtait pas quand « Réduire les
/// animations » était activé pendant que l'app tournait. Avec ce réglage, la vue ne tourne jamais.
struct ContinuousRotationModifier: ViewModifier {
    let isActive: Bool
    var rpm: Double = RecordSpin.rpm33

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Début de la rotation en cours : la vue repart de sa position d'origine à chaque activation.
    @State private var startDate: Date?

    private var isSpinning: Bool { isActive && !reduceMotion }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !isSpinning)) { timeline in
            content
                .rotationEffect(.degrees(angle(at: timeline.date)))
        }
        .onAppear(perform: restart)
        .onChange(of: isActive) { restart() }
        .onChange(of: reduceMotion) { restart() }
    }

    private func restart() {
        startDate = isSpinning ? .now : nil
    }

    private func angle(at date: Date) -> Double {
        guard isSpinning, let startDate else { return 0 }
        // Un tour = 60 / rpm secondes, soit rpm × 6 degrés par seconde.
        return (date.timeIntervalSince(startDate) * rpm * 6).truncatingRemainder(dividingBy: 360)
    }
}

extension View {
    func continuousRotation(isActive: Bool, rpm: Double = RecordSpin.rpm33) -> some View {
        modifier(ContinuousRotationModifier(isActive: isActive, rpm: rpm))
    }
}
