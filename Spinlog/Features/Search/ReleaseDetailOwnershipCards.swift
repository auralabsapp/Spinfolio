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
    @State private var marketEstimate: MarketEstimate?
    /// Cote convertie dans la devise d'affichage, pour la ligne « Cote actuelle » du compte gratuit.
    @State private var marketEstimateInDisplayCurrency: Double?

    private var isAlwaysAsk: Bool {
        guard let username = DiscogsAuthManager.shared.username else { return false }
        return CollectionPreferencesStore.isAlwaysAsk(for: username)
    }

    /// Champ prix d'achat configuré, pour tous les comptes : la saisie est libre (c'est un champ
    /// personnalisé Discogs), seul le calcul de la plus-value est Premium.
    private var purchasePriceFieldId: Int? {
        guard let username = DiscogsAuthManager.shared.username else { return nil }
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

    /// Dossiers où ranger un exemplaire : « All » est une vue agrégée de Discogs, pas un dossier.
    private var effectiveFolders: [CollectionFolder] {
        let targetFolders = actions.folders.filter { $0.id != DiscogsConstants.allFolderId }
        if !targetFolders.isEmpty {
            return targetFolders
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
                // La cote seule est gratuite ; sa comparaison au prix d'achat (pastille de
                // plus-value) reste réservée au Premium.
                if let marketEstimate, let marketEstimateInDisplayCurrency {
                    MarketEstimateRow(
                        price: marketEstimateInDisplayCurrency,
                        currency: defaultCurrency,
                        staleSince: marketEstimate.staleSince
                    )
                    .appleMusicGroupedCard()
                }
                PremiumLockedCard(
                    icon: "arrow.left.arrow.right",
                    title: "Plus-value de l'exemplaire",
                    message: "Passe premium pour calculer la plus-value de cet album à partir de ton prix d'achat."
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
                Text("Supprimer cet exemplaire (dossier « \(actions.folderName(for: item.folderId)) ») de ta collection Discogs ?")
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
        .task(id: "\(releaseId)_\(declaredCondition ?? "")_\(defaultCurrency)") {
            let estimate = await actions.refreshMarketEstimateIfNeeded(releaseId: releaseId, condition: declaredCondition)
            guard !Task.isCancelled else { return }
            marketEstimate = estimate
            if let estimate {
                let converted = await CurrencyConversionService.shared.convert(estimate.price, from: estimate.currency, to: defaultCurrency)
                guard !Task.isCancelled else { return }
                marketEstimateInDisplayCurrency = converted
            } else {
                marketEstimateInDisplayCurrency = nil
            }
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
        // Style relatif de `formatted` plutôt qu'un formatter créé à chaque rendu (§3).
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
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
                    .foregroundStyle(isPlayingThisRelease ? Color.onAccent : Color.spinlogPink)
                    // Le disque tourne à 33 tours/min tant que l'écoute dure (comme dans la feuille
                    // d'écoute) ; seule l'icône tourne, pas son fond.
                    .continuousRotation(isActive: isPlayingThisRelease)
                    .frame(width: 40, height: 40)
                    .expandedHitArea(visibleSide: 40)
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
                    .expandedHitArea(visibleSide: 40)
                    .background(isPlayingThisRelease ? Color(uiColor: .tertiarySystemFill) : Color(uiColor: .quaternarySystemFill).opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isPlayingThisRelease)
            .accessibilityLabel("Arrêter l'écoute en cours")

            Spacer(minLength: 8)

            // À droite : la pastille « Écoute en cours » (point qui pulse) pendant une écoute, et
            // toujours le compteur, qui s'incrémente en direct au démarrage d'une écoute. La date de
            // dernière écoute n'a de sens que hors écoute.
            VStack(alignment: .trailing, spacing: 4) {
                if isPlayingThisRelease {
                    HStack(spacing: 6) {
                        ListeningPulseDot()
                        Text("Écoute en cours")
                            .font(.caption.bold())
                            .foregroundStyle(Color.spinlogPink)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.spinlogPink.opacity(0.12), in: Capsule())
                    .motionTransition(.opacity.combined(with: .scale))
                }

                if playCount > 0 {
                    Text("Écouté \(playCount) fois")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        // Le chiffre défile quand le compteur augmente (voir `.animation` plus bas).
                        .contentTransition(.numericText(value: Double(playCount)))

                    if !isPlayingThisRelease, let relativeText = relativeLastListeningText {
                        Text("Dernière écoute : \(relativeText)")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                            .lineLimit(1)
                    }
                } else if !isPlayingThisRelease {
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
        }
        .padding(14)
        .appleMusicGroupedCard()
        // Halo qui respire derrière la carte pendant l'écoute.
        .background {
            if isPlayingThisRelease {
                // Halo plus léger que celui du guide de rangement : derrière une carte de texte, un halo
                // trop soutenu assombrit le fond et fait perdre du contraste aux libellés.
                BreathingGlow(blurRadius: 18, minOpacity: 0.06, maxOpacity: 0.17)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPlayingThisRelease)
        .animation(.snappy, value: playCount)
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
                // Espacement porté par chaque étoile (2 + 2 pt) plutôt que par la pile : les zones
                // de toucher se touchent, sans trou entre deux étoiles. Elles sont aussi étendues à
                // 44 pt de haut sans changer la mise en page (rembourrage annulé juste après).
                HStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { value in
                        Image(systemName: value <= rating ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(value <= rating ? Color.ratingStar : Color.secondary.opacity(0.3))
                            .padding(.horizontal, 2)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .padding(.vertical, -10)
                            .onTapGesture {
                                onSetRating(rating == value ? 0 : value)
                            }
                    }
                }
                .padding(.horizontal, -2)
                // Un seul élément réglable pour VoiceOver (balayer vers le haut ou le bas) plutôt
                // que cinq boutons à parcourir sans valeur d'ensemble.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Ma note")
                .accessibilityValue(rating == 0 ? Text("Aucune note") : Text("\(rating) étoiles"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment where rating < 5: onSetRating(rating + 1)
                    case .decrement where rating > 0: onSetRating(rating - 1)
                    default: break
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
