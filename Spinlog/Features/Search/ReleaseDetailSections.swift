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

    private var isAlwaysAsk: Bool {
        guard let username = authManager.username else { return false }
        return CollectionPreferencesStore.isAlwaysAsk(for: username)
    }

    private var effectiveFolders: [CollectionFolder] {
        if !actions.folders.isEmpty {
            return actions.folders
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
                        .shadow(color: Color.buttonPinkBottom.opacity(0.22), radius: 4, y: 1.5)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                }
            }
        )
        .contentShape(Capsule())
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
                    if actions.folders.count > 1 {
                        ForEach(actions.folders) { folder in
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
                                .shadow(color: Color.buttonPinkBottom.opacity(0.22), radius: 4, y: 1.5)
                        } else {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        }
                    }
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .animation(.easeInOut(duration: 0.15), value: actions.isInCollection)
        .animation(.easeInOut(duration: 0.15), value: actions.isInWantlist)
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
        .alert("Discogs", isPresented: Binding(
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
    let lowestPrice: Double?
    let action: () -> Void

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

                    if let lowestPrice {
                        Text("\(numForSale) exemplaires en vente dès \(lowestPrice.formatted(.currency(code: "USD")))")
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

                Divider()
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

            Divider()
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

/// Carte "Mon exemplaire" / "Mes exemplaires" :
/// Gère la possession de multiples exemplaires (notes, dossiers, suppression unitaire, ajout de copie supplémentaire)
/// et les tags personnels de la release.
struct MyItemCard: View {
    let instances: [CollectionItem]
    let releaseId: Int
    let release: Release?
    let actions: ReleaseActions
    let onOpenNotes: (CollectionItem) -> Void
    let onShelfPlacement: (CollectionItem) -> Void

    @State private var itemPendingDeletion: CollectionItem? = nil
    @State private var priceEditTarget: CollectionItem?
    @State private var marketEstimate: (price: Double, currency: String)?

    private var isAlwaysAsk: Bool {
        guard let username = DiscogsAuthManager.shared.username else { return false }
        return CollectionPreferencesStore.isAlwaysAsk(for: username)
    }

    private var purchasePriceFieldId: Int? {
        guard PremiumStore.shared.isPremium, let username = DiscogsAuthManager.shared.username else { return nil }
        return CollectionPreferencesStore.purchasePriceFieldId(for: username)
    }

    private var defaultCurrency: String {
        guard let username = DiscogsAuthManager.shared.username else { return "EUR" }
        return CollectionPreferencesStore.defaultCurrency(for: username)
    }

    /// Utilise le champ "état du disque" choisi dans les réglages (auto-détecté ou sélectionné
    /// manuellement) pour affiner l'estimation de cote (sinon `refreshMarketEstimateIfNeeded`
    /// retombe sur une moyenne). Si aucun champ n'est configuré, retombe sur une détection par
    /// mots-clés à la volée. Discogs fournit par défaut deux champs "état" distincts — Media
    /// Condition (le disque) et Sleeve Condition (la pochette) — on exclut donc explicitement
    /// toute mention de pochette/sleeve pour ne jamais confondre les deux.
    private var declaredCondition: String? {
        guard let firstInstance = instances.first else { return nil }

        if let username = DiscogsAuthManager.shared.username,
           let configuredFieldId = CollectionPreferencesStore.mediaConditionFieldId(for: username) {
            let value = firstInstance.value(forFieldId: configuredFieldId)
            return value.isEmpty ? nil : value
        }

        guard let field = actions.collectionFields.first(where: { field in
            let normalized = field.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard !normalized.contains("sleeve"), !normalized.contains("pochette") else { return false }
            return normalized.contains("media condition") || normalized.contains("etat du media") || normalized.contains("etat du disque")
        }) else { return nil }
        let value = firstInstance.value(forFieldId: field.id)
        return value.isEmpty ? nil : value
    }

    private var effectiveFolders: [CollectionFolder] {
        if !actions.folders.isEmpty {
            return actions.folders
        }
        return [CollectionFolder(id: DiscogsConstants.uncategorizedFolderId, name: "Uncategorized", count: 0)]
    }

    private var addAnotherInstanceLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
            Text("Ajouter un autre exemplaire")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.appSecondaryText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: instances.count > 1 ? "Mes exemplaires (\(instances.count))" : "Mon exemplaire", icon: "opticaldisc.fill")

            VStack(spacing: 0) {
                if !instances.isEmpty {
                    ForEach(Array(instances.enumerated()), id: \.element.id) { index, item in
                        SwipeableInstanceRow(
                            item: item,
                            index: index,
                            totalCount: instances.count,
                            folderName: actions.folderName(for: item.folderId),
                            coverURL: item.basicInformation.thumb ?? item.basicInformation.coverImage ?? release?.images?.first?.uri,
                            purchasePriceFieldId: purchasePriceFieldId,
                            isPremium: PremiumStore.shared.isPremium,
                            defaultCurrency: defaultCurrency,
                            marketEstimate: marketEstimate,
                            onOpenNotes: { onOpenNotes(item) },
                            onRequestDelete: { itemPendingDeletion = item },
                            onEditPurchasePrice: { priceEditTarget = item },
                            onShelfPlacement: { onShelfPlacement(item) }
                        )

                        Divider().opacity(0.15).padding(.leading, 14)
                    }

                    // Bouton pour ajouter un exemplaire supplémentaire
                    if isAlwaysAsk {
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
                            addAnotherInstanceLabel
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
                            addAnotherInstanceLabel
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
                }
            }
            .appleMusicGroupedCard()

            if !PremiumStore.shared.isPremium {
                PremiumLockedCard(
                    icon: "arrow.left.arrow.right",
                    title: "Plus-value de l'exemplaire",
                    message: "Passe premium pour renseigner ton prix d'achat et suivre la plus-value de cet album."
                )
            }
        }
        .confirmationDialog(
            "Supprimer cet exemplaire ?",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { if !$0 { itemPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let item = itemPendingDeletion {
                    Task { await actions.removeInstance(item) }
                }
                itemPendingDeletion = nil
            }
            Button("Annuler", role: .cancel) {
                itemPendingDeletion = nil
            }
        } message: {
            if let item = itemPendingDeletion {
                Text("Retirer cet exemplaire (dossier « \(actions.folderName(for: item.folderId)) ») de ta collection Discogs ?")
            }
        }
        .sheet(item: $priceEditTarget) { item in
            PurchasePriceEditSheet(
                instanceId: item.instanceId,
                currentValue: purchasePriceFieldId.map { item.value(forFieldId: $0) } ?? "",
                actions: actions
            )
        }
        .task(id: "\(releaseId)_\(declaredCondition ?? "")_\(PremiumStore.shared.isPremium)") {
            guard PremiumStore.shared.isPremium else {
                marketEstimate = nil
                return
            }
            marketEstimate = await actions.refreshMarketEstimateIfNeeded(releaseId: releaseId, condition: declaredCondition)
        }
    }
}

// MARK: - Carte Journal d'Écoute (Listening Log)

struct ListeningLogCard: View {
    let releaseId: Int
    var onLogListening: () -> Void
    var onStopListening: (() -> Void)? = nil

    @State private var listeningStore = ListeningLogStore.shared
    private var activityManager = NowPlayingActivityManager.shared

    private var isPlayingThisRelease: Bool {
        activityManager.isPlaying(releaseId: releaseId)
    }

    private var playCount: Int {
        listeningStore.playCount(for: releaseId)
    }

    private var lastListeningDate: Date? {
        listeningStore.lastListeningDate(for: releaseId)
    }

    private var relativeLastListeningText: String? {
        guard let date = lastListeningDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        listeningControls
    }

    private var listeningControls: some View {
        HStack(spacing: 12) {
            Button(action: onLogListening) {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isPlayingThisRelease ? Color.white : Color.spinlogPink)
                    .frame(width: 40, height: 40)
                    .background(isPlayingThisRelease ? Color.spinlogPink : Color.spinlogPinkBadge, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("J'écoute ce disque sur la platine")

            // Bouton Stop (toujours visible, grisé et désactivé si aucune écoute)
            Button(action: {
                if isPlayingThisRelease {
                    onStopListening?()
                }
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isPlayingThisRelease ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 40, height: 40)
                    .background(isPlayingThisRelease ? Color(uiColor: .tertiarySystemFill) : Color(uiColor: .quaternarySystemFill).opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isPlayingThisRelease)
            .accessibilityLabel("Arrêter l'écoute en cours")

            Spacer(minLength: 8)

            // Si écoute en cours : pilule "Écoute en cours"
            // Sinon : nombre d'écoutes et date de dernière écoute sur 2 lignes
            if isPlayingThisRelease {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.spinlogPink)
                        .frame(width: 7, height: 7)
                    Text("Écoute en cours")
                        .font(.caption.bold())
                        .foregroundStyle(Color.spinlogPink)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.spinlogPink.opacity(0.12), in: Capsule())
                .transition(.opacity.combined(with: .scale))
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    if playCount > 0 {
                        Text("Écouté \(playCount) fois")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        if let relativeText = relativeLastListeningText {
                            Text("Dernière écoute : \(relativeText)")
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Jamais écouté")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.appSecondaryText)
                            .lineLimit(1)
                        Text("Touche le disque quand tu l'écoutes")
                            .font(.caption2)
                            .foregroundStyle(Color.appTertiaryText)
                            .lineLimit(1)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(14)
        .appleMusicGroupedCard()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPlayingThisRelease)
    }
}

/// Note personnelle de la release (étoiles) : Discogs partage cette valeur entre tous les
/// exemplaires possédés d'une même release (même si l'API l'expose via un chemin par instance),
/// elle est donc affichée et modifiable une seule fois ici plutôt que dupliquée par exemplaire.
struct ReleaseRatingCard: View {
    let rating: Int
    let isUpdating: Bool
    let onSetRating: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Ma note de la release", icon: "star.fill")

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { value in
                        Image(systemName: value <= rating ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(value <= rating ? Color.orange : Color.secondary.opacity(0.3))
                            .onTapGesture {
                                onSetRating(rating == value ? 0 : value)
                            }
                            .accessibilityLabel("\(value) étoiles")
                            .accessibilityAddTraits(.isButton)
                    }
                }

                Spacer()

                if isUpdating {
                    ProgressView()
                } else if rating > 0 {
                    Text("\(rating)/5")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .appleMusicGroupedCard()
        }
        .disabled(isUpdating)
    }
}

private struct SwipeableInstanceRow: View {
    let item: CollectionItem
    let index: Int
    let totalCount: Int
    let folderName: String
    let coverURL: String?
    let purchasePriceFieldId: Int?
    let isPremium: Bool
    let defaultCurrency: String
    let marketEstimate: (price: Double, currency: String)?
    let onOpenNotes: () -> Void
    let onRequestDelete: () -> Void
    let onEditPurchasePrice: () -> Void
    let onShelfPlacement: () -> Void

    @State private var showingPremiumSheet = false

    var body: some View {
        // `.swipeActions` + `.swipeActionsContainer()` (iOS 27) : mécanisme natif qui
        // coexiste correctement avec le scroll vertical du ScrollView parent, contrairement
        // à un geste de swipe fait main qui accapare systématiquement le toucher.
        rowContent
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenNotes()
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    onRequestDelete()
                } label: {
                    Label("Supprimer", systemImage: "trash.fill")
                }
                .tint(.red)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Supprimer cet exemplaire")

                Button {
                    onOpenNotes()
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                .tint(.orange)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Modifier cet exemplaire")

                Button {
                    onShelfPlacement()
                } label: {
                    Label("Ranger", systemImage: "books.vertical.fill")
                }
                .tint(.indigo)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Où ranger cet exemplaire")
            }
            .fullScreenCover(isPresented: $showingPremiumSheet) {
                SpinlogPaywallView()
            }
    }

    private var rowContent: some View {
        let itemTags = TagStore.shared.tags(for: item.instanceId, releaseId: item.releaseId)

        return HStack(spacing: 12) {
            AsyncCoverImage(url: coverURL, cornerRadius: 6)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(totalCount > 1 ? "Exemplaire \(index + 1)" : "Note, tags et infos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("• \(folderName)")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    let filledNotes = item.notes.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    if !filledNotes.isEmpty {
                        Text("\(filledNotes.count) infos perso")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    if let date = item.dateAddedDate {
                        Text(date.formatted(Date.FormatStyle(date: .numeric, time: .omitted)))
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                    }

                    purchasePriceBadge
                }

                // Affiche chaque tag individuellement (plutôt qu'un compteur "x tags") : la limite
                // de `TagConstants.maxTagsPerInstance` par exemplaire garantit que ça reste lisible,
                // avec repli sur une seconde ligne via `FlowLayout` si besoin.
                if !itemTags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(itemTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.tagBackground, in: Capsule())
                                .foregroundStyle(Color.tagForeground)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Color.appTertiaryText)
        }
    }

    /// Pastille de plus-value si un prix d'achat est renseigné et qu'une cote est connue, ou
    /// bouton discret pour en saisir un sinon. Bouton distinct du reste de la ligne (qui ouvre les
    /// notes) : `Button` conserve sa propre priorité de toucher au sein de son cadre.
    @ViewBuilder
    private var purchasePriceBadge: some View {
        if let fieldId = purchasePriceFieldId {
            let rawValue = item.value(forFieldId: fieldId)
            if let parsed = PurchasePriceParser.parse(rawValue, defaultCurrency: defaultCurrency), !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let marketEstimate {
                    InstanceGainBadge(
                        purchaseAmount: parsed.amount,
                        purchaseCurrency: parsed.currency,
                        marketPrice: marketEstimate.price,
                        marketCurrency: marketEstimate.currency
                    )
                }
            } else {
                Button(action: onEditPurchasePrice) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                        Text("Prix d'achat")
                    }
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(Color.appSecondaryText)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    )
                }
                .buttonStyle(.plain)
            }
        } else if !isPremium {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingPremiumSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                    Text("? € (+ ?%)")
                }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(Color(red: 0.88, green: 0.52, blue: 0.12))
                .background(Color(red: 0.95, green: 0.68, blue: 0.18).opacity(0.14), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color(red: 0.95, green: 0.68, blue: 0.18).opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Pastille affichant la plus-value latente d'un exemplaire (prix d'achat vs cote actuelle
/// estimée), après conversion du prix d'achat dans la devise de la cote pour rester comparable.
private struct InstanceGainBadge: View {
    let purchaseAmount: Double
    let purchaseCurrency: String
    let marketPrice: Double
    let marketCurrency: String

    @State private var convertedPurchase: Double?

    var body: some View {
        Group {
            if let convertedPurchase {
                let gain = marketPrice - convertedPurchase
                let isPositive = gain >= 0
                HStack(spacing: 3) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(isPositive ? "+" : "")\(gain.formatted(.currency(code: marketCurrency).precision(.fractionLength(0))))")
                }
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((isPositive ? Color.gainPositive : Color.gainNegative).opacity(0.14), in: Capsule())
                .foregroundStyle(isPositive ? Color.gainPositive : Color.gainNegative)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .task(id: "\(purchaseAmount)_\(purchaseCurrency)_\(marketCurrency)") {
            convertedPurchase = await CurrencyConversionService.shared.convert(purchaseAmount, from: purchaseCurrency, to: marketCurrency)
        }
    }
}

/// Carte d'infos techniques (format, pays, date de sortie, labels/référence catalogue, master).
/// Les lignes label/master sont navigables vers leurs fiches respectives.
struct ReleaseInfoCard: View {
    let release: Release
    @State private var masterYear: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ReleaseInfoRow(systemImage: row.icon, text: row.text, destination: row.destination)
                if index < rows.count - 1 {
                    Divider().opacity(0.15).padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: release.masterId) {
            await fetchMasterYearIfNeeded()
        }
    }

    private var masterLabelText: String {
        if let masterYear, masterYear > 0 {
            return String(localized: "Sortie originale en \(masterYear) – voir le master")
        }
        return String(localized: "Voir le master")
    }

    private func fetchMasterYearIfNeeded() async {
        guard let masterId = release.masterId, masterId > 0 else { return }

        // Vérifier dans le cache local SwiftData
        if LocalDataStore.shared.isMasterResolved(masterId) {
            masterYear = LocalDataStore.shared.getMasterYear(for: masterId)
            return
        }

        // Sinon charger via l'API Discogs
        do {
            let credentials = DiscogsAuthManager.shared.credentials
            let master = try await DiscogsAPIClient.shared.masterRelease(id: masterId, credentials: credentials)
            let year = max(master.year ?? 0, 0)
            if year > 0 {
                masterYear = year
            }
            // 0 si Discogs n'a pas d'année : évite de le redemander à chaque ouverture.
            LocalDataStore.shared.saveMasterYear(year, for: masterId)
        } catch {
            // Silencieux en cas d'erreur réseau
        }
    }

    private var rows: [(id: String, icon: String, text: String, destination: SearchDestination?)] {
        var result: [(id: String, icon: String, text: String, destination: SearchDestination?)] = []
        if let formatLine {
            result.append((id: "format", icon: "opticaldisc", text: formatLine, destination: nil))
        }
        if let country = release.country {
            result.append((id: "country", icon: "mappin.and.ellipse", text: country, destination: nil))
        }
        if let dateLine {
            result.append((id: "date", icon: "calendar", text: dateLine, destination: nil))
        }
        for label in release.labels ?? [] {
            let text = [label.name, label.catno].compactMap { $0 }.joined(separator: " – ")
            result.append((id: "label-\(label.id)", icon: "barcode", text: text, destination: .label(label.id)))
        }
        if let masterId = release.masterId {
            result.append((id: "master", icon: "square.stack.3d.up", text: masterLabelText, destination: .master(masterId)))
        }
        return result
    }

    private var formatLine: String? {
        guard let formats = release.formats, !formats.isEmpty else { return nil }
        return formats
            .map { format in
                ([format.name] + (format.descriptions ?? []) + [format.text].compactMap { $0 })
                    .joined(separator: ", ")
            }
            .joined(separator: " / ")
    }

    private var dateLine: String? {
        guard let formatted = release.formattedReleasedDate else { return nil }
        if let year = release.year, !formatted.contains(String(year)) {
            return "\(formatted) (original \(year))"
        }
        return formatted
    }
}

private struct ReleaseInfoRow: View {
    let systemImage: String
    let text: String
    var destination: SearchDestination?

    var body: some View {
        Group {
            if let destination {
                NavigationLink(value: destination) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.spinlogPink)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            if destination != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTertiaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Identifiants du pressage : codes-barres, numéros de matrice/runout, société de gestion
/// des droits, etc.
struct ReleaseIdentifiersSection: View {
    let identifiers: [ReleaseIdentifier]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Identifiants", icon: "number")
            VStack(spacing: 0) {
                ForEach(Array(identifiers.enumerated()), id: \.offset) { index, identifier in
                    HStack(spacing: 12) {
                        Image(systemName: "barcode")
                            .font(.subheadline)
                            .foregroundStyle(Color.spinlogPink)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            let title = [identifier.type, identifier.description]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            Text(title.isEmpty ? "Identifiant" : title)
                                .font(.subheadline)
                            Text(identifier.value)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    if index < identifiers.count - 1 {
                        Divider().opacity(0.15).padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
            .appleMusicGroupedCard()
        }
    }
}

/// Sociétés liées à la fabrication/diffusion (pressage, distribution, mastering...),
/// distinctes des labels musicaux déjà listés dans `ReleaseInfoCard`.
struct ReleaseCompaniesSection: View {
    let companies: [ReleaseCompany]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Fabrication", icon: "building.2.fill")
            VStack(spacing: 0) {
                ForEach(Array(companies.enumerated()), id: \.offset) { index, company in
                    HStack(spacing: 12) {
                        Image(systemName: "building.2")
                            .font(.subheadline)
                            .foregroundStyle(Color.spinlogPink)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(company.entityTypeName?.isEmpty == false ? company.entityTypeName! : String(localized: "Société"))
                                .font(.subheadline)
                            Text(company.name)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    if index < companies.count - 1 {
                        Divider().opacity(0.15).padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
            .appleMusicGroupedCard()
        }
    }
}

/// Vidéos associées à la release (généralement des extraits YouTube renseignés sur Discogs).
/// Lues directement dans l'app via `YouTubePlayerView` quand l'identifiant YouTube est
/// reconnaissable ; repli vers un lien externe sinon (format d'URL non supporté).
struct ReleaseVideosSection: View {
    let videos: [ReleaseVideo]

    @State private var videoPlayerRequest: VideoPlayerRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(title: "Vidéos", icon: "video.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(videos) { video in
                        if let videoID = video.youTubeVideoID {
                            Button {
                                videoPlayerRequest = VideoPlayerRequest(videoID: videoID, title: video.title)
                            } label: {
                                videoCard(video)
                            }
                            .buttonStyle(.plain)
                        } else if let url = URL(string: video.uri) {
                            Link(destination: url) {
                                videoCard(video)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .fullScreenCover(item: $videoPlayerRequest) { request in
            VideoPlayerSheet(request: request)
        }
    }

    private func videoCard(_ video: ReleaseVideo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                AsyncImage(url: video.thumbnailURL) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(16.0 / 9.0, contentMode: .fill)
                    } else {
                        Rectangle().fill(.fill.tertiary)
                    }
                }
                .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            Text(video.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
            if let duration = video.formattedDuration {
                Text(duration)
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }
            if let description = video.description, !description.isEmpty, description != video.title {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
            }
        }
    }
}

/// Galerie des photos de cette release (pochette, verso, label du disque...).
/// Chaque miniature ouvre le visualiseur plein écran à son index via `onSelect`.
struct ReleaseImagesGallery: View {
    let images: [DiscogsImage]
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(title: "Images", icon: "photo.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(images.indices, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            AsyncCoverImage(url: images[index].uri, cornerRadius: 10)
                                .frame(width: 140, height: 140)
                                .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(images[index].type == "primary" ? Text("Pochette de l'album") : Text("Photo \(index + 1) de la release"))
                        .accessibilityHint("Voir en plein écran")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }
}


// MARK: - Toast de notification d'écoute (Lecture démarrée / stoppée)

enum ListeningToastType: Equatable {
    case started
    case stopped
}

struct ListeningToastBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    let type: ListeningToastType
    var onCancel: (() -> Void)? = nil

    private var bannerBackground: Color {
        colorScheme == .dark
            ? Color(white: 0.23)
            : Color(uiColor: .systemBackground)
    }

    private var bannerBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.black.opacity(0.08)
    }

    var body: some View {
        HStack(spacing: 12) {
            switch type {
            case .started:
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.spinlogPink)

                Text("Écoute sur platine démarrée")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)

                Spacer()

                if let onCancel {
                    Button("Annuler") {
                        onCancel()
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.spinlogPink)
                }

            case .stopped:
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.75) : Color(uiColor: .systemGray))

                Text("Écoute arrêtée")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)

                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(
            Capsule()
                .fill(bannerBackground)
        )
        .overlay(
            Capsule()
                .stroke(bannerBorder, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.15), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
