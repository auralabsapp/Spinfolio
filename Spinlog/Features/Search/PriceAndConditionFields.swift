import SwiftUI

/// Saisie du prix d'achat (montant + devise) et de l'état du média d'un exemplaire : les deux
/// informations dont le suivi de la plus-value a besoin (prix payé, cote par état). Partagée par
/// `PriceAndConditionSheet` (fiche disque) et `BatchCompletionSheet` (après un scan par lot).
/// Chaque carte n'apparaît que si son champ est configuré dans Réglages > Prix d'achat et état.
struct PriceAndConditionFields: View {
    @Binding var amountText: String
    @Binding var currency: String
    @Binding var condition: String
    let showsPrice: Bool
    let showsCondition: Bool
    /// Champ « état du média » de Discogs : menu s'il est de type liste, texte libre sinon (ou tant
    /// que les champs du compte ne sont pas encore chargés).
    let conditionField: CollectionField?
    let isLoadingConditionField: Bool
    /// Donne le focus au montant au premier affichage puis à chaque changement de cette valeur
    /// (disque suivant dans la saisie par lot).
    var focusTrigger = 0

    @FocusState private var isPriceFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showsPrice { priceCard }
            if showsCondition { conditionCard }
        }
        .onAppear { if showsPrice { isPriceFocused = true } }
        .onChange(of: focusTrigger) { if showsPrice { isPriceFocused = true } }
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Prix d'achat", icon: "eurosign.circle.fill")
            HStack(spacing: 12) {
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold))
                    .focused($isPriceFocused)
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
    }

    private var conditionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "État du média", icon: "sparkles")
            Group {
                if isLoadingConditionField {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let conditionField, conditionField.isDropdown {
                    HStack {
                        Text(conditionField.name)
                            .font(.subheadline)
                        Spacer()
                        Picker(conditionField.name, selection: $condition) {
                            Text("—").tag("")
                            ForEach(conditionField.options ?? [], id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.spinlogPink)
                    }
                } else {
                    TextField(conditionField?.name ?? String(localized: "État du média"), text: $condition)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .appleMusicGroupedCard()
        }
    }
}
