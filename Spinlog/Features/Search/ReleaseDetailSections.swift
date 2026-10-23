import SwiftUI

/// Titre de section ("eyebrow"), avec accent rose signature Spinlog et petites majuscules.
/// `.section` marque une section de premier niveau ; `.subsection` marque un sous-titre
/// imbriqué dans une section `.section` déjà affichée au-dessus (ex. "Titres" à l'intérieur
/// de "Infos Discogs sur la release"), avec un poids visuel plus discret pour ne pas être
/// confondu avec le titre de la section parente.
struct SectionEyebrow: View {
    enum Style {
        case section
        case subsection
    }

    let title: LocalizedStringKey
    var icon: String? = nil
    var style: Style = .section
    /// Section d'une fonction Premium : étiquette dorée pendant l'aperçu de la démo
    /// (`DemoPremiumBadge`), invisible sinon.
    var isPremiumFeature = false

    var body: some View {
        switch style {
        case .section:
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.spinlogPink)
                }

                Text(title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.spinlogPink)
                    .kerning(0.5)
                    .textCase(.uppercase)

                if isPremiumFeature {
                    DemoPremiumBadge()
                }
            }
        case .subsection:
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appSecondaryText)
                    .kerning(0.3)
                    .textCase(.uppercase)
            }
        }
    }
}

/// Barre d'actions rapides tactiles (Collection, Wantlist) style Apple Music
struct ReleaseQuickActionsBar: View {
    let releaseId: Int
    var release: Release? = nil
    var actions: ReleaseActions
    var onShowShelfPlacement: (() -> Void)? = nil

    @State private var authManager = DiscogsAuthManager.shared
    @State private var instancePendingDeletion: CollectionItem? = nil
    @State private var showDeleteAllConfirmation = false
    @State private var showSingleDeleteConfirmation = false
    @State private var showWantlistDeleteConfirmation = false
    /// Compteurs qui déclenchent le « pop » des boutons après un ajout (voir `libraryPop`).
    @State private var collectionPop = 0
    @State private var wantlistPop = 0

    private var isAlwaysAsk: Bool {
        guard let username = authManager.username else { return false }
        return CollectionPreferencesStore.isAlwaysAsk(for: username)
    }

    /// Dossiers où ranger un exemplaire : « All » est une vue agrégée de Discogs, pas un dossier.
    private var effectiveFolders: [CollectionFolder] {
        let targetFolders = actions.folders.filter { $0.id != DiscogsConstants.allFolderId }
        if !targetFolders.isEmpty {
            return targetFolders
        }
        return [CollectionFolder(id: DiscogsConstants.uncategorizedFolderId, name: "Uncategorized", count: 0)]
    }

    private var collectionButtonTitle: String {
        if actions.isInCollection {
            if actions.instancesCount > 1 {
                return String(localized: "En collection (\(actions.instancesCount))")
            }
            return String(localized: "En collection")
        }
        return String(localized: "Collection")
    }

    private var collectionButtonLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: actions.isInCollection ? "checkmark" : "plus")
                .font(.subheadline.bold())
                .contentTransition(.symbolEffect(.replace))
            Text(collectionButtonTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(actions.isInCollection ? Color.white : Color.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(
            Group {
                if actions.isInCollection {
                    Capsule()
                        .fill(Color.spinlogPinkButtonGradient)
                        .shadow(color: Color.buttonPinkShadow, radius: 4, y: 1.5)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                }
            }
        )
        .contentShape(Capsule())
        .libraryPop(trigger: collectionPop)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Bouton Collection (bascule ajout/retrait instantanée ou menu selon réglages/exemplaires)
            if actions.isInCollection && actions.instancesCount > 1 {
                // Plusieurs exemplaires : menu au tap direct pour ajouter une copie ou retirer
                Menu {
                    Section {
                        if isAlwaysAsk {
                            Menu("Ajouter un autre exemplaire") {
                                ForEach(effectiveFolders) { folder in
                                    Button(folder.name) {
                                        Task {
                                            await actions.addToCollection(
                                                releaseId: releaseId,
                                                release: release,
                                                targetFolderId: folder.id
                                            )
                                        }
                                    }
                                }
                            }
                        } else {
                            Button("Ajouter un autre exemplaire") {
                                Task {
                                    await actions.addToCollection(
                                        releaseId: releaseId,
                                        release: release
                                    )
                                }
                            }
                        }
                    }

                    Section("Gérer les exemplaires") {
                        ForEach(Array(actions.collectionInstances.enumerated()), id: \.element.id) { index, inst in
                            Button(role: .destructive) {
                                instancePendingDeletion = inst
                            } label: {
                                Label("Supprimer exemplaire \(index + 1) (\(actions.folderName(for: inst.folderId)))", systemImage: "trash")
                            }
                        }

                        Button("Supprimer tous les exemplaires", role: .destructive) {
                            showDeleteAllConfirmation = true
                        }
                    }

                    Section {
                        Button {
                            onShowShelfPlacement?()
                        } label: {
                            Label("Emplacement dans mon meuble", systemImage: "books.vertical.fill")
                        }
                    }
                } label: {
                    collectionButtonLabel
                }
                .buttonStyle(.plain)
            } else if actions.isInCollection {
                Button {
                    showSingleDeleteConfirmation = true
                } label: {
                    collectionButtonLabel
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if isAlwaysAsk {
                        Menu("Ajouter un autre exemplaire") {
                            ForEach(effectiveFolders) { folder in
                                Button(folder.name) {
                                    Task {
                                        await actions.addToCollection(
                                            releaseId: releaseId,
                                            release: release,
                                            targetFolderId: folder.id
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        Button("Ajouter un autre exemplaire") {
                            Task {
                                await actions.addToCollection(
                                    releaseId: releaseId,
                                    release: release
                                )
                            }
                        }
                    }

                    Button(role: .destructive) {
                        showSingleDeleteConfirmation = true
                    } label: {
                        Label("Supprimer de la collection", systemImage: "trash")
                    }

                    Section {
                        Button {
                            onShowShelfPlacement?()
                        } label: {
                            Label("Emplacement dans mon meuble", systemImage: "books.vertical.fill")
                        }
                    }
                }
            } else if isAlwaysAsk {
                Menu {
                    ForEach(effectiveFolders) { folder in
                        Button(folder.name) {
                            Task {
                                await actions.addToCollection(
                                    releaseId: releaseId,
                                    release: release,
                                    targetFolderId: folder.id
                                )
                            }
                        }
                    }
                } label: {
                    collectionButtonLabel
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task {
                        await actions.addToCollection(
                            releaseId: releaseId,
                            release: release
                        )
                    }
                } label: {
                    collectionButtonLabel
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if effectiveFolders.count > 1 {
                        ForEach(effectiveFolders) { folder in
                            Button(folder.name) {
                                Task {
                                    await actions.addToCollection(
                                        releaseId: releaseId,
                                        release: release,
                                        targetFolderId: folder.id
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Bouton Wantlist (bascule ajout/retrait avec confirmation)
            Button {
                if actions.isInWantlist {
                    showWantlistDeleteConfirmation = true
                } else {
                    Task { await actions.toggleWantlist(releaseId: releaseId, release: release) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: actions.isInWantlist ? "checkmark" : "heart.fill")
                        .font(.subheadline.bold())
                        .contentTransition(.symbolEffect(.replace))
                    Text(actions.isInWantlist ? "En wantlist" : "Wantlist")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(actions.isInWantlist ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Group {
                        if actions.isInWantlist {
                            Capsule()
                                .fill(Color.spinlogPinkButtonGradient)
                                .shadow(color: Color.buttonPinkShadow, radius: 4, y: 1.5)
                        } else {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        }
                    }
                )
                .contentShape(Capsule())
                .libraryPop(trigger: wantlistPop)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("releaseWantlistButton")
        }
        .animation(.easeInOut(duration: 0.15), value: actions.isInCollection)
        .animation(.easeInOut(duration: 0.15), value: actions.isInWantlist)
        .onChange(of: actions.lastFeedbackEvent) { _, event in
            guard let event, event.kind.isAddition else { return }
            if event.kind == .addedToCollection {
                collectionPop += 1
            } else {
                wantlistPop += 1
            }
        }
        .task {
            await actions.loadFoldersIfNeeded()
        }
        .confirmationDialog(
            "Supprimer cet exemplaire ?",
            isPresented: Binding(
                get: { instancePendingDeletion != nil },
                set: { if !$0 { instancePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let inst = instancePendingDeletion {
                    Task { await actions.removeInstance(inst) }
                }
                instancePendingDeletion = nil
            }
            Button("Annuler", role: .cancel) {
                instancePendingDeletion = nil
            }
        } message: {
            if let inst = instancePendingDeletion {
                Text("Retirer cet exemplaire (dossier « \(actions.folderName(for: inst.folderId)) ») de ta collection Discogs ?")
            }
        }
        .confirmationDialog(
            "Supprimer tous les exemplaires ?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer tous les exemplaires", role: .destructive) {
                Task { await actions.removeFromCollection(releaseId: releaseId) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous tes exemplaires de cet album seront retirés de ta collection Discogs.")
        }
        .confirmationDialog(
            "Retirer de la collection ?",
            isPresented: $showSingleDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer de la collection", role: .destructive) {
                Task { await actions.removeFromCollection(releaseId: releaseId) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Veux-tu retirer cet album de ta collection Discogs ?")
        }
        .confirmationDialog(
            "Retirer de la wantlist ?",
            isPresented: $showWantlistDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Retirer de la wantlist", role: .destructive) {
                Task { await actions.toggleWantlist(releaseId: releaseId, release: release) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Veux-tu retirer cet album de ta wantlist Discogs ?")
        }
        .alert(DemoMode.isActive ? Text("Mode démo") : Text(verbatim: "Discogs"), isPresented: Binding(
            get: { actions.message != nil },
            set: { if !$0 { actions.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actions.message ?? "")
        }
    }
}

/// Bouton Marketplace élégant et discret placé sous la tracklist
struct MarketplaceButton: View {
    let numForSale: Int
    /// Prix le plus bas renvoyé par `/releases/{id}`, toujours en dollars.
    let lowestPrice: Double?
    let action: () -> Void

    /// Prix converti dans la devise choisie (Réglages → Suivi de cote) ; `nil` tant que la
    /// conversion n'est pas faite, le prix s'affiche alors en dollars comme avant.
    @State private var convertedPrice: (amount: Double, currency: String)?

    private var formattedLowestPrice: String? {
        if let convertedPrice {
            return convertedPrice.amount.formatted(.currency(code: convertedPrice.currency))
        }
        return lowestPrice?.formatted(.currency(code: "USD"))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.title3)
                    .foregroundStyle(Color.spinlogPink)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Marketplace Discogs")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let formattedLowestPrice {
                        Text("\(numForSale) exemplaires en vente dès \(formattedLowestPrice)")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                    } else {
                        Text("\(numForSale) exemplaires en vente")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .appleMusicGroupedCard()
        }
        .buttonStyle(.plain)
        .task(id: lowestPrice) {
            guard let lowestPrice, let username = DiscogsAuthManager.shared.username else { return }
            let currency = CollectionPreferencesStore.defaultCurrency(for: username)
            guard currency != "USD" else { return }
            let amount = await CurrencyConversionService.shared.convert(lowestPrice, from: "USD", to: currency)
            convertedPrice = (amount, currency)
        }
    }
}

/// Bandeau compact et moderne des statistiques communautaires (Note moyenne, Possesseurs, Souhaits)
struct CommunityStatsBar: View {
    let community: Community

    var body: some View {
        HStack(spacing: 0) {
            if let rating = community.rating, rating.count > 0 {
                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating.average))
                            .font(.subheadline.weight(.bold))
                    }
                    Text("\(rating.count) avis")
                        .font(.caption2)
                        .foregroundStyle(Color.appSecondaryText)
                }
                .frame(maxWidth: .infinity)

                Divider().overlay(Color.appSeparator)
                    .opacity(0.15)
                    .frame(height: 24)
            }

            VStack(spacing: 2) {
                Text(community.have.formatted())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.spinlogPink)
                Text("Possesseurs")
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(Color.appSeparator)
                .opacity(0.15)
                .frame(height: 24)

            VStack(spacing: 2) {
                Text(community.want.formatted())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.spinlogPink)
                Text("Souhaits")
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
    }
}

/// Ligne 3 : tags genres/styles ; défile horizontalement car cette liste dépasse souvent la
/// largeur de l'écran. `.scrollBounceBehavior(.basedOnSize)` désactive l'effet élastique quand
/// le contenu tient déjà à l'écran.
struct GenreTagsRow: View {
    /// Genres larges (ex. "Rock") : mis en évidence, affichés en premier.
    let genres: [String]
    /// Styles/sous-genres (ex. "Alternative Rock") : affichage plus discret.
    let styles: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.spinlogPink, in: Capsule())
                }
                ForEach(styles, id: \.self) { style in
                    Text(style)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
