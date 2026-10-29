import SwiftUI

/// Panneau d'achat épinglé en bas du paywall : forfaits, bouton d'abonnement, mentions de renouvellement,
/// achat à vie, restauration, code d'offre et liens légaux. Il ne reçoit que des données déjà prêtes
/// (voir `PaywallPlan`) et des actions : `SpinlogPaywallView` garde les achats, le panneau s'aperçoit
/// avec de faux forfaits.
struct PaywallPurchasePanel: View {
    let plans: [PaywallPlan]
    let isLoadingPlans: Bool
    @Binding var selectedKind: PaywallPlan.Kind
    /// Texte d'essai gratuit de l'annuel, `nil` si non éligible.
    let trialText: String?
    /// Prix de l'achat à vie ; `nil` si le produit est absent ou déjà possédé.
    let lifetimePrice: String?
    let isPurchasing: Bool
    let isPurchasingLifetime: Bool
    let isRestoring: Bool
    let onSubscribe: () -> Void
    let onLifetime: () -> Void
    let onRestore: () -> Void
    let onRedeemCode: () -> Void
    let onRetry: () -> Void

    private var selectedPlan: PaywallPlan? {
        plans.first { $0.kind == selectedKind } ?? plans.first
    }

    /// L'essai n'existe que sur l'annuel.
    private var activeTrial: String? {
        selectedPlan?.kind == .yearly ? trialText : nil
    }

    var body: some View {
        VStack(spacing: 6) {
            if let selectedPlan {
                VStack(spacing: 8) {
                    ForEach(plans) { plan in
                        PaywallPlanCard(plan: plan, isSelected: plan.kind == selectedPlan.kind) {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedKind = plan.kind
                        }
                    }
                }

                subscribeButton
                    .padding(.top, 4)

                Text(PaywallLegalText.renewal(kind: selectedPlan.kind, price: selectedPlan.displayPrice, trial: activeTrial))
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isLoadingPlans {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                unavailableState
            }

            if let lifetimePrice {
                PaywallLifetimeRow(displayPrice: lifetimePrice, isPurchasing: isPurchasingLifetime, onPurchase: onLifetime)
            }

            PaywallFooterLinks(isRestoring: isRestoring, onRestore: onRestore, onRedeemCode: onRedeemCode)

            legalLinks
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .background(Color.appBackground)
    }

    private var subscribeButton: some View {
        Button(action: onSubscribe) {
            Group {
                if isPurchasing && !isPurchasingLifetime {
                    ProgressView()
                } else {
                    (activeTrial != nil ? Text("Commencer l'essai gratuit") : Text("S'abonner"))
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color.goldWarm)
        .disabled(isPurchasing)
        .accessibilityIdentifier("paywall.subscribe")
    }

    private var unavailableState: some View {
        VStack(spacing: 8) {
            Text("Les abonnements ne sont pas disponibles pour le moment.")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
            Button("Réessayer", action: onRetry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.goldText)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Link("Conditions d'utilisation", destination: AppInfo.termsURL)
            Link("Confidentialité", destination: AppInfo.privacyURL)
        }
        .font(.caption)
        .foregroundStyle(Color.appSecondaryText)
        .padding(.bottom, 8)
    }
}

#Preview("Avec essai") {
    PaywallPurchasePanel(
        plans: [
            PaywallPlan(kind: .yearly, id: "y", displayPrice: "17,99 €", monthlyEquivalent: "1,50 €", savingsPercent: 25),
            PaywallPlan(kind: .monthly, id: "m", displayPrice: "1,99 €", monthlyEquivalent: nil, savingsPercent: nil)
        ],
        isLoadingPlans: false,
        selectedKind: .constant(.yearly),
        trialText: "1 semaine d'essai gratuit",
        lifetimePrice: "39,99 €",
        isPurchasing: false,
        isPurchasingLifetime: false,
        isRestoring: false,
        onSubscribe: {}, onLifetime: {}, onRestore: {}, onRedeemCode: {}, onRetry: {}
    )
}

#Preview("Indisponible") {
    PaywallPurchasePanel(
        plans: [], isLoadingPlans: false, selectedKind: .constant(.yearly), trialText: nil, lifetimePrice: nil,
        isPurchasing: false, isPurchasingLifetime: false, isRestoring: false,
        onSubscribe: {}, onLifetime: {}, onRestore: {}, onRedeemCode: {}, onRetry: {}
    )
}
