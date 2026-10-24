import SwiftUI

/// Page « Organisation » de Réglages : les tags, les dossiers Discogs (dont le dossier d'ajout par
/// défaut) et la personnalisation du tri par artiste. Les règles de rangement du meuble ont leur
/// propre page (`ShelvingSettingsPage`).
struct OrganizationSettingsPage: View {
    @State private var tagStore = TagStore.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var shelfPreferences = ShelfPreferencesStore.shared
    @State private var defaultFolderId: Int = CollectionPreferencesStore.alwaysAskFolderId

    var body: some View {
        SettingsSubPage(title: "Organisation") {
            Section {
                NavigationLink(value: SettingsDestination.tags) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "tag.fill", backgroundColor: .orange)
                        Text("Gestion des tags")
                        Spacer()
                        let count = tagStore.allTags.count
                        Text(count == 0 ? "Aucun" : "\(count)")
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }

                if authManager.isAuthenticated {
                    NavigationLink(value: SettingsDestination.folders) {
                        HStack(spacing: 14) {
                            SettingsIcon(systemName: "folder.fill", backgroundColor: .blue)
                            Text("Gestion des dossiers")
                            Spacer()
                            Text(defaultFolderName)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
            } header: {
                SectionEyebrow(title: "Organisation", icon: "tag.fill")
            } footer: {
                Text("Personnalise tes tags et tes dossiers Discogs, dont le dossier d'enregistrement par défaut.")
            }

            Section {
                Toggle(isOn: $shelfPreferences.ignoreArticles) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "text.quote", backgroundColor: .teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ignorer les articles (The...)")
                                .foregroundStyle(.primary)
                            Text("Ex : « Beatles, The » si actif, sinon « The Beatles »")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .tint(Color.spinlogPink)

                Toggle(isOn: $shelfPreferences.sortByLastName) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "person.text.rectangle", backgroundColor: .purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trier par nom de famille")
                                .foregroundStyle(.primary)
                            Text("S'applique à tous les tris par artiste (meuble, Collection, Wantlist)")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .tint(Color.spinlogPink)

                if shelfPreferences.sortByLastName {
                    NavigationLink(value: SettingsDestination.artistSort) {
                        HStack(spacing: 14) {
                            SettingsIcon(systemName: "slider.horizontal.3", backgroundColor: .pink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Personnaliser le tri des artistes")
                                    .foregroundStyle(.primary)
                                let count = shelfPreferences.customArtistSortOverrides.count
                                Text(count > 0 ? "\(count) artistes personnalisés" : "Ajuster l'ordre artiste par artiste")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                        }
                    }
                }
            } header: {
                SectionEyebrow(title: "Personnalisation du tri par artiste", icon: "person.text.rectangle")
            } footer: {
                Text("Ces réglages valent pour le meuble, la Collection et la Wantlist.")
            }
        }
        // La ligne « Personnaliser le tri des artistes » apparaît ou disparaît avec le réglage qui la commande.
        .animatesSettingsChanges(value: shelfPreferences.sortByLastName)
        .task { loadDefaultFolder() }
        // Un dossier par défaut modifié depuis un autre appareil (iCloud) ne rafraîchirait pas ce
        // `@State`, chargé une seule fois à l'apparition.
        .onReceive(NotificationCenter.default.publisher(for: .collectionPreferencesChanged)) { _ in
            loadDefaultFolder()
        }
    }

    private func loadDefaultFolder() {
        guard let username = authManager.username else { return }
        defaultFolderId = CollectionPreferencesStore.defaultAddFolderId(for: username)
    }

    private var defaultFolderName: String {
        if defaultFolderId == CollectionPreferencesStore.alwaysAskFolderId {
            return String(localized: "Toujours demander")
        }
        return CollectionViewModel.shared.folders.first { $0.id == defaultFolderId }?.name ?? ""
    }
}

/// Page « Rangement » de Réglages : la règle de classement du meuble et les options de tri par artiste.
/// C'est ici qu'arrive « Modifier » du guide de rangement, avec la règle mise en évidence.
struct ShelvingSettingsPage: View {
    @State private var shelfPreferences = ShelfPreferencesStore.shared
    @State private var tabCoordinator = TabNavigationCoordinator.shared
    @State private var isShelfRuleHighlighted = false

    var body: some View {
        SettingsSubPage(title: "Rangement") {
            Section {
                Picker(selection: $shelfPreferences.sortStrategy) {
                    ForEach(ShelfSortStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "books.vertical.fill", backgroundColor: .indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Règle de rangement dans le meuble")
                                .foregroundStyle(.primary)
                            Text(shelfPreferences.sortStrategy.title)
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.spinlogPink)
                // Fond de ligne par défaut, teinté le temps de la mise en évidence, comme les badges
                // actifs de l'app.
                .listRowBackground(
                    ZStack {
                        Color(uiColor: .secondarySystemGroupedBackground)
                        Color.spinlogPinkBadge
                            .opacity(isShelfRuleHighlighted ? 1 : 0)
                    }
                )

                Toggle(isOn: $shelfPreferences.restrictToSameFolder) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "square.stack.3d.up.fill", backgroundColor: .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Limiter au dossier Discogs")
                                .foregroundStyle(.primary)
                            Text("Le guide de rangement ne compare qu'au dossier du disque, plutôt qu'à toute la collection")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .tint(Color.spinlogPink)
            } header: {
                SectionEyebrow(title: "Rangement", icon: "books.vertical.fill")
            } footer: {
                Text("Règles de tri appliquées à ton meuble physique et à ta collection.")
            }
        }
        // `initial: true` : à la toute première visite, la demande de mise en évidence a été émise
        // avant que cette page n'existe (le changement du déclencheur passerait inaperçu) ; elle est
        // donc aussi lue à l'apparition. Seul point d'entrée : « Modifier » du guide de rangement.
        .onChange(of: tabCoordinator.scrollToOrganizationSectionTrigger, initial: true) { _, _ in
            guard tabCoordinator.consumePendingOrganizationScroll() else { return }
            Task { @MainActor in
                // Laisse finir la fermeture de la feuille du guide et le changement d'onglet.
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.settingsRowHighlight) { isShelfRuleHighlighted = true }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.settingsRowHighlight) { isShelfRuleHighlighted = false }
            }
        }
    }
}
