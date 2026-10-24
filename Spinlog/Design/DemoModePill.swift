import SwiftUI

/// Pastille flottante affichée pendant la démo, au-dessus des onglets : rappelle qu'il s'agit de
/// données d'exemple et donne une sortie en un toucher, sans confirmation (la démo ne contient rien à
/// perdre), vers l'écran d'accueil. Le bouton « Quitter le mode démo » de Réglages reste le second chemin.
struct DemoModePill: View {
    @State private var authManager = DiscogsAuthManager.shared

    var body: some View {
        Button {
            authManager.logout()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text("Mode démo")
                    .font(.footnote.weight(.semibold))
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color.orange.opacity(0.22)).interactive())
        .accessibilityLabel("Quitter la démo")
        .accessibilityHint("Mode démo actif")
        .accessibilityIdentifier("demoBannerExitButton")
    }
}
