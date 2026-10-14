import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel.shared
    @State private var isScannerPresented = false
    @State private var isBatchScannerPresented = false
    @State private var premiumStore = PremiumStore.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var showingPremiumSheet = false
    @FocusState private var isSearchFieldFocused: Bool

    private var activityManager = NowPlayingActivityManager.shared
    private var membership = LibraryMembershipStore.shared



    var body: some View {
        VStack(spacing: 12) {
            if !networkMonitor.isConnected {
                OfflineBannerView(customMessage: String(localized: "La recherche nécessite une connexion réseau"))
            }
            searchBar
            scopePicker
            content
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isSearchFieldFocused = false
                }
        )
        .navigationTitle("Recherche")
        .searchDestinations()
        .fullScreenCover(isPresented: $isScannerPresented) {
            scannerSheet
        }
        .fullScreenCover(isPresented: $isBatchScannerPresented) {
            BatchScanView()
        }
        .premiumFeaturesSheet(isPresented: $showingPremiumSheet)
        .task(id: "\(viewModel.query)|\(viewModel.scope.rawValue)") {
            if viewModel.consumeSuppressFlag() { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.search()
        }
        .task {
            membership.refresh()
        }

    }

    /// Barre de recherche personnalisée
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appSecondaryText)

            TextField("Artiste, disque, label, code-barre…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appSecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }

            Divider().frame(height: 18)

            Button {
                isSearchFieldFocused = false
                isScannerPresented = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .foregroundStyle(networkMonitor.isConnected ? Color.spinlogPink : Color.appTertiaryText)
            }
            .buttonStyle(.plain)
            .disabled(!networkMonitor.isConnected)
            .accessibilityLabel("Rechercher par scan")

            Button {
                isSearchFieldFocused = false
                if premiumStore.isPremium {
                    isBatchScannerPresented = true
                } else {
                    showingPremiumSheet = true
                }
            } label: {
                if premiumStore.isPremium {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.spinlogPink)
                } else {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color(red: 0.92, green: 0.62, blue: 0.16))

                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.78, blue: 0.28),
                                            Color(red: 0.88, green: 0.52, blue: 0.12)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 12, height: 12)

                            Image(systemName: "lock.fill")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 5, y: -5)
                    }
                    .padding(.trailing, 2)
                }
            }
            .buttonStyle(.plain)
            // Seulement si premium : un non-premium doit toujours pouvoir ouvrir le paywall,
            // lui-même sans dépendance réseau.
            .disabled(premiumStore.isPremium && !networkMonitor.isConnected)
            .accessibilityLabel(premiumStore.isPremium ? "Scan par lot" : "Scan par lot (Premium)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    private var scopePicker: some View {
        Picker("Filtrer", selection: $viewModel.scope) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: viewModel.scope) {
            isSearchFieldFocused = false
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            BarcodeScannerRepresentable(
                onScan: { payload in
                    isScannerPresented = false
                    Task { await viewModel.searchByBarcode(payload) }
                },
                onError: { error in
                    isScannerPresented = false
                    viewModel.reportScannerError(error.localizedDescription)
                }
            )
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Annuler") { isScannerPresented = false }
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ViewBuilder
    private var content: some View {
        let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)

        if !networkMonitor.isConnected {
            ContentUnavailableView(
                "Recherche indisponible hors ligne",
                systemImage: "wifi.slash",
                description: Text("La recherche Discogs nécessite une connexion réseau.")
            )
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "Recherche impossible",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if trimmed.isEmpty {
            ContentUnavailableView(
                "Recherche Discogs",
                systemImage: "magnifyingglass",
                description: Text("Trouve un disque, un artiste, un label, ou scanne un code-barres.")
            )
        } else if viewModel.isLoading && viewModel.results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.results.isEmpty {
            ContentUnavailableView.search(text: trimmed)
        } else {
            List(viewModel.results) { result in
                SearchResultRow(result: result)
                    .task { await viewModel.loadMoreIfNeeded(current: result) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        leadingSwipeActions(for: result)
                    }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            // `.scrollDismissesKeyboard` ne réagit qu'au défilement, et le tap sur le fond de
            // `VStack` ci-dessus n'est jamais atteint quand on touche directement une ligne (son
            // propre geste de tap/navigation l'intercepte avant) : sans ce `.simultaneousGesture`
            // (qui se déclenche EN PLUS du tap de la ligne, pas à sa place), toucher un résultat
            // pendant que le clavier est ouvert laissait celui-ci affiché par-dessus la navigation.
            .simultaneousGesture(
                TapGesture().onEnded {
                    isSearchFieldFocused = false
                }
            )
            .refreshable {
                await viewModel.search()
            }
        }
    }

    // MARK: - Swipe Actions (Lecture / Stop uniquement)

    @ViewBuilder
    private func leadingSwipeActions(for result: SearchResult) -> some View {
        if result.isRelease && membership.isInCollection(result.id) {
            if activityManager.isPlaying(releaseId: result.id) {
                Button {
                    stopListening(for: result)
                } label: {
                    Label("Arrêter l'écoute", systemImage: "stop.fill")
                }
                .tint(Color(uiColor: .systemGray))
            } else {
                Button {
                    triggerListeningLog(for: result)
                } label: {
                    Label("J'écoute", systemImage: "opticaldisc.fill")
                }
                .tint(Color.spinlogPink)
            }
        }
    }

    // MARK: - Listening Actions & Toasts

    private func stopListening(for result: SearchResult) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await NowPlayingActivityManager.shared.endActivity(for: result.id)
        }
    }

    private func triggerListeningLog(for result: SearchResult) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        ListeningLogStore.shared.logListening(for: result.id)

        let (artist, album) = parseArtistAndAlbum(from: result.title)
        NowPlayingActivityManager.shared.startActivity(
            releaseId: result.id,
            albumTitle: album,
            artistName: artist,
            coverURL: result.thumb ?? result.coverImage
        )
    }

    private func parseArtistAndAlbum(from title: String) -> (artist: String, album: String) {
        if title.contains(" - ") {
            let parts = title.components(separatedBy: " - ")
            let artist = parts.first ?? ""
            let album = parts.dropFirst().joined(separator: " - ")
            return (artist, album)
        }
        return ("", title)
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}
