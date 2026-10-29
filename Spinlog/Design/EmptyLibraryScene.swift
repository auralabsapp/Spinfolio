import SwiftUI

/// Illustration des écrans vides de la bibliothèque : le disque qui tourne (`EmptyStateDisc`), mis en
/// scène avec les pochettes embarquées (`WelcomeCovers`). Décorative : masquée à VoiceOver. Sans
/// « Réduire les animations », tout est immobile et visible d'emblée. Sans aucune pochette embarquée,
/// seul le disque s'affiche.
enum LibraryEmptyScene {
    /// Collection vide : des pochettes posées en éventail derrière le disque, comme sur une étagère
    /// qui attend ses disques.
    case shelf
    /// Wantlist vide : des pochettes et des cœurs qui montent doucement, comme des envies.
    case wishes
}

/// Collection vide : trois ou quatre pochettes tirées au hasard à chaque affichage, en éventail
/// derrière le disque. Elles arrivent l'une après l'autre avec un petit rebond, puis ne bougent plus.
struct EmptyShelfScene: View {
    let symbol: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var covers = Array(WelcomeCovers.names.shuffled().prefix(4))
    @State private var appeared = false

    /// Position, taille et inclinaison de chaque pochette, de gauche à droite (les plus au centre au
    /// premier plan) : un tableau fixe, seul le choix des pochettes varie.
    private struct Slot {
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let rotation: Double
    }

    private static let slots = [
        Slot(dx: -70, dy: -30, size: 78, rotation: -12),
        Slot(dx: 72, dy: -36, size: 74, rotation: 11),
        Slot(dx: -24, dy: -62, size: 70, rotation: -4),
        Slot(dx: 28, dy: -58, size: 66, rotation: 5)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(zip(covers, Self.slots).enumerated()), id: \.offset) { index, pair in
                cover(pair.0, slot: pair.1, index: index)
            }
            EmptyStateDisc(symbol: symbol)
                .offset(y: 38)
        }
        .frame(height: 200)
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }

    private func cover(_ name: String, slot: Slot, index: Int) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .frame(width: slot.size, height: slot.size)
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
            .rotationEffect(.degrees(slot.rotation))
            .offset(x: slot.dx, y: slot.dy + (appeared || reduceMotion ? 0 : 24))
            .opacity(appeared || reduceMotion ? 1 : 0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.65).delay(0.15 + Double(index) * 0.12),
                value: appeared
            )
    }
}

/// Wantlist vide : le disque au centre, entouré de pochettes et de cœurs qui montent lentement en
/// s'estompant, chacun à son rythme. Mouvement calculé à partir de l'heure (`TimelineView`) plutôt
/// que d'animations répétées : pas d'état à gérer, et figé avec « Réduire les animations ».
struct EmptyWishesScene: View {
    let symbol: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var covers = Array(WelcomeCovers.names.shuffled().prefix(3))

    private struct Particle {
        let dx: CGFloat
        /// Durée d'une montée, en secondes.
        let period: Double
        /// Décalage de départ dans la montée (0 à 1), pour que tout ne parte pas en même temps.
        let phase: Double
        let size: CGFloat
        /// Pochette (indice dans `covers`) ou, à défaut, un cœur.
        let coverIndex: Int?
    }

    private static let particles = [
        Particle(dx: -92, period: 9, phase: 0.05, size: 52, coverIndex: 0),
        Particle(dx: 88, period: 11, phase: 0.45, size: 46, coverIndex: 1),
        Particle(dx: -8, period: 10, phase: 0.75, size: 42, coverIndex: 2),
        Particle(dx: -50, period: 7, phase: 0.30, size: 16, coverIndex: nil),
        Particle(dx: 56, period: 8, phase: 0.60, size: 14, coverIndex: nil),
        Particle(dx: 112, period: 9, phase: 0.90, size: 12, coverIndex: nil),
        Particle(dx: -118, period: 8.5, phase: 0.55, size: 12, coverIndex: nil)
    ]

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(Array(Self.particles.enumerated()), id: \.offset) { _, particle in
                        particleView(particle, time: time)
                    }
                }
            }
            EmptyStateDisc(symbol: symbol)
                .offset(y: 30)
        }
        // Pleine largeur avant `clipped()` : sinon le cadre se réduit au disque et rogne les pochettes
        // et les cœurs qui montent de part et d'autre.
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func particleView(_ particle: Particle, time: TimeInterval) -> some View {
        let progress = ((time / particle.period) + particle.phase).truncatingRemainder(dividingBy: 1)
        // Monte de bas en haut, apparaît et s'estompe en douceur aux extrémités du trajet.
        let y = 70 - progress * 190
        let opacity = sin(progress * .pi)
        let sway = sin(progress * .pi * 2 + particle.phase * 6) * 6
        let content = particleContent(particle)
        content
            .opacity(opacity * (particle.coverIndex == nil ? 0.9 : 0.85))
            .offset(x: particle.dx + sway, y: y)
    }

    @ViewBuilder
    private func particleContent(_ particle: Particle) -> some View {
        if let index = particle.coverIndex {
            if index < covers.count {
                Image(covers[index])
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: particle.size, height: particle.size)
                    .clipShape(RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
            }
        } else {
            Image(systemName: "heart.fill")
                .font(.system(size: particle.size))
                .foregroundStyle(Color.spinlogPink)
        }
    }
}

#Preview("Scènes vides") {
    VStack(spacing: 24) {
        EmptyShelfScene(symbol: "square.stack.fill")
        EmptyWishesScene(symbol: "heart.fill")
    }
    .padding()
    .background(Color.appBackground)
}
