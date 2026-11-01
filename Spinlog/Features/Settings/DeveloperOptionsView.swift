import SwiftUI
import WidgetKit

// Exclu des builds Release/App Store : ce type n'existe même pas en dehors du Debug, pour
// qu'aucun futur point d'entrée ne puisse le rendre accessible par erreur en production.
#if DEBUG

/// Écran d'options et d'outils développeur pour tester les fonctionnalités de Spinlog :
/// simulation du compte premium, simulation du mode hors ligne (sans couper le Wi-Fi),
/// déclenchement de la règle des 6h Discogs, et inspection des files de synchronisation.
struct DeveloperOptionsView: View {
    @State private var premiumStore = PremiumStore.shared
    @State private var authManager = DiscogsAuthManager.shared

    @State private var showingPaywall = false
    @State private var showingFeaturesSheet = false
    @State private var toastMessage: String? = nil

    // Alimentation ponctuelle du champ personnalisé "Prix d'achat net"
    @State private var isBackfillingNetPrice = false

    var body: some View {
        List {
            // MARK: - 1. Statut Premium & Achat
            DeveloperPremiumSection(
                showingPaywall: $showingPaywall,
                showingFeaturesSheet: $showingFeaturesSheet,
                showToast: showToast
            )

            // MARK: - 2. Simulation Réseau & Mode Hors Ligne
            DeveloperNetworkSection()

            // MARK: - 3. Règle des 6 heures Discogs (Cache Stale)
            Section {
                Button {
                    simulateStaleCache()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simuler expiration du cache (> 6h)")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Recule l'horodatage de 7 heures pour afficher le bandeau hors ligne")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }

                Button {
                    resetFreshCache()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Réinitialiser cache frais (< 6h)")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Met l'horodatage du cache à maintenant")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
            } header: {
                Text("Règle des 6h Discogs")
            } footer: {
                Text("Permet de tester l'apparition du bandeau d'instantané hors ligne conforme aux CGU Discogs.")
            }

            // MARK: - 4. File d'attente Hors Ligne (OfflineSyncQueue)
            DeveloperSyncQueueSection(showToast: showToast)

            // MARK: - 4bis. Synchronisation iCloud (CloudSyncEngine)
            DeveloperCloudSyncSection(showToast: showToast)

            // MARK: - 5. Caches & Widgets
            Section {
                Button {
                    KingfisherConfig.clearDiskCache()
                    showToast("Cache des images vidé")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(.purple)
                        Text("Vider le cache d'images")
                            .foregroundStyle(.primary)
                    }
                }

                Button {
                    WidgetCenter.shared.reloadAllTimelines()
                    showToast("Widgets rechargés")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.3.group")
                            .foregroundStyle(.indigo)
                        Text("Recharger les widgets")
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("Stockage & Widgets")
            }

            // MARK: - 6. Champs personnalisés (backfill ponctuel)
            Section {
                Button {
                    fillNetPurchasePriceField()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "eurosign.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alimentation prix d'achat net")
                                .font(.body.weight(.medium))
                                .foregroundStyle(authManager.isAuthenticated ? .primary : .secondary)
                            Text("Prix d'achat net = Prix d'achat − Réduction, sur toute la collection")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        if isBackfillingNetPrice {
                            ProgressView()
                        }
                    }
                }
                .disabled(isBackfillingNetPrice || !authManager.isAuthenticated)
            } header: {
                Text("Champs personnalisés")
            } footer: {
                Text("Recalcule et pousse sur Discogs le champ « Prix d'achat net » pour chaque exemplaire possédant au moins un prix d'achat ou une réduction renseigné(e) — une valeur manquante compte pour 0. Nécessite que les champs « Prix d'achat » (choisi dans Réglages), « Réduction » et « Prix d'achat net » existent déjà sur discogs.com.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .listRowSeparatorTint(Color.appSeparator)
        .navigationTitle("Options développeur")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingPaywall) {
            SpinlogPaywallView()
        }
        .sheet(isPresented: $showingFeaturesSheet) {
            PremiumFeaturesSheet()
        }
        .messageAlert(message: $toastMessage)
    }

    private func simulateStaleCache() {
        guard let username = authManager.username else {
            showToast("Connecte-toi d'abord à un compte Discogs")
            return
        }
        LocalDataStore.shared.simulateStaleCache(username: username)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showToast("Cache daté à -7 heures. Va sur Collection ou Wantlist en mode hors ligne pour voir le bandeau.")
    }

    private func resetFreshCache() {
        guard let username = authManager.username else {
            showToast("Connecte-toi d'abord à un compte Discogs")
            return
        }
        LocalDataStore.shared.resetCacheFreshness(username: username)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Horodatage réinitialisé à l'instant présent.")
    }

    private func fillNetPurchasePriceField() {
        guard let username = authManager.username, let credentials = authManager.credentials else {
            showToast("Connecte-toi d'abord à un compte Discogs")
            return
        }
        isBackfillingNetPrice = true
        Task {
            await runNetPurchasePriceBackfill(username: username, credentials: credentials)
            isBackfillingNetPrice = false
        }
    }

    private func runNetPurchasePriceBackfill(username: String, credentials: DiscogsCredentials) async {
        switch await NetPurchasePriceBackfill.run(username: username, credentials: credentials) {
        case .fieldsUnavailable:
            showToast("Impossible de récupérer les champs personnalisés Discogs.")
        case .discountFieldMissing:
            showToast("Champ « Réduc » introuvable sur Discogs. Crée-le d'abord depuis discogs.com.")
        case .netFieldMissing:
            showToast("Champ « Prix d'achat net » introuvable sur Discogs. Crée-le d'abord depuis discogs.com.")
        case .finished(let updated, let failures):
            let failureSuffix = failures > 0 ? " (\(failures) échec\(failures > 1 ? "s" : ""))" : ""
            showToast("Prix d'achat net recalculé pour \(updated) exemplaire\(updated > 1 ? "s" : "")\(failureSuffix).")
        }
    }

    private func showToast(_ msg: String) {
        toastMessage = msg
    }
}

#endif
