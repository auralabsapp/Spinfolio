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
