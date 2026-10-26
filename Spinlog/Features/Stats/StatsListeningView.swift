import SwiftUI
import Kingfisher

/// Tops & palmarès d'écoute (podium, classements) de l'onglet Stats — extrait de
/// StatsView.swift, voir le commentaire sur `StatsChartsView`.
extension StatsView {
    // MARK: - Tops & Palmarès d'écoute

    @ViewBuilder
    var listeningStatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Tops & Palmarès", icon: "waveform", isPremiumFeature: true)

            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "waveform",
                    title: "Palmarès d'écoute sur platine",
                    message: viewModel.totalListeningSessionsCount > 0
                        ? "Tu as déjà enregistré \(viewModel.totalListeningSessionsCount) écoutes sur platine. Passe premium pour révéler tes classements, artistes favoris et podiums !"
                        : "Passe premium pour révéler tes classements d'albums et artistes les plus écoutés sur platine, podiums mensuels et annuels."
                )
            } else if viewModel.totalListeningSessionsCount < StatsViewModel.minimumListeningSessionsForRanking {
                notEnoughListeningDataCard(
                    "Enregistre au moins \(StatsViewModel.minimumListeningSessionsForRanking) écoutes sur platine (bouton J'écoute d'une fiche album) pour débloquer tes classements."
                )
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    topEntitiesCard
                    podiumSection
                    Text("Basé sur tes écoutes sur platine. Les lectures Apple Music ne sont pas comptées.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
        }
    }

    /// Classements des albums et artistes les plus écoutés, au même endroit : le même geste
    /// (segmented Picker) que pour la période du podium ci-dessous permet de passer de l'un à
    /// l'autre sans faire défiler deux cartes empilées séparément.
    @ViewBuilder
    var topEntitiesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(title: "Les plus écoutés", style: .subsection)

            Picker("Classement", selection: $topEntityKind.animation(.easeInOut(duration: 0.2))) {
                ForEach(TopEntityKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch topEntityKind {
            case .albums:
                let visibleAlbums = Array(viewModel.topAlbums.prefix(20).enumerated())
                // 5 lignes visibles par défaut, jusqu'à 20 en faisant défiler verticalement (hauteur
                // calculée par `cappedListHeight`).
                let visibleHeight = Self.cappedListHeight(
                    contentHeight: topAlbumsContentHeight,
                    rowCount: visibleAlbums.count,
                    estimatedRowHeight: 64
                )

                if visibleAlbums.count > 5 {
                    Text("Faire défiler verticalement pour afficher les autres albums")
                        .font(.caption2)
                        .foregroundStyle(Color.appSecondaryText)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(visibleAlbums, id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)
                            }
                            topAlbumRow(rank: index + 1, entry: entry)
                        }
                    }
                    // Hauteur réelle des lignes (taille de texte, noms sur deux lignes...) : une
                    // hauteur de ligne estimée coupait la 5ᵉ ligne. `@Sendable` : voir CLAUDE.md §12.
                    .onGeometryChange(for: CGFloat.self) { @Sendable proxy in
                        proxy.size.height
                    } action: { height in
                        topAlbumsContentHeight = height
                    }
                }
                .frame(height: visibleHeight)
                .appleMusicGroupedCard()
            case .artists:
                let visibleArtists = Array(viewModel.topArtists.prefix(20).enumerated())
                // Même convention que les albums ci-dessus (indice textuel affiché seulement s'il y
                // a effectivement plus à découvrir).
                let visibleHeight = Self.cappedListHeight(
                    contentHeight: topArtistsContentHeight,
                    rowCount: visibleArtists.count,
                    estimatedRowHeight: 56
                )

                if visibleArtists.count > 5 {
                    Text("Faire défiler verticalement pour afficher les autres artistes")
                        .font(.caption2)
                        .foregroundStyle(Color.appSecondaryText)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(visibleArtists, id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)
                            }
                            topArtistRow(rank: index + 1, entry: entry)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { @Sendable proxy in
                        proxy.size.height
                    } action: { height in
                        topArtistsContentHeight = height
                    }
                }
                .frame(height: visibleHeight)
                .appleMusicGroupedCard()
            }
        }
    }

    /// Hauteur du cadre défilant des classements : exactement 5 lignes visibles (moins s'il y en a
    /// moins), d'après la hauteur mesurée du contenu — les lignes ont toutes la même hauteur. Tant
    /// que la mesure n'est pas connue, repli sur une hauteur de ligne estimée.
    nonisolated static func cappedListHeight(contentHeight: CGFloat, rowCount: Int, estimatedRowHeight: CGFloat, visibleRows: Int = 5) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let shown = min(rowCount, visibleRows)
        guard contentHeight > 0 else { return estimatedRowHeight * CGFloat(shown) }
        return contentHeight * CGFloat(shown) / CGFloat(rowCount)
    }

    @ViewBuilder
    var podiumSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(title: "Podium", style: .subsection)

            Picker("Période du podium", selection: $podiumPeriod.animation(.easeInOut(duration: 0.2))) {
                ForEach(PodiumPeriod.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)

            switch podiumPeriod {
            case .yearly:
                if viewModel.yearlyListeningSessionsCount < StatsViewModel.minimumListeningSessionsForRanking {
                    notEnoughListeningDataCard("Pas assez d'écoutes cette année pour un podium pertinent (minimum \(StatsViewModel.minimumListeningSessionsForRanking)).")
                } else {
                    podiumStage(entries: viewModel.yearlyPodium)
                }
            case .monthly:
                if viewModel.monthlyListeningSessionsCount < StatsViewModel.minimumListeningSessionsForRanking {
                    notEnoughListeningDataCard("Pas assez d'écoutes ce mois-ci pour un podium pertinent (minimum \(StatsViewModel.minimumListeningSessionsForRanking)).")
                } else {
                    podiumStage(entries: viewModel.monthlyPodium)
                }
            }
        }
    }

    /// Podium stylisé façon estrade : les 3 pochettes posées sur des marches de hauteur
    /// décroissante (1ʳᵉ place au centre, plus haute), teintées or/argent/bronze.
    func podiumStage(entries: [TopAlbumEntry]) -> some View {
        let first = entries.first
        let second = entries.count > 1 ? entries[1] : nil
        let third = entries.count > 2 ? entries[2] : nil

        return HStack(alignment: .bottom, spacing: 10) {
            Spacer(minLength: 0)
            podiumColumn(entry: second, rank: 2)
            podiumColumn(entry: first, rank: 1)
            podiumColumn(entry: third, rank: 3)
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .appleMusicGroupedCard()
    }

    @ViewBuilder
    func podiumColumn(entry: TopAlbumEntry?, rank: Int) -> some View {
        if let entry {
            NavigationLink(value: SearchDestination.release(
                entry.item.releaseId,
                coverURL: entry.item.basicInformation.coverImage ?? entry.item.basicInformation.thumb
            )) {
                VStack(spacing: 6) {
                    AsyncCoverImage(url: entry.item.basicInformation.coverImage ?? entry.item.basicInformation.thumb, cornerRadius: AppLayout.coverCornerRadius, targetSize: podiumCoverSize(for: rank))
                        .frame(width: podiumCoverSize(for: rank), height: podiumCoverSize(for: rank))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)

                    Text(entry.item.basicInformation.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(entry.playCount) écoutes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.spinlogPink)
                        .lineLimit(1)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(podiumPedestalGradient(for: rank))
                        .frame(width: 76, height: podiumPedestalHeight(for: rank))
                        .overlay(alignment: .top) {
                            Text("\(rank)")
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.top, 6)
                        }
                }
                .frame(width: 86)
            }
            .buttonStyle(.plain)
        }
    }

    func podiumCoverSize(for rank: Int) -> CGFloat {
        switch rank {
        case 1: return 72
        case 2: return 60
        default: return 52
        }
    }

    func podiumPedestalHeight(for rank: Int) -> CGFloat {
        switch rank {
        case 1: return 64
        case 2: return 46
        default: return 32
        }
    }

    func podiumPedestalGradient(for rank: Int) -> LinearGradient {
        switch rank {
        case 1:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.85, blue: 0.4), Color(red: 0.82, green: 0.62, blue: 0.13)],
                startPoint: .top, endPoint: .bottom
            )
        case 2:
            return LinearGradient(
                colors: [Color(white: 0.85), Color(white: 0.64)],
                startPoint: .top, endPoint: .bottom
            )
        default:
            return LinearGradient(
                colors: [Color(red: 0.80, green: 0.55, blue: 0.35), Color(red: 0.62, green: 0.40, blue: 0.24)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    func topAlbumRow(rank: Int, entry: TopAlbumEntry) -> some View {
        NavigationLink(value: SearchDestination.release(
            entry.item.releaseId,
            coverURL: entry.item.basicInformation.coverImage ?? entry.item.basicInformation.thumb
        )) {
            HStack(spacing: 12) {
                rankBadge(rank)

                AsyncCoverImage(url: entry.item.basicInformation.coverImage ?? entry.item.basicInformation.thumb, cornerRadius: AppLayout.coverCornerRadius, targetSize: 44)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.item.basicInformation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.item.basicInformation.artistNames)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(entry.playCount) écoutes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    /// Ouvre la fiche de l'artiste (ou, pour une collaboration, du premier artiste crédité).
    @ViewBuilder
    func topArtistRow(rank: Int, entry: TopArtistEntry) -> some View {
        if let artist = entry.artists.first {
            NavigationLink(value: SearchDestination.artist(artist.id)) {
                topArtistRowContent(rank: rank, entry: entry, showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            topArtistRowContent(rank: rank, entry: entry, showsChevron: false)
        }
    }

    func topArtistRowContent(rank: Int, entry: TopArtistEntry, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            rankBadge(rank)

            ArtistThumbnailView(artistName: entry.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                // Même unité que le classement des albums (« écoutes », plus « sessions ») ; deux
                // textes imbriqués pour que chaque nombre ait sa propre règle de pluriel.
                Text("\(Text("\(entry.totalPlays) écoutes")) · \(Text("\(entry.releaseCount) disques"))")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTertiaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Photo circulaire de l'artiste récupérée sur Apple Music (voir
    /// `AppleMusicArtistArtworkService`), avec repli silencieux sur l'icône micro générique si
    /// l'autorisation est refusée, l'artiste n'est pas trouvé dans le catalogue, ou hors ligne.
    private struct ArtistThumbnailView: View {
        let artistName: String
        @State private var artworkURL: URL?

        var body: some View {
            Group {
                if let artworkURL {
                    KFImage(artworkURL)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "music.mic")
                                .font(.title3)
                                .foregroundStyle(Color.spinlogPink)
                        }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
            .task(id: artistName) {
                artworkURL = await AppleMusicArtistArtworkService.shared.artworkURL(for: artistName)
            }
        }
    }

    @ViewBuilder
    func rankBadge(_ rank: Int) -> some View {
        switch rank {
        case 1:
            Text("🥇").font(.title3).frame(width: 24)
        case 2:
            Text("🥈").font(.title3).frame(width: 24)
        case 3:
            Text("🥉").font(.title3).frame(width: 24)
        default:
            Text("\(rank)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.appTertiaryText)
                .frame(width: 24)
        }
    }

    func notEnoughListeningDataCard(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Color.appSecondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, 14)
            .appleMusicGroupedCard()
    }
}
