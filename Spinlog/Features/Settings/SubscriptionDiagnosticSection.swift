import SwiftUI

/// Diagnostic de l'abonnement, affiché seulement hors App Store (TestFlight, sandbox, Xcode) et
/// après déverrouillage (voir `SubscriptionDiagnosticUnlock`) :
/// montre ce que StoreKit renvoie réellement, pour comprendre un écart entre la page
/// « Gérer mon abonnement » d'Apple et l'accès Premium de l'app. Jamais visible des utilisateurs
/// de l'App Store ; textes volontairement non traduits (`verbatim`), réservés aux tests.
struct SubscriptionDiagnosticSection: View {
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var isRefreshing = false

    private static let dateFormat = Date.FormatStyle(date: .abbreviated, time: .standard)

    var body: some View {
        if subscriptionManager.showsDiagnostic {
            Section {
                row("Accès Premium", premiumStore.isPremium ? "oui" : "non")
                row("Abonnement (StoreKit)", premiumStore.hasSubscription ? "actif" : "aucun")
                row("Aperçu démo", premiumStore.isDemoPreview ? "oui" : "non")
                if subscriptionManager.lastEntitlements.isEmpty {
                    Text(verbatim: "Aucun droit renvoyé par StoreKit")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                } else {
                    ForEach(subscriptionManager.lastEntitlements) { entitlement in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entitlement.productID)
                                .font(.footnote.weight(.semibold))
                            Text(verbatim: details(for: entitlement))
                                .font(.footnote)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                if let lastCheck = subscriptionManager.lastEntitlementCheck {
                    row("Dernière vérification", lastCheck.formatted(Self.dateFormat))
                }
                Button {
                    isRefreshing = true
                    Task {
                        await subscriptionManager.updateCustomerProductStatus()
                        isRefreshing = false
                    }
                } label: {
                    HStack {
                        Text(verbatim: "Revérifier auprès de StoreKit")
                        if isRefreshing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefreshing)
            } header: {
                Text(verbatim: "Diagnostic abonnement (test)")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(Color.appSecondaryText)
        }
        .font(.footnote)
    }

    private func details(for entitlement: SubscriptionManager.EntitlementSnapshot) -> String {
        var parts: [String] = [entitlement.counted ? "retenu" : "ignoré"]
        if let expiration = entitlement.expirationDate {
            parts.append("expire le \(expiration.formatted(Self.dateFormat))")
        }
        if let revocation = entitlement.revocationDate {
            parts.append("révoqué le \(revocation.formatted(Self.dateFormat))")
        }
        return parts.joined(separator: " · ")
    }
}
