import SwiftUI

struct SwipeableInstanceRow: View {
    let item: CollectionItem
    let index: Int
    let totalCount: Int
    let folderName: String
    let coverURL: String?
    let purchasePriceFieldId: Int?
    let isPremium: Bool
    let defaultCurrency: String
    let marketEstimate: MarketEstimate?
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
                            .background(Color.spinlogPink.opacity(0.10), in: Capsule())
                            .foregroundStyle(Color.spinlogPink)
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
    /// La saisie est ouverte à tous ; sans Premium, la pastille garde son aspect mais masque le
    /// montant (le calcul de la plus-value est la fonction Premium).
    @ViewBuilder
    private var purchasePriceBadge: some View {
        if let fieldId = purchasePriceFieldId {
            let rawValue = item.value(forFieldId: fieldId)
            if let parsed = PurchasePriceParser.parse(rawValue, defaultCurrency: defaultCurrency), !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !isPremium {
                    maskedGainBadge
                } else if let marketEstimate {
                    InstanceGainBadge(
                        purchaseAmount: parsed.amount,
                        purchaseCurrency: parsed.currency,
                        marketPrice: marketEstimate.price,
                        marketCurrency: marketEstimate.currency
                    )
                    // Cote de plus de 6 h servie hors ligne : sa date, pour ne pas la faire passer
                    // pour une cote à jour (CGU Discogs).
                    if let staleSince = marketEstimate.staleSince {
                        Text("Cote du \(staleSince.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                            .lineLimit(1)
                    }
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
        }
    }

    /// Même pastille que pour un compte Premium (`InstanceGainBadge` : montant seul, sans
    /// pourcentage), montant masqué ; le toucher ouvre l'offre Premium.
    private var maskedGainBadge: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingPremiumSheet = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.right")
                    .font(.inlineIcon)
                Text(verbatim: "+" + Self.maskedAmount(currency: defaultCurrency))
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gainPositive.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.gainPositive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Plus-value masquée"))
        .accessibilityHint(Text("Réservée au Premium. Touche deux fois pour découvrir l'offre."))
    }

    /// Montant masqué au format de la devise (« ? € » en français, « €? » en anglais) : même mise
    /// en forme que le montant réel, chiffres remplacés par un point d'interrogation.
    nonisolated static func maskedAmount(currency: String) -> String {
        0.formatted(.currency(code: currency).precision(.fractionLength(0))).replacingOccurrences(of: "0", with: "?")
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
