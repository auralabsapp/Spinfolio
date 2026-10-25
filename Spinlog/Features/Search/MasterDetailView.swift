import SwiftUI

struct MasterDetailView: View {
    /// Partagée entre la vraie pochette et `masterDetailSkeleton`, pour que le squelette ne
    /// puisse pas diverger silencieusement de la taille réelle.
    private static let coverSize: CGFloat = 220

    let masterId: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = MasterDetailViewModel()

    private var infoBackgroundColor: Color {
        if let averageColor = viewModel.averageColor {
            return averageColor.infoBackgroundColor(for: colorScheme)
        }
        return Color(uiColor: .systemBackground)
    }

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
            .navigationTitle(viewModel.master?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .disablesContentPopGesture()
            .task { await viewModel.loadIfNeeded(masterId: masterId) }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            masterDetailSkeleton
                .background(infoBackgroundColor.ignoresSafeArea())
                .transition(.opacity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Impossible de charger ce master", systemImage: "exclamationmark.triangle")
            } description: {
                // Hors ligne : la raison réelle plutôt que le message technique de l'erreur réseau.
                NetworkMonitor.shared.isConnected ? Text(errorMessage) : Text("Cette fiche nécessite une connexion réseau.")
            } actions: {
                Button("Réessayer") {
                    Task { await viewModel.load(masterId: masterId) }
                }
                .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(infoBackgroundColor.ignoresSafeArea())
        } else if let master = viewModel.master {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Même bandeau que la fiche artiste : la page reste affichée mais ne se met plus à jour.
                    if !NetworkMonitor.shared.isConnected {
                        OfflineBannerView(customMessage: String(localized: "Hors ligne : cette page ne se met plus à jour."))
                    }
                    AsyncCoverImage(
                        url: master.primaryImageURL,
                        cornerRadius: 12,
                        onAverageColorLoaded: { color in
                            ReleaseColorCache.shared.register(color: color, url: master.primaryImageURL)
                            withAnimation(.easeInOut(duration: 0.35)) {
                                viewModel.averageColor = color
                            }
                        }
                    )
                    .frame(width: Self.coverSize, height: Self.coverSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                    .frame(maxWidth: .infinity)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.16), radius: 16, y: 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(master.title).font(.title2.bold())
                        if !master.artistNames.isEmpty {
                            Text(master.artistNames).font(.headline).foregroundStyle(Color.appSecondaryText)
                        }
                        if let year = master.year {
                            InfoBadge(systemImage: "calendar", text: String(year))
                        }
                    }

                    if let tracklist = master.tracklist, !tracklist.isEmpty {
                        TracklistSection(
                            tracklist: tracklist,
                            artistName: master.artistNames,
                            albumTitle: master.title,
                            coverURL: master.primaryImageURL,
                            destination: .master(master.id)
                        )
                    }

                    if !viewModel.versions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Pressages (\(viewModel.versions.count))").font(.headline)
                            // `LazyVStack` plutôt que `VStack` : un master populaire peut avoir
                            // 50-150 pressages, et un `VStack` classique dans une `ScrollView`
                            // instancie et décode d'un coup toutes leurs pochettes à l'ouverture,
                            // provoquant un à-coup. `targetSize` évite en plus un décodage en
                            // pleine résolution pour une miniature de 44pt.
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(viewModel.versions) { version in
                                    NavigationLink(value: SearchDestination.release(version.id, coverURL: version.thumb)) {
                                        HStack(spacing: 12) {
                                            AsyncCoverImage(url: version.thumb, cornerRadius: 6, targetSize: 44)
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                                )
                                                .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                                                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text([version.format, version.label].compactMap { $0 }.joined(separator: " · "))
                                                    .font(.subheadline)
                                                Text([version.country, version.released].compactMap { $0 }.joined(separator: " · "))
                                                    .font(.caption)
                                                    .foregroundStyle(Color.appSecondaryText)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if let url = master.discogsWebURL {
                        DiscogsAttributionLink(url: url)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding()
            }
            .background(infoBackgroundColor.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.35), value: infoBackgroundColor)
            .onAppear {
                TabNavigationCoordinator.shared.registerTopDestination(.master(masterId))
            }
            .onDisappear {
                TabNavigationCoordinator.shared.unregisterTopDestination(.master(masterId))
            }
            .transition(.opacity)
        }
    }

    /// Gabarit neutre affiché pendant le chargement, à la place d'une icône de chargement :
    /// reproduit la structure réelle (pochette centrée, titre/artiste/année, puis des sections
    /// titre + contenu pour la tracklist et les pressages) avec des blocs animés (voir
    /// `SkeletonBlock`), pour que l'apparition du contenu réel ne fasse pas sauter la page.
    private var masterDetailSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SkeletonBlock(cornerRadius: 12, width: Self.coverSize, height: Self.coverSize)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(width: 200, height: 22)
                    SkeletonBlock(width: 140, height: 17)
                    SkeletonBlock(cornerRadius: 10, width: 70, height: 20)
                }

                SkeletonSection(titleWidth: 90, contentHeight: 160)
                SkeletonSection(titleWidth: 130, contentHeight: 150)
            }
            .padding()
        }
        .scrollDisabled(true)
    }
}
