import SwiftUI

/// Pastille de prix de la feuille « Alerte de prix » (raccourci en pourcentage ou cote par état) :
/// touche pour appliquer ce montant comme seuil. Rebond à l'appui (voir `PriceChipButtonStyle`).
struct PriceChip: View {
    let title: String
    let price: Double
    let currency: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                Text(price.formatted(.currency(code: currency)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.onAccent : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isSelected ? Color.spinlogPink : Color.spinlogPink.opacity(0.1))
            )
            .overlay(Capsule().strokeBorder(Color.spinlogPink.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(PriceChipButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Réduit la pastille sous le doigt puis la relâche avec un petit rebond. Avec « Réduire les
/// animations », aucun changement d'échelle.
struct PriceChipButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
