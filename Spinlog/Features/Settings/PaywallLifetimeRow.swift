import SwiftUI

/// Ligne secondaire du paywall, sous les abonnements : l'achat unique « Premium pour toujours ».
/// `SubscriptionStoreView` ne présente que des abonnements, d'où cette ligne à part ; le prix vient
/// de StoreKit (`Product.displayPrice`), jamais écrit en dur. Aucun texte d'essai : l'achat à vie
/// n'en a pas.
struct PaywallLifetimeRow: View {
    let displayPrice: String
    let isPurchasing: Bool
    let onPurchase: () -> Void

    var body: some View {
        Button(action: onPurchase) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Achat unique")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Premium pour toujours")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }

                Spacer(minLength: 8)

                if isPurchasing {
                    ProgressView()
                } else {
                    Text(displayPrice)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.goldText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .appleMusicGroupedCard()
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
