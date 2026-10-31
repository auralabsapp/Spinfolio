import SwiftUI

/// Feuille « Prix et état » d'un exemplaire : prix d'achat (montant + devise) et état du disque,
/// les deux informations nécessaires au suivi de la plus-value. Enregistrés dans l'app
/// (`CopyDetailsStore`), puis envoyés à Discogs seulement si un champ y est associé dans Réglages.
/// Seuls les champs modifiés sont écrits.
struct PriceAndConditionSheet: View {
    let item: CollectionItem
    let actions: ReleaseActions

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var currency: String
    @State private var condition: RecordGrade?
    @State private var isSaving = false

    /// Valeurs d'origine, pour n'écrire que ce qui change.
    private let initialPrice: (amount: Double, currency: String)?
    private let initialCondition: RecordGrade?

    init(item: CollectionItem, actions: ReleaseActions) {
        self.item = item
        self.actions = actions

        let username = DiscogsAuthManager.shared.username ?? ""
        let defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)
        let details = CopyDetailsStore.shared.details(for: item.instanceId)
        initialPrice = details?.purchasePrice
        initialCondition = details?.mediaCondition
        _amountText = State(initialValue: initialPrice.map { PurchasePriceParser.editableAmountString($0.amount) } ?? "")
        _currency = State(initialValue: initialPrice?.currency ?? defaultCurrency)
        _condition = State(initialValue: initialCondition)
    }

    /// Prix saisi, lisible et différent de l'actuel.
    private var priceChange: (amount: Double, currency: String)? {
        guard let parsed = BatchCompletion.parsedPrice(amountText: amountText, currency: currency),
              parsed.amount != initialPrice?.amount || parsed.currency != initialPrice?.currency else { return nil }
        return parsed
    }

    /// État choisi et différent de l'actuel (un état remis à « — » n'est pas effacé sur Discogs).
    private var conditionChange: RecordGrade? {
        guard let condition, condition != initialCondition else { return nil }
        return condition
    }

    private var hasChanges: Bool { priceChange != nil || conditionChange != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PriceAndConditionFields(amountText: $amountText, currency: $currency, condition: $condition)

                    Text("Le prix d'achat et l'état du disque servent à calculer la plus-value de cet exemplaire.")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Prix et état")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("OK") {
                            save()
                        }
                        .accessibilityLabel("Enregistrer le prix et l'état")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.spinlogPink)
                        .disabled(!hasChanges)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let username = DiscogsAuthManager.shared.username else { return }
        isSaving = true
        let price = priceChange
        let grade = conditionChange
        let target = item
        Task {
            let result = await BatchCompletion.save(price: price, condition: grade, on: target, username: username)
            if result == .refused {
                actions.message = String(localized: "Impossible d'enregistrer ces informations sur Discogs.")
            }
            isSaving = false
            dismiss()
        }
    }
}
