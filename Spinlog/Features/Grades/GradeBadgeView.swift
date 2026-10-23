import SwiftUI

/// Badge d'un grade : un disque noir (sillons, reflets qui balaient) cerclé d'un anneau à la teinte
/// du grade, avec une étiquette à la couleur du parcours. Vivant : l'anneau et les reflets tournent
/// lentement, un halo respire, et les étincelles du dernier grade scintillent. Verrouillé : gris,
/// immobile, avec un cadenas. Sans « Réduire les animations », tout est fixe.
struct GradeBadgeView: View {
    let track: GradeTrack
    /// Indice du grade représenté (0 = premier).
    let tier: Int
    var isUnlocked = true
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var twinkle = false

    private var ringColor: Color { isUnlocked ? Color.gradeTier(tier) : Color.gray.opacity(0.7) }
    private var labelColor: Color { isUnlocked ? track.labelColor : Color.gray.opacity(0.55) }
    private var isTopTier: Bool { tier >= track.thresholds.count - 1 }
    private var inset: CGFloat { size * 0.07 }

    var body: some View {
        ZStack {
            if isUnlocked {
                BreathingGlow(cornerRadius: size / 2, blurRadius: size * 0.16, color: ringColor, minOpacity: 0.12, maxOpacity: 0.38)
                    .frame(width: size, height: size)
            }

            ring
            record
            highlights
            label

            if isUnlocked && isTopTier {
                sparkles
            }
        }
        .frame(width: size, height: size)
        .opacity(isUnlocked ? 1 : 0.65)
        .onAppear {
            guard isUnlocked, isTopTier, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                twinkle = true
            }
        }
    }

    private var ring: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [ringColor, ringColor.opacity(0.35), ringColor, ringColor.opacity(0.35), ringColor],
                    center: .center
                ),
                lineWidth: size * 0.07
            )
            .continuousRotation(isActive: isUnlocked, rpm: 5)
    }

    private var record: some View {
        Circle()
            .fill(Color.black.opacity(isUnlocked ? 0.92 : 0.55))
            .padding(inset)
            .overlay {
                ZStack {
                    ForEach([0.82, 0.68, 0.54], id: \.self) { ratio in
                        Circle()
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: max(0.5, size * 0.008))
                            .frame(width: size * ratio, height: size * ratio)
                    }
                }
            }
    }

    /// Deux reflets opposés qui balaient le disque, comme la lumière sur un vinyle qui tourne.
    private var highlights: some View {
        Circle()
            .fill(
                AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.30), location: 0.06),
                        .init(color: .clear, location: 0.14),
                        .init(color: .clear, location: 0.5),
                        .init(color: .white.opacity(0.16), location: 0.56),
                        .init(color: .clear, location: 0.64),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center
                )
            )
            .padding(inset)
            .continuousRotation(isActive: isUnlocked, rpm: 9)
            .allowsHitTesting(false)
    }

    private var label: some View {
        Circle()
            .fill(labelColor)
            .frame(width: size * 0.44, height: size * 0.44)
            .overlay {
                Image(systemName: isUnlocked ? track.symbol : "lock.fill")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: max(0.5, size * 0.01)))
    }

    private var sparkles: some View {
        ZStack {
            sparkle(x: 0.38, y: -0.36, scale: 1.0, phase: twinkle)
            sparkle(x: -0.40, y: -0.18, scale: 0.7, phase: !twinkle)
            sparkle(x: 0.30, y: 0.40, scale: 0.55, phase: twinkle)
        }
        .allowsHitTesting(false)
    }

    private func sparkle(x: CGFloat, y: CGFloat, scale: CGFloat, phase: Bool) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.2 * scale, weight: .bold))
            .foregroundStyle(Color.goldLight)
            .opacity(phase ? 1 : 0.25)
            .scaleEffect(phase ? 1.15 : 0.7)
            .offset(x: size * x, y: size * y)
    }
}

/// Jauge vers le palier suivant : se remplit à l'apparition, avec un reflet qui la parcourt.
struct GradeGauge: View {
    let progress: Double
    let tint: Color

    @State private var shown = false
    @State private var sheen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fill = width * (shown || reduceMotion ? progress : 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(fill, fill > 0 ? 8 : 0))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 36)
                            .offset(x: sheen ? max(fill, 0) : -36)
                            .opacity(reduceMotion || fill < 20 ? 0 : 1)
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 8)
        .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.82), value: shown)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            shown = true
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false).delay(0.9)) {
                sheen = true
            }
        }
        .accessibilityHidden(true)
    }
}
