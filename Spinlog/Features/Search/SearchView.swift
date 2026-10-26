import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel.shared
    @State private var isScannerPresented = false
    @State private var isBatchScannerPresented = false
    @State private var premiumStore = PremiumStore.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var showingPremiumSheet = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var suggestionIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activityManager = NowPlayingActivityManager.shared
    private var membership = LibraryMembershipStore.shared



    var body: some View {
        // Hors ligne, l'état vide « Recherche indisponible hors ligne » suffit : le bandeau en tête
        // répétait le même message.
        VStack(spacing: 12) {
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
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Recherche")
        .serifNavigationTitle()
        .searchDestinations()
        .fullScreenCover(isPresented: $isScannerPresented) {
            scannerSheet
        }
        .fullScreenCover(isPresented: $isBatchScannerPresented) {
            BatchScanView()
        }
        .premiumFeaturesSheet(isPresented: $showingPremiumSheet)
        // `.onChange` plutôt que `.task(id:)` : ce dernier se relance à chaque réapparition
        // de la vue (ex. retour d'une fiche détail via le bouton précédent) même quand la
        // requête n'a pas changé, ce qui remplaçait `results` et remettait le scroll à zéro.
        .onChange(of: viewModel.query) { _, _ in scheduleSearch() }
        .onChange(of: viewModel.scope) { _, _ in scheduleSearch() }
        .task {
            membership.refresh()
        }

    }

    private func scheduleSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            if viewModel.consumeSuppressFlag() { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.search()
        }
    }

    /// Barre de recherche personnalisée
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appSecondaryText)

            // Le texte d'invite tourne parmi quelques suggestions : il est dessiné en surimpression
            // (un `prompt` ne s'anime pas), le champ garde l'invite d'origine pour VoiceOver.
            TextField("", text: $viewModel.query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .accessibilityLabel("Artiste, disque, label, code-barre…")
                .overlay(alignment: .leading) {
                    if viewModel.query.isEmpty {
                        SearchSuggestion(index: suggestionIndex)
                            .foregroundStyle(Color.appTertiaryText)
                            .lineLimit(1)
                            .id(suggestionIndex)
                            .motionTransition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .clipped()
                .task(id: viewModel.query.isEmpty && !isSearchFieldFocused) {
                    // Rotation seulement quand le champ est vide et au repos, et sans « Réduire les animations ».
                    guard viewModel.query.isEmpty, !isSearchFieldFocused, !reduceMotion else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            suggestionIndex = (suggestionIndex + 1) % SearchSuggestion.count
                        }
                    }
                }

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

            Divider().overlay(Color.appSeparator).frame(height: 18)

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
                        // Démo : fonction débloquée, mais signalée comme Premium (voir
                        // `DemoPremiumBadge`) — trop peu de place ici pour l'étiquette entière.
                        .overlay(alignment: .topTrailing) {
                            if premiumStore.showsDemoPremiumBadges {
                                goldCornerBadge(systemName: "sparkles")
                            }
                        }
                        .padding(.trailing, premiumStore.showsDemoPremiumBadges ? 2 : 0)
                } else {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.goldAccent)
                        .overlay(alignment: .topTrailing) {
                            goldCornerBadge(systemName: "lock.fill")
                        }
                        .padding(.trailing, 2)
                }
            }
            .buttonStyle(.plain)
            // Seulement si premium : un non-premium doit toujours pouvoir ouvrir le paywall,
            // lui-même sans dépendance réseau.
            .disabled(premiumStore.isPremium && !networkMonitor.isConnected)
            .accessibilityLabel(premiumStore.isPremium && !premiumStore.showsDemoPremiumBadges ? Text("Scan par lot") : Text("Scan par lot (Premium)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    /// Pastille dorée 12×12 posée sur l'icône du scan par lot : cadenas sans Premium, étincelles
    /// pendant l'aperçu de la démo.
    private func goldCornerBadge(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.goldButtonGradient)
                .frame(width: 12, height: 12)

            // Taille isolée (pas de token partagé) : ce badge fait 12×12 fixe,
            // plus petit que tous les autres contextes d'icône de l'app.
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .offset(x: 5, y: -5)
    }

    private var scopePicker: some View {
        Picker("Filtrer", selection: $viewModel.scope) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
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
            CameraScannerGate {
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
            }
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
            ContentUnavailableView {
                Label("Recherche impossible", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Réessayer") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.glassProminent)
                .foregroundStyle(Color.onAccent)
            }
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
            ScrollViewReader { proxy in
                List(viewModel.results) { result in
                    SearchResultRow(result: result)
                        .task { await viewModel.loadMoreIfNeeded(current: result) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            leadingSwipeActions(for: result)
                        }
                        // Même action par appui long (seul accès sur iOS 26).
                        .contextMenu { leadingSwipeActions(for: result) }
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowSeparatorTint(Color.appSeparator)
                .scrollDismissesKeyboard(.immediately)
                .refreshable {
                    await viewModel.search()
                }
                .onChange(of: TabNavigationCoordinator.shared.scrollToTopOfSearchTrigger) {
                    guard let first = viewModel.results.first else { return }
                    withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                }
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
        let (artist, album) = parseArtistAndAlbum(from: result.title)
        NowPlayingActivityManager.shared.startListening(
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

/// Texte d'invite du champ de recherche, tournant parmi quelques suggestions (la première est
/// l'invite d'origine).
private struct SearchSuggestion: View {
    static let count = 5

    let index: Int

    var body: some View {
        switch index {
        case 1: Text("Cherche un artiste…")
        case 2: Text("Cherche un album…")
        case 3: Text("Cherche un label…")
        case 4: Text("Tape un code-barres…")
        default: Text("Artiste, disque, label, code-barre…")
        }
    }
}
