import SwiftUI

/// Interrupteur de la synchronisation iCloud (Premium). Couper la synchro arrête les échanges
/// depuis cet appareil sans rien effacer ; la réactiver refusionne tout avec iCloud (voir
/// `CloudSyncEngine.setUserEnabled`).
struct SettingsICloudSyncSection: View {
    @State private var premiumStore = PremiumStore.shared
    @State private var authManager = DiscogsAuthManager.shared
    @State private var cloudSyncEngine = CloudSyncEngine.shared

    var body: some View {
        Section {
            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "icloud.fill",
                    title: "Synchronisation iCloud",
                    message: "Passe premium pour retrouver tes tags, écoutes et préférences sur tous tes appareils."
                )
            } else {
                // La démo n'est jamais synchronisée : l'interrupteur y reste visible mais coupé,
                // pour montrer la fonction sans laisser croire que les données d'exemple partent.
                Toggle(isOn: Binding(
                    get: { !authManager.isDemoMode && cloudSyncEngine.isUserEnabled },
                    set: { cloudSyncEngine.setUserEnabled($0) }
                )) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "icloud.fill", backgroundColor: .blue)
                        Text("Synchroniser avec iCloud")
                            .foregroundStyle(.primary)
                    }
                }
                .tint(Color.spinlogPink)
                .disabled(authManager.isDemoMode)
            }
        } header: {
            SectionEyebrow(title: "Synchronisation iCloud", icon: "icloud.fill", isPremiumFeature: true)
        } footer: {
            if authManager.isDemoMode {
                Text("Désactivée pendant la démo : les données d'exemple restent sur cet appareil.")
            } else {
                Text("Tags, écoutes sur platine, alertes de prix et préférences suivent ton compte sur tous tes appareils. Couper la synchro n'efface rien : à sa réactivation, les modifications faites entre-temps sont fusionnées avec iCloud.")
            }
        }
    }
}
