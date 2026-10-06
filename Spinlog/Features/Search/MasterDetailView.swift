import SwiftUI

struct MasterDetailView: View {
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
            .navigationTitle(viewModel.master?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .disablesContentPopGesture()
            .task { await viewModel.load(masterId: masterId) }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(infoBackgroundColor.ignoresSafeArea())
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "Impossible de charger ce master",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(infoBackgroundColor.ignoresSafeArea())
        } else if let master = viewModel.master {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                    .frame(width: 220, height: 220)
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
                            ForEach(viewModel.versions) { version in
                                NavigationLink(value: SearchDestination.release(version.id, coverURL: version.thumb)) {
                                    HStack(spacing: 12) {
                                        AsyncCoverImage(url: version.thumb, cornerRadius: 6)
                                            .frame(width: 44, height: 44)
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
        }
    }
}
