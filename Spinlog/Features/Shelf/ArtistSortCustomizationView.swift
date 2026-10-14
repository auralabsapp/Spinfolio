import SwiftUI

/// Vue permettant à l'utilisateur de consulter et personnaliser la clé de tri de chaque artiste de sa collection.
struct ArtistSortCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shelfPreferences = ShelfPreferencesStore.shared
    @State private var searchText = ""
    @State private var editingArtist: String? = nil
    @State private var showingResetConfirmation = false
    @State private var filterMode: FilterMode = .all
    /// Lecture disque (`getAllCollectionItemsSync`) mise en cache une seule fois à l'apparition de
    /// l'écran, plutôt que refaite à chaque frappe dans la recherche : `allArtists` (et donc
    /// `filteredArtists`) était recalculée — relecture disque comprise — à chaque caractère tapé.
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

    private func loadCollectionArtists() {
        guard let username = DiscogsAuthManager.shared.username else {
            collectionArtists = []
            return
        }
        let items = LocalDataStore.shared.getAllCollectionItemsSync(username: username)
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
                }
            }
        }
        .navigationTitle("Tri des artistes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Rechercher un artiste...")
        .task {
            loadCollectionArtists()
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

private struct ArtistEditPayload: Identifiable {
    let artist: String
    var id: String { artist }
}

private struct ArtistSortRow: View {
    let artist: String
    let customOverride: String?
    let effectiveKey: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(artist)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)

                    HStack(spacing: 6) {
                        Text("Classé comme :")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)

                        Text(effectiveKey)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(customOverride != nil ? Color.spinlogPink : Color.primary)
                    }
                }

                Spacer()

                if customOverride != nil {
                    Text("Personnalisé")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.spinlogPink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.spinlogPink.opacity(0.12), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appTertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ArtistSortEditSheet: View {
    let artist: String
    @Environment(\.dismiss) private var dismiss
    @State private var shelfPreferences = ShelfPreferencesStore.shared
    @State private var sortKey: String = ""

    private var naturalKey: String {
        artist
    }

    private var coreAndArticle: (core: String, article: String?) {
        artist.extractingInitialArticle()
    }

    private var hasArticle: Bool {
        coreAndArticle.article != nil
    }

    private var articleKey: String {
        artist.normalizedForArtistSorting(ignoreArticles: true)
    }

    private var invertedKey: String {
        let core = coreAndArticle.core
        let words = core.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count == 2 {
            return "\(words[1]), \(words[0])"
        } else if words.count == 3 {
            return "\(words[2]), \(words[0]) \(words[1])"
        }
        return core
    }

    private var defaultKey: String {
        artist.shelfArtistSortKey(
            ignoreArticles: shelfPreferences.ignoreArticles,
            sortByLastName: shelfPreferences.sortByLastName,
            overrides: [:]
        )
    }

    private var isCustomized: Bool {
        shelfPreferences.customSort(for: artist) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                scrollContent
            }
            .navigationTitle("Éditer le tri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.spinlogPink)
                }
            }
            .onAppear {
                sortKey = shelfPreferences.customSort(for: artist) ?? defaultKey
            }
        }
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
    }

    private var scrollContent: some View {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Carte En-tête Artiste
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.spinlogPink.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "music.mic")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.spinlogPink)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Artiste")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.appSecondaryText)
                            Text(artist)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if isCustomized {
                            Text("Personnalisé")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.spinlogPink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.spinlogPink.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(14)
                    .appleMusicGroupedCard()

                    // 2. Carte Saisie libre
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "textformat")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.spinlogPink)
                            Text("Nom utilisé pour le classement")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appSecondaryText)
                                .textCase(.uppercase)
                        }
                        .padding(.leading, 4)

                        HStack(spacing: 10) {
                            TextField("Clé de tri (ex: Bowie, David)", text: $sortKey)
                                .font(.body.weight(.medium))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.words)

                            if !sortKey.isEmpty {
                                Button {
                                    sortKey = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.appTertiaryText)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Effacer")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .appleMusicGroupedCard()

                        Text("Détermine la place alphabétique de tous les albums de cet artiste.")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                            .padding(.horizontal, 6)
                    }

                    // 3. Carte Suggestions rapides
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.spinlogPink)
                            Text("Suggestions de classement")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appSecondaryText)
                                .textCase(.uppercase)
                        }
                        .padding(.leading, 4)

                        VStack(spacing: 0) {
                            // Option 1 : Ordre direct
                            suggestionRow(
                                title: "Ordre direct",
                                value: naturalKey,
                                isSelected: sortKey == naturalKey
                            ) {
                                withAnimation(.snappy(duration: 0.2)) {
                                    sortKey = naturalKey
                                }
                            }

                            // Option 2 : Article à la fin
                            if hasArticle && articleKey != naturalKey {
                                Divider()
                                    .padding(.leading, 14)

                                suggestionRow(
                                    title: "Article à la fin",
                                    value: articleKey,
                                    isSelected: sortKey == articleKey
                                ) {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        sortKey = articleKey
                                    }
                                }
                            }

                            // Option 3 : Inversé (Nom, Prénom)
                            if !hasArticle && invertedKey != naturalKey {
                                Divider()
                                    .padding(.leading, 14)

                                suggestionRow(
                                    title: "Inversé (Nom, Prénom)",
                                    value: invertedKey,
                                    isSelected: sortKey == invertedKey
                                ) {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        sortKey = invertedKey
                                    }
                                }
                            }
                        }
                        .appleMusicGroupedCard()
                    }

                    // 4. Action Rétablir (si personnalisé)
                    if isCustomized {
                        Button(role: .destructive) {
                            withAnimation(.snappy(duration: 0.2)) {
                                shelfPreferences.setCustomSort(for: artist, sortKey: nil)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.subheadline.weight(.semibold))
                                Text("Rétablir le tri automatique")
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func suggestionRow(
        title: LocalizedStringResource,
        value: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary)
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.spinlogPink : Color.appSecondaryText)
                }

                Spacer()

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.spinlogPink : Color.appTertiaryText, lineWidth: 1.5)
                        .frame(width: 20, height: 20)

                    if isSelected {
                        Circle()
                            .fill(Color.spinlogPink)
                            .frame(width: 11, height: 11)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmed = sortKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultKey {
            shelfPreferences.setCustomSort(for: artist, sortKey: nil)
        } else {
            shelfPreferences.setCustomSort(for: artist, sortKey: trimmed)
        }
        dismiss()
    }
}

#Preview {
    ArtistSortEditSheet(artist: "The Beatles")
}
