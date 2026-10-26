import SwiftUI
import StoreKit

/// Page « À propos » de Réglages : site Discogs, gestion de l'abonnement, options développeur
/// (Debug seulement) et version.
struct AboutSettingsPage: View {
    /// Décompte des touchers sur la version (déverrouillage du diagnostic d'abonnement).
    @State private var diagnosticUnlock = SubscriptionDiagnosticUnlock()
    @State private var showingDiscogsWebsite = false
    @State private var showingManageSubscriptions = false

    var body: some View {
        SettingsSubPage(title: "À propos") {
            Section {
                Button {
                    showingDiscogsWebsite = true
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "globe", backgroundColor: .cyan)
                        Text("Site web Discogs")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }

                // Feuille système StoreKit (lecture seule, aucun risque à l'exposer partout,
                // contrairement aux outils du menu développeur) : état réel de l'abonnement, utile
                // notamment en TestFlight pour vérifier qu'un essai Sandbox précédent n'en a pas
                // laissé un actif avant d'en retenter un nouveau depuis le paywall.
                Button {
                    showingManageSubscriptions = true
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "creditcard.fill", backgroundColor: .indigo)
                        Text("Gérer mon abonnement")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.appTertiaryText)
                    }
                }

                #if DEBUG
                NavigationLink(value: SettingsDestination.developerOptions) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "hammer.fill", backgroundColor: .gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Options développeur")
                                .foregroundStyle(.primary)
                            Text("Debug, sauvegardes JSON & simulations")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.appTertiaryText)
                    }
                }
                #endif

                HStack(spacing: 14) {
                    SettingsIcon(systemName: "info.circle.fill", backgroundColor: .brown)
                    Text("Version")
                    Spacer()
                    Text(AppInfo.versionString)
                        .foregroundStyle(Color.appSecondaryText)
                }
                .contentShape(Rectangle())
                // Hors App Store seulement : 7 touchers affichent ou masquent le diagnostic
                // d'abonnement (voir `SubscriptionDiagnosticUnlock`). Volontairement sans
                // équivalent VoiceOver ni indice visuel : réservé aux tests TestFlight.
                .onTapGesture {
                    guard diagnosticUnlock.registerTap(),
                          SubscriptionManager.shared.toggleDiagnosticUnlock() else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } header: {
                SectionEyebrow(title: "À propos", icon: "info.circle.fill")
            } footer: {
                Text("\(AppInfo.name) utilise l'API publique Discogs mais n'est ni affilié à ni approuvé par Discogs.")
            }
        }
        .sheet(isPresented: $showingDiscogsWebsite) {
            SafariView(url: DiscogsConstants.websiteURL)
        }
        .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
    }
}

extension AppInfo {
    /// « 1.4 (23) » : version et numéro de build, affichés dans « À propos » et sur la ligne d'accueil.
    static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
