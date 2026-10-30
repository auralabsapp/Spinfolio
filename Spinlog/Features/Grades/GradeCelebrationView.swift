import SwiftUI

/// Pose, au-dessus de l'app, la célébration d'un grade qui vient d'être franchi. Vue à part :
/// seule elle lit `GradeStore.pendingCelebration`, pour ne pas invalider `RootTabView`.
struct GradeCelebrationHost: View {
    @State private var store = GradeStore.shared

    var body: some View {
        ZStack {
            if let celebration = store.pendingCelebration {
                GradeCelebrationView(
                    celebration: celebration,
                    onDismiss: { store.dismissCelebration() },
                    onShowGrades: {
                        store.dismissCelebration()
                        TabNavigationCoordinator.shared.openGrades()
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.pendingCelebration?.id)
    }
}

/// Un grade franchi : le badge arrive en rebondissant au milieu d'une gerbe d'étincelles, avec un
/// haptique de succès. Se ferme d'un toucher n'importe où ou par « Fermer ». Sans « Réduire les
/// animations », badge et étincelles apparaissent sans mouvement.
struct GradeCelebrationView: View {
    let celebration: GradeCelebration
    let onDismiss: () -> Void
    let onShowGrades: () -> Void

    @State private var arrived = false
    @State private var burst = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sparkCount = 14

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            VStack(spacing: 18) {
                ZStack {
                    sparks
                    GradeBadgeView(track: celebration.track, tier: celebration.tier, size: 150)
                        .scaleEffect(arrived || reduceMotion ? 1 : 0.2)
                        .rotationEffect(.degrees(arrived || reduceMotion ? 0 : -140))
                        .opacity(arrived || reduceMotion ? 1 : 0)
                }
                .frame(height: 190)
                .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Group {
                        switch celebration.kind {
                        case .newGrade: Text("Nouveau grade !")
                        case .welcome: Text("Bienvenue !")
                        }
                    }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.spinlogPink)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    Text(celebration.track.tierName(celebration.tier))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(celebration.track.title)
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                    if celebration.kind == .welcome {
                        Text("Voici ton grade de départ, déjà mérité. Les suivants se gagnent avec tes albums et tes écoutes.")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if celebration.tiersGained > 1 {
                        Text("Tu as franchi \(celebration.tiersGained) grades d'un coup.")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                            .multilineTextAlignment(.center)
                    }
                }

                VStack(spacing: 10) {
                    Button(action: onShowGrades) {
                        Text("Voir mes grades")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color.onAccent)
                    .tint(Color.spinlogPink)

                    Button("Fermer", action: onDismiss)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.appBackground)
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
            )
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onDismiss)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            guard !reduceMotion else {
                arrived = true
                return
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.55)) { arrived = true }
            withAnimation(.easeOut(duration: 1.1).delay(0.15)) { burst = true }
        }
    }

    /// Gerbe d'étincelles qui part du badge et s'efface.
    private var sparks: some View {
        ZStack {
            ForEach(0..<Self.sparkCount, id: \.self) { index in
                let angle = Double(index) / Double(Self.sparkCount) * 2 * .pi
                let distance: CGFloat = index.isMultiple(of: 2) ? 112 : 88
                Image(systemName: index.isMultiple(of: 3) ? "sparkle" : "circle.fill")
                    .font(.system(size: index.isMultiple(of: 3) ? 16 : 6, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 2) ? Color.goldLight : Color.gradeTier(celebration.tier))
                    .offset(
                        x: burst ? CGFloat(cos(angle)) * distance : 0,
                        y: burst ? CGFloat(sin(angle)) * distance : 0
                    )
                    .scaleEffect(burst ? 1 : 0.2)
                    .opacity(burst ? 0 : 1)
            }
        }
        .opacity(reduceMotion ? 0 : 1)
    }
}
