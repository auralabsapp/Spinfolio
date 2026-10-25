import SwiftUI

/// Vue permettant à l'utilisateur de consulter et personnaliser la clé de tri de chaque artiste de sa collection.
struct ArtistSortCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shelfPreferences = ShelfPreferencesStore.shared
    @State private var searchText = ""
    @State private var editingArtist: String? = nil
    @State private var showingResetConfirmation = false
    @State private var filterMode: FilterMode = .all
    /// Lecture disque mise en cache une seule fois à l'apparition de l'écran, plutôt que refaite
    /// à chaque frappe dans la recherche : `allArtists` (et donc `filteredArtists`) était
    /// recalculée — relecture disque comprise — à chaque caractère tapé. Décodée hors du fil
    /// principal (`loadAllCollectionItems`).
    @State private var collectionArtists: [String] = []

    enum FilterMode: String, CaseIterable, Identifiable {
        case all = "Tous"
        case customized = "Personnalisés"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "Tous")
            case .customized: return String(localized: "Personnalisés")
            }
        }
    }

    private var allArtists: [String] {
        var artistSet = Set(collectionArtists)
        for customArtist in shelfPreferences.customArtistSortOverrides.keys {
            artistSet.insert(customArtist)
        }
        return artistSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func loadCollectionArtists() async {
        guard let username = DiscogsAuthManager.shared.username else {
            collectionArtists = []
            return
        }
        let items = await LocalDataStore.shared.loadAllCollectionItems(username: username)
        var artistSet = Set<String>()
        for item in items {
            let cleaned = ArtistShelfSortHelper.cleanDiscogsSuffix(item.basicInformation.artistNames)
            if !cleaned.isEmpty {
                artistSet.insert(cleaned)
            }
        }
        collectionArtists = Array(artistSet)
    }

    private var filteredArtists: [String] {
        allArtists.filter { artist in
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let query = searchText.lowercased()
                let currentSort = shelfPreferences.customSort(for: artist) ?? artist.shelfArtistSortKey(
                    ignoreArticles: shelfPreferences.ignoreArticles,
                    sortByLastName: shelfPreferences.sortByLastName,
                    overrides: shelfPreferences.customArtistSortOverrides
                )
                matchesSearch = artist.lowercased().contains(query) || currentSort.lowercased().contains(query)
            }

            switch filterMode {
            case .all:
                return matchesSearch
            case .customized:
                return matchesSearch && shelfPreferences.customSort(for: artist) != nil
            }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personnalisation du tri")
                        .font(.subheadline.weight(.semibold))
                    Text("Définis comment chaque artiste doit être ordonné dans tous tes tris par artiste (meuble physique, Collection et Wantlist). Tes règles personnalisées sont prioritaires.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("Filtre", selection: $filterMode) {
                    ForEach(FilterMode.allCases) { mode in
                        if mode == .customized {
                            Text("\(mode.title) (\(shelfPreferences.customArtistSortOverrides.count))").tag(mode)
                        } else {
                            Text("\(mode.title) (\(allArtists.count))").tag(mode)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if filteredArtists.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: filterMode == .customized ? "slider.horizontal.3" : "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(Color.appSecondaryText)
                        Text(filterMode == .customized ? "Aucun artiste personnalisé pour l'instant" : "Aucun artiste trouvé")
                            .font(.subheadline)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(filteredArtists, id: \.self) { artist in
                        ArtistSortRow(
                            artist: artist,
                            customOverride: shelfPreferences.customSort(for: artist),
                            effectiveKey: artist.shelfArtistSortKey(
                                ignoreArticles: shelfPreferences.ignoreArticles,
                                sortByLastName: shelfPreferences.sortByLastName,
                                overrides: shelfPreferences.customArtistSortOverrides
                            ),
                            onTap: {
                                editingArtist = artist
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if shelfPreferences.customSort(for: artist) != nil {
                                Button(role: .destructive) {
                                    shelfPreferences.setCustomSort(for: artist, sortKey: nil)
                                } label: {
                                    Label("Rétablir", systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }

            if !shelfPreferences.customArtistSortOverrides.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Réinitialiser toutes les personnalisations")
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .listRowSeparatorTint(Color.appSeparator)
        .navigationTitle("Tri des artistes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Rechercher un artiste...")
        .task {
            await loadCollectionArtists()
        }
        .sheet(item: Binding(
            get: { editingArtist.map { ArtistEditPayload(artist: $0) } },
            set: { editingArtist = $0?.artist }
        )) { payload in
            ArtistSortEditSheet(artist: payload.artist)
        }
        .confirmationDialog(
            "Réinitialiser toutes les personnalisations ?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Réinitialiser", role: .destructive) {
                shelfPreferences.resetAllOverrides()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Toutes tes règles personnalisées d'ordonnancement d'artistes seront effacées.")
        }
    }
}

#Preview {
    ArtistSortEditSheet(artist: "The Beatles")
}
