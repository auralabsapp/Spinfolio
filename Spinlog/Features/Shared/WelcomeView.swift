import SwiftUI

/// Écran d'accueil plein écran, posé par `RootTabView` par-dessus les onglets (barre d'onglets
/// comprise) tant que l'utilisateur n'est pas connecté : disque qui tourne entouré de pochettes qui
/// flottent, nom de l'app, accroches qui défilent et actions de connexion.
/// Sans « Réduire les animations », tout est immobile (le contenu reste identique).
struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var taglineIndex = 0
    /// Pochettes tirées au hasard à chaque affichage de l'écran, parmi toutes celles embarquées.
    @State private var covers = Array(WelcomeCovers.names.shuffled().prefix(6))

    private static let taglines: [LocalizedStringKey] = [
        "Ta collection, à portée de main",
        "Ta wantlist, toujours avec toi",
        "Tes écoutes, au rythme du sillon"
    ]

    /// Position (par rapport au centre du disque), taille et inclinaison de chaque pochette, ainsi
    /// que sa phase de flottement : un tableau fixe plutôt qu'un tirage aléatoire, pour que l'écran
    /// soit identique à chaque lancement.
    private struct Slot {
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let rotation: Double
        let phase: Double
    }

    private static let slots: [Slot] = [
        Slot(dx: -118, dy: -78, size: 84, rotation: -9, phase: 0.0),
        Slot(dx: 120, dy: -96, size: 70, rotation: 7, phase: 1.3),
        Slot(dx: -138, dy: 42, size: 64, rotation: 6, phase: 2.1),
        Slot(dx: 136, dy: 52, size: 78, rotation: -6, phase: 3.4),
        Slot(dx: -34, dy: -142, size: 58, rotation: 4, phase: 4.2),
        Slot(dx: 28, dy: 128, size: 60, rotation: -4, phase: 5.0)
    ]

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 30) {
                    // Hauteur qui englobe la pochette du bas (centre + 128 + demi-taille + dérive) :
                    // sinon elle déborde sur le nom de l'app.
                    hero
                        .frame(height: 340)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8), value: appeared)

                    VStack(spacing: 10) {
                        Text(AppInfo.name)
                            .font(.system(.largeTitle, design: .serif).bold())
                            .accessibilityAddTraits(.isHeader)
                            .staggeredEntrance(appeared, delay: 0.15, reduceMotion: reduceMotion)

                        taglineView
                            .staggeredEntrance(appeared, delay: 0.3, reduceMotion: reduceMotion)

                        Text("Connecte-toi à Discogs pour retrouver ta collection, ta wantlist et tes statistiques.")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                            .multilineTextAlignment(.center)
                            .staggeredEntrance(appeared, delay: 0.4, reduceMotion: reduceMotion)
                    }
                    .padding(.horizontal, 24)

                    LoginActionsView()
                        .padding(.horizontal, 24)
                        .staggeredEntrance(appeared, delay: 0.5, reduceMotion: reduceMotion)
                }
                .padding(.vertical, 12)
                // Au moins la hauteur de l'écran, contenu centré : sur un grand écran, il ne reste pas
                // collé en haut (et défile quand même s'il ne tient pas, sur un petit écran).
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Lueur rose en haut de l'écran, qui s'efface vers le fond de l'app (placée devant lui : le
        // dernier `background` posé est celui du fond).
        .background(alignment: .top) {
            LinearGradient(
                colors: [Color.spinlogPink.opacity(0.16), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear { appeared = true }
        .task { await rotateTaglines() }
    }

    // MARK: - Disque et pochettes

    private var hero: some View {
        ZStack {
            BreathingGlow(cornerRadius: 90, blurRadius: 28, minOpacity: 0.14, maxOpacity: 0.34)
                .frame(width: 170, height: 170)

            // `TimelineView` en pause avec « Réduire les animations » : une seule image, immobile.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(Array(zip(covers, Self.slots).enumerated()), id: \.offset) { _, pair in
                        floatingCover(named: pair.0, slot: pair.1, time: time)
                    }
                }
            }

            EmptyStateDisc(diameter: 150)
        }
        .accessibilityHidden(true)
    }

    private func floatingCover(named name: String, slot: Slot, time: TimeInterval) -> some View {
        // Légère dérive verticale et petit balancement : lent, pour rester discret.
        let drift = sin(time * 0.9 + slot.phase) * 6
        let sway = sin(time * 0.6 + slot.phase) * 2.5
        return Image(name)
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .frame(width: slot.size, height: slot.size)
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
            .rotationEffect(.degrees(slot.rotation + sway))
            .offset(x: slot.dx, y: slot.dy + drift)
    }

    // MARK: - Accroches

    /// Une accroche à la fois, qui se fond et glisse de quelques points pour laisser la place à la
    /// suivante. Le glissement reste volontairement court et la zone a de la marge : un déplacement
    /// d'une hauteur de texte sortait de la zone et recouvrait le nom de l'app. Masquée à VoiceOver (le
    /// message fixe dessous porte l'information, sans texte qui change tout seul).
    private var taglineView: some View {
        Text(Self.taglines[taglineIndex])
            .id(taglineIndex)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.spinlogPink)
            .multilineTextAlignment(.center)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity.combined(with: .offset(y: -8))
                    )
            )
            .frame(maxWidth: .infinity, minHeight: 64)
            .clipped()
            .accessibilityHidden(true)
    }

    private func rotateTaglines() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                taglineIndex = (taglineIndex + 1) % Self.taglines.count
            }
        }
    }
}

private extension View {
    /// Apparition décalée : fondu et léger glissement vers le haut, après `delay` secondes.
    func staggeredEntrance(_ appeared: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85).delay(delay), value: appeared)
    }
}

#Preview {
    WelcomeView()
}
