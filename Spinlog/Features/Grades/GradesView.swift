import SwiftUI

/// Page « Mes grades » : pour chaque parcours (collection, écoute sur platine), le grade acquis en
/// grand avec sa date d'obtention, la jauge vers le suivant, puis tous les grades — obtenus en
/// couleur, à venir en gris avec leur condition. Un grade acquis ne se perd jamais.
struct GradesView: View {
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Tes grades récompensent la taille de ta collection et tes écoutes sur platine. Un grade obtenu ne se perd jamais, même si tu retires des disques.")
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(GradeTrack.allCases.enumerated()), id: \.element) { index, track in
                    GradeTrackSection(track: track)
                        .shelfEntrance(isVisible: revealed, offset: CGSize(width: 0, height: 20), delay: 0.12 * Double(index))
                }
            }
            .padding()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Mes grades")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { revealed = true }
    }
}

/// Un parcours : carte du grade acquis puis liste de tous les grades.
private struct GradeTrackSection: View {
    let track: GradeTrack

    @State private var store = GradeStore.shared

    var body: some View {
        let acquired = store.acquiredTiers(for: track)
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(title: track.title, icon: track.symbol)
            GradeHeroCard(track: track, acquiredTiers: acquired)
            GradeTierList(track: track, acquiredTiers: acquired)
        }
    }
}

/// Le grade acquis en grand, avec la jauge vers le suivant.
private struct GradeHeroCard: View {
    let track: GradeTrack
    let acquiredTiers: Int

    @State private var store = GradeStore.shared
    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentTier: Int { max(0, acquiredTiers - 1) }

    var body: some View {
        VStack(spacing: 14) {
            GradeBadgeView(track: track, tier: currentTier, isUnlocked: acquiredTiers > 0, size: 120)
                .scaleEffect(popped || reduceMotion ? 1 : 0.55)
                .opacity(popped || reduceMotion ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: popped)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                if acquiredTiers > 0 {
                    Text(track.tierName(currentTier))
                        .font(.title2.bold())
                    if let date = store.unlockDate(track: track, tier: currentTier) {
                        Text("Obtenu le \(date.formatted(date: .long, time: .omitted))")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                } else {
                    Text("Aucun grade pour l'instant")
                        .font(.title3.weight(.semibold))
                }
            }

            progressSection
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .appleMusicGroupedCard()
        .accessibilityElement(children: .combine)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            popped = true
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if let next = GradeRules.nextThreshold(acquiredTiers: acquiredTiers, track: track) {
            if let count = store.knownCount(for: track) {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        CountUpText(target: count)
                            .font(.headline.monospacedDigit())
                        Text("/")
                            .foregroundStyle(Color.appSecondaryText)
                        Text(next, format: .number)
                            .font(.headline.monospacedDigit())
                        Spacer()
                        Text(track.unitCaption)
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    GradeGauge(
                        progress: GradeRules.progress(count: count, acquiredTiers: acquiredTiers, track: track),
                        tint: Color.gradeTier(acquiredTiers)
                    )
                }
            } else {
                Text("Le comptage apparaîtra une fois ta collection synchronisée.")
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
            }
        } else {
            Label("Grade maximum atteint", systemImage: "crown.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.goldText)
        }
    }
}

/// Tous les grades du parcours, du premier au dernier.
private struct GradeTierList: View {
    let track: GradeTrack
    let acquiredTiers: Int

    @State private var store = GradeStore.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(track.thresholds.indices), id: \.self) { tier in
                GradeTierRow(
                    track: track,
                    tier: tier,
                    isUnlocked: tier < acquiredTiers,
                    isCurrent: tier == acquiredTiers - 1,
                    date: store.unlockDate(track: track, tier: tier)
                )
                if tier < track.thresholds.count - 1 {
                    Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 70)
                }
            }
        }
        .padding(.vertical, 6)
        .appleMusicGroupedCard()
    }
}

private struct GradeTierRow: View {
    let track: GradeTrack
    let tier: Int
    let isUnlocked: Bool
    let isCurrent: Bool
    let date: Date?

    var body: some View {
        HStack(spacing: 14) {
            GradeBadgeView(track: track, tier: tier, isUnlocked: isUnlocked, size: 46)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.tierName(tier))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isUnlocked ? Color.primary : Color.appSecondaryText)
                subtitle
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }

            Spacer(minLength: 8)

            if isCurrent {
                Text("Grade actuel")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.spinlogPinkBadge, in: Capsule())
            } else if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.gainPositive)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var subtitle: some View {
        if isUnlocked, let date {
            Text("Obtenu le \(date.formatted(date: .long, time: .omitted))")
        } else if isUnlocked {
            Text("Obtenu")
        } else {
            Text(track.condition(forTier: tier))
        }
    }
}

#Preview {
    NavigationStack { GradesView() }
}
