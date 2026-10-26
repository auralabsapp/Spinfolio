import SwiftUI

/// Maquettes des fiches du guide. Elles reprennent les libellés et les icônes réels de l'app
/// (mêmes clés de catalogue, mêmes SF Symbols, mêmes jetons de couleur) sans en être des
/// captures. Purement décoratives : le texte de la fiche porte le sens, donc masquées à VoiceOver.
struct GuideVisualView: View {
    let visual: GuideVisual

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appBackground)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch visual {
        case .signIn: SignInMock()
        case .searchBar: SearchBarMock()
        case .collectionAndWantlist: CollectionAndWantlistMock()
        case .batchScan: BatchScanMock()
        case .displayModes: DisplayModesMock()
        case .sortAndIndex: SortAndIndexMock()
        case .filters: FiltersMock()
        case .rowActions: RowActionsMock()
        case .tracklist: TracklistMock()
        case .copies: CopiesMock()
        case .tagsAndRating: TagsAndRatingMock()
        case .price: PriceMock()
        case .statsCounters: StatsCountersMock()
        case .statsCharts: StatsChartsMock()
        case .gain: GainMock()
        case .podium: PodiumMock()
        case .listening: ListeningMock()
        case .liveActivity: LiveActivityMock()
        case .appleMusic: AppleMusicMock()
        case .widget: WidgetMock()
        case .shelfPlacement: ShelfPlacementMock()
        case .shelfMethod: ShelfMethodMock()
        case .artistNames: ArtistNamesMock()
        case .shelfScope: ShelfScopeMock()
        case .alertRow: AlertRowMock()
        case .alertSuggestions: AlertSuggestionsMock()
        case .alertTriggered: AlertTriggeredMock()
        case .offline: OfflineMock()
        case .iCloud: ICloudMock()
        case .themes: ThemesMock()
        case .exports: ExportsMock()
        case .tagsAndFolders: TagsAndFoldersMock()
        case .account: AccountMock()
        }
    }
}

// MARK: - Connexion

private struct SignInMock: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Se connecter")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onAccentGradient)
                .padding(.horizontal, 32)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.spinlogPinkButtonGradient))

            Text("Pas de compte ? Crée-en un")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.spinlogPink)

            Text("Explorer avec une collection de démo")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
    }
}

// MARK: - Recherche

private struct SearchBarMock: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appSecondaryText)

            Text("Artiste, disque, label, code-barre…")
                .font(.subheadline)
                .foregroundStyle(Color.appTertiaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            Divider().overlay(Color.appSeparator).frame(height: 18)

            // Icône de scan entourée : c'est elle que la fiche désigne.
            Image(systemName: "barcode.viewfinder")
                .foregroundStyle(Color.spinlogPink)
                .padding(5)
                .overlay(Circle().stroke(Color.spinlogPink, lineWidth: 2))

            // Couleur du thème, comme pour un abonné : l'or de l'app est celui du cadenas affiché
            // aux non-abonnés, et la fiche porte déjà sa propre pastille Premium.
            Image(systemName: "rectangle.stack.badge.plus")
                .foregroundStyle(Color.spinlogPink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Collection et wantlist

private struct CollectionAndWantlistMock: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                pill("Collection", systemImage: "plus", isActive: false)
                pill("Wantlist", systemImage: "heart.fill", isActive: false)
            }

            Image(systemName: "arrow.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.appSecondaryText)

            HStack(spacing: 10) {
                pill("En collection", systemImage: "checkmark", isActive: true)
                pill("En wantlist", systemImage: "checkmark", isActive: true)
            }
        }
    }

    /// Même forme que les boutons de la fiche d'un disque (`ReleaseQuickActionsBar`).
    private func pill(_ title: LocalizedStringKey, systemImage: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.bold())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? Color.onAccentGradient : Color.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(
            Capsule().fill(isActive ? AnyShapeStyle(Color.spinlogPinkButtonGradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
        )
    }
}

// MARK: - Scan par lot

private struct BatchScanMock: View {
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Image(systemName: "barcode")
                        .font(.title2)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }

            Image(systemName: "arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appSecondaryText)

            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.onAccentGradient)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.spinlogPinkButtonGradient))
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        GuideVisualView(visual: .signIn)
        GuideVisualView(visual: .searchBar)
        GuideVisualView(visual: .collectionAndWantlist)
        GuideVisualView(visual: .batchScan)
    }
    .padding()
}
