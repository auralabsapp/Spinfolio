import SwiftUI

/// Saisie du prix d'achat (montant + devise) et de l'état du disque d'un exemplaire : les deux
/// informations dont le suivi de la plus-value a besoin (prix payé, cote par état). Partagée par
/// `PriceAndConditionSheet` (fiche d'un album) et `BatchCompletionSheet` (après un ajout).
struct PriceAndConditionFields: View {
    @Binding var amountText: String
    @Binding var currency: String
    @Binding var condition: RecordGrade?
    /// Donne le focus au montant au premier affichage puis à chaque changement de cette valeur
    /// (album suivant dans la saisie par lot).
    var focusTrigger = 0

    @FocusState private var isPriceFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            priceCard
            conditionCard
        }
        .onAppear { isPriceFocused = true }
        .onChange(of: focusTrigger) { isPriceFocused = true }
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
                CurrencyPicker(currency: $currency)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .appleMusicGroupedCard()
        }
    }

    private var conditionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "État du disque", icon: "sparkles")
            RecordGradeRow(grade: $condition)
                .padding(.horizontal, 14)
                .appleMusicGroupedCard()
        }
    }
}

/// Menu de choix de la devise d'un prix d'achat.
struct CurrencyPicker: View {
    @Binding var currency: String

    var body: some View {
        Picker("Devise", selection: $currency) {
            ForEach(PurchasePriceParser.supportedCurrencies, id: \.self) { code in
                Text(code).tag(code)
            }
        }
        .pickerStyle(.menu)
        .tint(Color.spinlogPink)
    }
}

/// Ligne « État du disque » : titre à gauche, état choisi à droite (ou « — »). Un simple bouton, de
/// hauteur fixée ici (`minHeight`), qui ouvre la liste des 8 grades de Discogs dans une feuille
/// d'actions : sa mise en page est celle de la ligne du prix, sans dépendre de la taille de menus
/// système. Les menus de sélection essayés avant (`Picker`, `Menu`) laissaient la ligne vide, plus
/// basse que sa voisine ou décalée après défilement.
struct RecordGradeRow: View {
    @Binding var grade: RecordGrade?
    var minHeight: CGFloat = 44

    @State private var isChoosing = false

    var body: some View {
        Button {
            isChoosing = true
        } label: {
            HStack(spacing: 8) {
                Text("État du disque")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let grade {
                    Text(verbatim: grade.discogsLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.spinlogPink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("État du disque")
        .accessibilityValue(grade?.discogsLabel ?? "—")
        .confirmationDialog("État du disque", isPresented: $isChoosing, titleVisibility: .visible) {
            // Libellés Discogs tels quels (non traduits).
            ForEach(RecordGrade.allCases) { option in
                Button(option.discogsLabel) { grade = option }
            }
            if grade != nil {
                Button("Retirer l'état", role: .destructive) { grade = nil }
            }
            Button("Annuler", role: .cancel) {}
        }
    }
}
