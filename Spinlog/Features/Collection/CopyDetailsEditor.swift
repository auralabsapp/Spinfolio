import SwiftUI

/// Prix d'achat et état du disque d'un exemplaire, modifiables en place dans « Mon exemplaire »
/// (section « Plus-value de l'exemplaire »). Le prix s'enregistre en quittant le champ (ou avec
/// « OK » du clavier, ou en changeant de devise) ; l'état, dès qu'on le choisit. Tout reste dans
/// l'app (`CopyDetailsStore`) et part sur Discogs seulement si un champ y est associé (Réglages).
struct CopyDetailsEditor: View {
    let item: CollectionItem
    /// Message à afficher quand Discogs refuse l'envoi (la valeur reste enregistrée dans l'app).
    let onDiscogsRefusal: (String) -> Void

    @State private var store = CopyDetailsStore.shared
    @State private var amountText: String
    @State private var currency: String
    @FocusState private var isPriceFocused: Bool

    /// Hauteur commune des deux lignes (le menu de devise, plus haut qu'un simple texte, en dictait une).
    private static let rowHeight: CGFloat = 48

    init(item: CollectionItem, onDiscogsRefusal: @escaping (String) -> Void) {
        self.item = item
        self.onDiscogsRefusal = onDiscogsRefusal
        let username = DiscogsAuthManager.shared.username ?? ""
        let stored = CopyDetailsStore.shared.purchasePrice(for: item.instanceId)
        _amountText = State(initialValue: stored.map { PurchasePriceParser.editableAmountString($0.amount) } ?? "")
        _currency = State(initialValue: stored?.currency ?? CollectionPreferencesStore.defaultCurrency(for: username))
    }

    private var storedPrice: (amount: Double, currency: String)? {
        store.purchasePrice(for: item.instanceId)
    }

    private var conditionBinding: Binding<RecordGrade?> {
        Binding(
            get: { store.mediaCondition(for: item.instanceId) },
            set: { newValue in
                guard newValue != store.mediaCondition(for: item.instanceId) else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                write { username in
                    await CopyDetailsWriter.setMediaCondition(newValue, for: item, username: username)
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Prix d'achat")
                    .font(.subheadline)
                Spacer(minLength: 8)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .focused($isPriceFocused)
                    .onSubmit(commitPrice)
                    .accessibilityLabel("Prix d'achat")
                CurrencyPicker(currency: $currency)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: Self.rowHeight)

            Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)

            RecordGradeRow(grade: conditionBinding, minHeight: Self.rowHeight)
                .padding(.horizontal, 14)
        }
        .appleMusicGroupedCard()
        .onChange(of: isPriceFocused) { _, focused in
            if !focused { commitPrice() }
        }
        .onChange(of: currency) { commitPrice() }
        .onDisappear(perform: commitPrice)
    }

    /// Enregistre le prix saisi s'il est lisible et différent de l'actuel ; un champ vidé efface le
    /// prix ; une saisie illisible est remplacée par la valeur enregistrée.
    private func commitPrice() {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard storedPrice != nil else { return }
            write { username in await CopyDetailsWriter.setPurchasePrice(nil, for: item, username: username) }
            return
        }
        guard let parsed = BatchCompletion.parsedPrice(amountText: trimmed, currency: currency) else {
            amountText = storedPrice.map { PurchasePriceParser.editableAmountString($0.amount) } ?? ""
            return
        }
        guard parsed.amount != storedPrice?.amount || parsed.currency != storedPrice?.currency else { return }
        write { username in await CopyDetailsWriter.setPurchasePrice(parsed, for: item, username: username) }
    }

    private func write(_ operation: @escaping (String) async -> DiscogsWriteOutcome?) {
        guard let username = DiscogsAuthManager.shared.username else { return }
        Task {
            if await operation(username) == .refused {
                onDiscogsRefusal(String(localized: "Impossible d'enregistrer ces informations sur Discogs."))
            }
        }
    }
}
