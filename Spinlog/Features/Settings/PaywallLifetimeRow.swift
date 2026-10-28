import SwiftUI

/// Lien secondaire du paywall, sous les abonnements : l'achat unique « Premium pour toujours ».
/// `SubscriptionStoreView` ne présente que des abonnements, d'où ce lien à part, volontairement
/// discret pour ne pas faire concurrence à l'annuel (et son essai). Le prix vient de StoreKit
/// (`Product.displayPrice`), jamais écrit en dur. Aucun texte d'essai : l'achat à vie n'en a pas.
struct PaywallLifetimeRow: View {
    let displayPrice: String
    let isPurchasing: Bool
    let onPurchase: () -> Void

    var body: some View {
        Button(action: onPurchase) {
            VStack(spacing: 2) {
                if isPurchasing {
                    ProgressView()
                } else {
                    Text("Ou achat unique à \(displayPrice)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.goldText)
                }
                Text("Premium pour toujours")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
        .accessibilityIdentifier("paywall.lifetime")
    }
}

#Preview {
    VStack(spacing: 12) {
        PaywallLifetimeRow(displayPrice: "39,99 €", isPurchasing: false) {}
        PaywallLifetimeRow(displayPrice: "39,99 €", isPurchasing: true) {}
    }
    .padding(22)
    .background(Color.appBackground)
}
