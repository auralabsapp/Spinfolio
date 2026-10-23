import SwiftUI

/// Nombre entier qui défile de 0 jusqu'à sa valeur la première fois qu'elle est connue (compteurs de
/// l'écran Stats), puis suit les changements suivants sans repartir de zéro. Sans « Réduire les
/// animations », la valeur s'affiche directement. Sans valeur (`nil`), un tiret.
struct CountUpText: View {
    let target: Int?

    @State private var shown = 0
    @State private var hasAnimated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if target == nil {
                Text("–")
            } else {
                Text(shown, format: .number)
                    .contentTransition(.numericText(value: Double(shown)))
            }
        }
        .task(id: target) {
            guard let target else { return }
            guard !hasAnimated, !reduceMotion, target > 0 else {
                shown = target
                hasAnimated = true
                return
            }
            hasAnimated = true
            // ≈ 0,7 s en 14 pas : chaque pas est lui-même animé par `numericText`.
            let steps = min(14, target)
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    shown = Int((Double(target) * Double(step) / Double(steps)).rounded())
                }
            }
            shown = target
        }
    }
}
