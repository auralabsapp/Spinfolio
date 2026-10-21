import SwiftUI

/// Page d'une section du guide : ses fiches, sous forme de cartes visuelles.
struct GuideSectionView: View {
    let section: GuideSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(section.summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondaryText)

                ForEach(section.entries) { entry in
                    GuideEntryCard(entry: entry)
                }
            }
            .padding()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(Text(section.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Carte d'une fiche : visuel, titre, une phrase, accès requis et bouton « Essayer ». Étapes et
/// astuce sont repliées sous « Détails ». Le badge Premium est fixe (il décrit la fonction, pas
/// l'état de l'abonné) et n'ouvre jamais le paywall.
struct GuideEntryCard: View {
    let entry: GuideEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideVisualView(visual: entry.visual)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(entry.summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondaryText)
                accessBadge
            }

            if let destination = entry.destination {
                tryButton(destination)
            }

            if entry.hasDetails {
                details
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appleMusicGroupedCard()
    }

    /// L'accès est dit en toutes lettres : pas d'information portée par la seule couleur.
    @ViewBuilder
    private var accessBadge: some View {
        switch entry.access {
        case .free:
            EmptyView()
        case .premium:
            PremiumPill()
        case .requiresAccount:
            Label("Compte Discogs requis", systemImage: "person.crop.circle")
                .font(.caption)
                .foregroundStyle(Color.appSecondaryText)
        }
    }

    private var details: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entry.numberedSteps) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        // `verbatim` : un `Text("\(n)")` créerait une clé de catalogue « %lld ».
                        Text(verbatim: String(step.number))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.spinlogPink)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.spinlogPink.opacity(0.15)))
                            .accessibilityHidden(true)
                        Text(step.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let tip = entry.tip {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.goldText)
                            .accessibilityHidden(true)
                        Text(tip)
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Détails")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.appSecondaryText)
        }
        .tint(Color.appSecondaryText)
    }

    private func tryButton(_ destination: GuideDestination) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            destination.open()
        } label: {
            Label("Essayer", systemImage: "arrow.right.circle.fill")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(Color.spinlogPink)
        // Plusieurs boutons « Essayer » par page : le titre de la fiche les distingue.
        .accessibilityHint(Text(entry.title))
    }
}

#Preview {
    NavigationStack {
        GuideSectionView(section: .gettingStarted)
    }
}
