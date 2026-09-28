import SwiftUI

/// Feuille d'édition du prix d'achat d'un exemplaire : montant (clavier décimal) + devise.
/// Écrit la valeur canonique `"<montant> <devise>"` attendue par Discogs dans le champ
/// personnalisé configuré dans les réglages (`CollectionPreferencesStore.purchasePriceFieldId`).
struct PurchasePriceEditSheet: View {
    let instanceId: Int
    let actions: ReleaseActions

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var currency: String
    @State private var isSaving = false

    init(instanceId: Int, currentValue: String, actions: ReleaseActions) {
        self.instanceId = instanceId
        self.actions = actions

        let username = DiscogsAuthManager.shared.username ?? ""
        let defaultCurrency = CollectionPreferencesStore.defaultCurrency(for: username)
        if let parsed = PurchasePriceParser.parse(currentValue, defaultCurrency: defaultCurrency) {
            _amountText = State(initialValue: String(format: "%.2f", parsed.amount))
            _currency = State(initialValue: parsed.currency)
        } else {
            _amountText = State(initialValue: "")
            _currency = State(initialValue: defaultCurrency)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(title: "Prix d'achat", icon: "eurosign.circle.fill")

                    HStack(spacing: 12) {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title3.weight(.semibold))

                        Spacer()

                        Picker("Devise", selection: $currency) {
                            ForEach(PurchasePriceParser.supportedCurrencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.spinlogPink)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .appleMusicGroupedCard()
                }
                .padding()
            }
            .navigationTitle("Prix d'achat")
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
                        Button("Enregistrer") {
                            save()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.spinlogPink)
                        .disabled(parsedAmount == nil)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        isSaving = true
        let canonical = PurchasePriceParser.canonicalString(amount: amount, currency: currency)
        Task {
            await actions.updatePurchasePrice(canonical, for: instanceId)
            isSaving = false
            dismiss()
        }
    }
}
