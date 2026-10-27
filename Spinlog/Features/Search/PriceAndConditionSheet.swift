import SwiftUI

/// Feuille « Prix et état » d'un exemplaire : prix d'achat (montant + devise) et état du média,
/// les deux informations nécessaires au suivi de la plus-value. Écrit dans les champs personnalisés
/// configurés dans Réglages (`CollectionPreferencesStore`) : la valeur du prix est la forme
/// canonique `"<montant> <devise>"` attendue par Discogs. Seuls les champs modifiés sont envoyés.
struct PriceAndConditionSheet: View {
    let item: CollectionItem
    let actions: ReleaseActions

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var currency: String
    @State private var condition: String
    @State private var isSaving = false

    private let priceFieldId: Int?
    private let conditionFieldId: Int?
    /// Valeurs d'origine, pour n'envoyer que ce qui change.
    private let initialCanonicalPrice: String?
    private let initialCondition: String

    init(item: CollectionItem, actions: ReleaseActions) {
        self.item = item
        self.actions = actions

        let username = DiscogsAuthManager.shared.username ?? ""
        let priceFieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username)
        let conditionFieldId = CollectionPreferencesStore.mediaConditionFieldId(for: username)
        self.priceFieldId = priceFieldId
        self.conditionFieldId = conditionFieldId

        let defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)
        let rawPrice = priceFieldId.map { item.value(forFieldId: $0) } ?? ""
        let rawCondition = conditionFieldId.map { item.value(forFieldId: $0) } ?? ""
        initialCondition = rawCondition

        if let parsed = PurchasePriceParser.parse(rawPrice, defaultCurrency: defaultCurrency) {
            _amountText = State(initialValue: String(format: "%.2f", parsed.amount))
            _currency = State(initialValue: parsed.currency)
            initialCanonicalPrice = PurchasePriceParser.canonicalString(amount: parsed.amount, currency: parsed.currency)
        } else {
            _amountText = State(initialValue: "")
            _currency = State(initialValue: defaultCurrency)
            initialCanonicalPrice = nil
        }
        _condition = State(initialValue: rawCondition)
    }

    private var conditionField: CollectionField? {
        conditionFieldId.flatMap { id in actions.collectionFields.first { $0.id == id } }
    }

    /// Champs réellement modifiés : prix saisi, lisible et différent de l'actuel ; état choisi et
    /// différent de l'actuel (un état vidé n'est pas effacé sur Discogs).
    private var changes: [(fieldId: Int, value: String)] {
        var result: [(fieldId: Int, value: String)] = []
        if let priceFieldId,
           let canonical = BatchCompletion.canonicalPrice(amountText: amountText, currency: currency),
           canonical != initialCanonicalPrice {
            result.append((priceFieldId, canonical))
        }
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        if let conditionFieldId, !trimmed.isEmpty, trimmed != initialCondition {
            result.append((conditionFieldId, trimmed))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PriceAndConditionFields(
                        amountText: $amountText,
                        currency: $currency,
                        condition: $condition,
                        showsPrice: priceFieldId != nil,
                        showsCondition: conditionFieldId != nil,
                        conditionField: conditionField,
                        isLoadingConditionField: false
                    )

                    Text("Le prix d'achat et l'état du média servent à calculer la plus-value de cet exemplaire.")
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
                        .disabled(changes.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        isSaving = true
        let toWrite = changes
        let instanceId = item.instanceId
        Task {
            for change in toWrite {
                await actions.updateInstanceField(change.fieldId, value: change.value, for: instanceId)
            }
            isSaving = false
            dismiss()
        }
    }
}
