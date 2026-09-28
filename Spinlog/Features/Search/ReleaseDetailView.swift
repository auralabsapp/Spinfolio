import SwiftUI

struct ReleaseDetailView: View {
    let releaseId: Int

    @Environment(\.dismiss) private var dismiss

    @State private var release: Release?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actions = ReleaseActions()
    @State private var showingNotesSheet = false
    @State private var imageViewerRequest: ImageViewerRequest?

    var body: some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .disablesContentPopGesture()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.bold))
                            .liquidGlassCircle(size: 38)
                    }
                    .accessibilityLabel("Retour")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ReleaseActionsMenu(releaseId: releaseId, actions: actions)
                }
            }
            .sheet(isPresented: $showingNotesSheet) {
                if let item = actions.collectionInstance {
                    CollectionItemEditSheet(item: item, fields: actions.collectionFields) { rating, notes in
                        actions.applyEditedValues(rating: rating, notes: notes)
                    }
                }
            }
            .fullScreenCover(item: $imageViewerRequest) { request in
                ImageViewerView(images: release?.images ?? [], startIndex: request.startIndex)
            }
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView(
                "Impossible de charger la release",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if let release {
            ScrollView {
                VStack(spacing: 0) {
                    parallaxHeroCover(for: release)

                    // Zone d'informations glissant par-dessus la jaquette avec effet parallaxe
                    VStack(alignment: .leading, spacing: 24) {
                        if let community = release.community {
                            CommunityRatingRow(community: community)
                        }

                        let tags = (release.genres ?? []) + (release.styles ?? [])
                        if !tags.isEmpty {
                            GenreTagsRow(tags: tags)
                        }

                        if let item = actions.collectionInstance {
                            NotesTile(item: item) { showingNotesSheet = true }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tags").font(.headline)
                            TagsEditor(releaseId: release.id)
                        }

                        ReleaseInfoCard(release: release)

                        if let videos = release.videos, !videos.isEmpty {
                            ReleaseVideosSection(videos: videos)
                        }

                        if let images = release.images, images.count > 1 {
                            ReleaseImagesGallery(images: images) { index in
                                imageViewerRequest = ImageViewerRequest(startIndex: index)
                            }
                        }

                        if let tracklist = release.tracklist, !tracklist.isEmpty {
                            TracklistSection(tracklist: tracklist)
                        }

                        if let credits = release.extraartists, !credits.isEmpty {
                            CreditsSection(credits: credits)
                        }

                        if let notes = release.notes, !notes.isEmpty {
                            NotesSection(notes: notes)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 24,
                            topTrailingRadius: 24,
                            style: .continuous
                        )
                    )
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: -4)
                    .offset(y: -20)
                }
            }
            .coordinateSpace(name: "releaseScroll")
            .ignoresSafeArea(edges: .top)
        }
    }

    private func parallaxHeroCover(for release: Release) -> some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("releaseScroll")).minY
            let width = proxy.size.width
            let height = width

            // Détection du scroll vers le haut (swipe up) : minY < 0
            let scrollUp = max(0, -minY)
            // Étirement fluide si traction vers le bas (pull-down rubberband) : minY > 0
            let pullDown = max(0, minY)

            // Progression du swipe up (0.0 au repos -> 1.0 quand scrollé de 70% de la hauteur de jaquette)
            let progress = min(1.0, scrollUp / (height * 0.70))

            // Floutage progressif : de 0 pt (net) à 24 pt (flou d'arrière-plan complet)
            let blurRadius = progress * 24.0

            // Disparition progressive de la jaquette
            let coverOpacity = max(0.0, 1.0 - (progress * 0.95))

            // Disparition rapide du titre et groupe superposés sur le premier tiers de scroll
            let textOpacity = max(0.0, 1.0 - (scrollUp / 120.0))

            // Effet parallaxe : la jaquette monte 2 fois moins vite que le défilement
            let parallaxOffset = scrollUp * 0.5

            ZStack(alignment: .bottomLeading) {
                AsyncCoverImage(url: release.primaryImageURL, cornerRadius: 0, showsBorder: false)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: width, height: height + pullDown)
                    .clipped()
                    .blur(radius: blurRadius)
                    .opacity(coverOpacity)
                    .offset(y: -pullDown + parallaxOffset)

                // Dégradé sombre inférieur qui s'estompe avec le texte
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.4), location: 0.45),
                        .init(color: .black.opacity(0.85), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .opacity(textOpacity)
                .offset(y: parallaxOffset)

                // Nom de l'album et groupe en superposition
                VStack(alignment: .leading, spacing: 6) {
                    Text(release.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)

                    if !release.artistNames.isEmpty {
                        Text(release.artistNames)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .opacity(textOpacity)
                .offset(y: parallaxOffset)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let images = release.images, !images.isEmpty else { return }
                imageViewerRequest = ImageViewerRequest(startIndex: 0)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            release = try await DiscogsAPIClient.shared.release(
                id: releaseId, credentials: DiscogsAuthManager.shared.credentials
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        await actions.checkIfInCollection(releaseId: releaseId)
    }
}

struct TracklistSection: View {
    let tracklist: [Track]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Titres").font(.headline)
            ForEach(tracklist) { track in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .frame(width: 22, height: 22)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(track.position)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                    Text(track.title)
                    Spacer()
                    if let duration = track.duration, !duration.isEmpty {
                        Text(duration).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let totalDuration {
                Divider()
                HStack {
                    Text("Durée totale").font(.subheadline.bold())
                    Spacer()
                    Text(totalDuration).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var totalDuration: String? {
        let totalSeconds = tracklist.compactMap { seconds(from: $0.duration) }.reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func seconds(from duration: String?) -> Int? {
        guard let duration, let colonIndex = duration.firstIndex(of: ":") else { return nil }
        let minutesPart = duration[..<colonIndex]
        let secondsPart = duration[duration.index(after: colonIndex)...]
        guard let minutes = Int(minutesPart), let seconds = Int(secondsPart) else { return nil }
        return minutes * 60 + seconds
    }
}

struct CreditsSection: View {
    let credits: [ReleaseArtist]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Crédits").font(.headline)
            ForEach(credits) { credit in
                HStack {
                    NavigationLink(value: SearchDestination.artist(credit.id)) {
                        Text(credit.name)
                    }
                    Spacer()
                    Text(credit.role ?? "").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }
}

struct NotesSection: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").font(.headline)
            Text(notes).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        ReleaseDetailView(releaseId: 249504)
    }
}
