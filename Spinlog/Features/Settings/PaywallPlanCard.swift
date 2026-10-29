import SwiftUI

/// Carte d'un forfait du paywall : nom, prix et périodicité ; sur l'annuel, badge d'économie face au
/// mensuel et équivalent mensuel. La carte sélectionnée a un contour doré et une coche.
struct PaywallPlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let action: () -> Void

    private var isYearly: Bool { plan.kind == .yearly }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.goldText : Color.appSecondaryText)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        (isYearly ? Text("Annuel") : Text("Mensuel"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let percent = plan.savingsPercent {
                            Text("−\(percent) %")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.goldText))
                        }
                    }
                    subtitle
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.displayPrice)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    (isYearly ? Text("par an") : Text("par mois"))
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.appBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.goldText : Color.appSeparator, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(isYearly ? "paywall.plan.yearly" : "paywall.plan.monthly")
    }

    @ViewBuilder
    private var subtitle: some View {
        if let monthly = plan.monthlyEquivalent {
            Text("soit \(monthly) par mois")
        } else {
            Text("sans engagement")
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        PaywallPlanCard(
            plan: PaywallPlan(kind: .yearly, id: "y", displayPrice: "17,99 €", monthlyEquivalent: "1,50 €", savingsPercent: 25),
            isSelected: true
        ) {}
        PaywallPlanCard(
            plan: PaywallPlan(kind: .monthly, id: "m", displayPrice: "1,99 €", monthlyEquivalent: nil, savingsPercent: nil),
            isSelected: false
        ) {}
    }
    .padding(22)
    .background(Color.appBackground)
}
