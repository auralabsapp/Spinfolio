import SwiftUI

/// Cartes liées à l'exemplaire possédé (notes, dossiers, journal d'écoute, note personnelle)
/// de la fiche release — extrait de ReleaseDetailSections.swift (1464 lignes à l'origine) pour
/// isoler cette responsabilité.
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

                        Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
            Button(action: {
                // Sans ce garde-fou, retaper sur une écoute déjà en cours incrémentait le
                // compteur à chaque appui au lieu de ne rien faire.
                guard !isPlayingThisRelease else { return }
                onLogListening()
            }) {
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
            // Repli d'iOS 26 (pas de `swipeActionsContainer`, voir `SwipeActionsContainerCompat`),
            // et raccourci par appui long sur iOS 27.
            .contextMenu {
                Button {
                    onOpenNotes()
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                Button {
                    onShelfPlacement()
                } label: {
                    Label("Où ranger cet exemplaire", systemImage: "books.vertical.fill")
                }
                Button(role: .destructive) {
                    onRequestDelete()
                } label: {
                    Label("Supprimer", systemImage: "trash.fill")
                }
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
                // Micro-bordure pour l'épaisseur carton, comme les pochettes de la Collection et
                // de la Wantlist.
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                // Ombre de contact (très proche) puis ombre d'ambiance flottante (large et
                // douce), même recette que les autres pochettes de l'app.
                .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(totalCount > 1 ? "Exemplaire \(index + 1)" : "Note, tags et infos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("• \(folderName)")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    let filledNotes = item.notes.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    if !filledNotes.isEmpty {
                        Text("\(filledNotes.count) infos perso")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    if let date = item.dateAddedDate {
                        Text(date.formatted(Date.FormatStyle(date: .numeric, time: .omitted)))
                            .font(.footnote)
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
                                .font(.footnote.weight(.medium))
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
                            .font(.inlineIcon)
                        Text("Prix d'achat")
                    }
                    .font(.footnote.weight(.medium))
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
                        .font(.inlineIcon)
                    Text("? € (+ ?%)")
                }
                .font(.footnote.weight(.semibold))
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
                        .font(.inlineIcon)
                    Text("\(isPositive ? "+" : "")\(gain.formatted(.currency(code: marketCurrency).precision(.fractionLength(0))))")
                }
                .font(.footnote.weight(.medium))
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
