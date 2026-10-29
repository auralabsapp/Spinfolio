import SwiftUI

/// Actions secondaires du paywall, sous les forfaits : « Restaurer un achat » et « Utiliser un code ».
/// Liens discrets plutôt que de gros boutons empilés, qui mangeaient la hauteur utile du paywall. La
/// restauration reste accessible depuis l'écran, comme l'exige l'App Review (3.1.1).
struct PaywallFooterLinks: View {
    let isRestoring: Bool
    let onRestore: () -> Void
    let onRedeemCode: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            link("Restaurer un achat", identifier: "paywall.restore", action: onRestore)
                .disabled(isRestoring)
            Text("·")
                .foregroundStyle(Color.appSecondaryText)
                .accessibilityHidden(true)
            link("Utiliser un code", identifier: "paywall.redeemCode", action: onRedeemCode)
        }
        .overlay { if isRestoring { ProgressView() } }
    }

    private func link(_ title: LocalizedStringKey, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.goldText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    PaywallFooterLinks(isRestoring: false, onRestore: {}, onRedeemCode: {})
        .padding(22)
        .background(Color.appBackground)
}
