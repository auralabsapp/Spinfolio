import SwiftUI

// Exclu des builds Release/App Store, comme `DeveloperOptionsView` dont il découpe les sections.
#if DEBUG

/// Simulation du compte Premium, accès au paywall et diagnostic StoreKit.
struct DeveloperPremiumSection: View {
    @Binding var showingPaywall: Bool
    @Binding var showingFeaturesSheet: Bool
    let showToast: (String) -> Void

    @State private var premiumStore = PremiumStore.shared
    @State private var subscriptionManager = SubscriptionManager.shared

    var body: some View {
            Section {
                Toggle(isOn: $premiumStore.developerOverride) {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Compte Premium")
                                .font(.body.weight(.medium))
                            Text(premiumStore.isPremium ? "Toutes les fonctions débloquées" : "Compte gratuit bridé")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .tint(Color.spinlogPink)

                Button {
                    showingPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.goldAccent)
                        Text("Afficher l'écran Paywall")
                            .foregroundStyle(.primary)
                    }
                }

                Button {
                    showingFeaturesSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "list.star")
                            .foregroundStyle(.blue)
                        Text("Afficher la fiche des fonctionnalités")
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "cart.fill")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("StoreKit 2")
                            .font(.body.weight(.medium))
                        Text(subscriptionManager.products.isEmpty ? "Aucun produit chargé" : "\(subscriptionManager.products.count) forfaits chargés (\(subscriptionManager.yearlyPriceString), \(subscriptionManager.monthlyPriceString))")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                        // Diagnostic temporaire : permet de voir directement sur l'appareil si
                        // `introductoryOffer` remonte bien depuis StoreKit (config locale ou réelle).
                        Text("Essai annuel : \(subscriptionManager.freeTrialText(for: .yearly) ?? "aucun (introductoryOffer = nil)")")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                        if let errorMessage = subscriptionManager.errorMessage {
                            Text("Erreur StoreKit : \(errorMessage)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    Button("Sync") {
                        Task {
                            await subscriptionManager.loadProducts()
                            await subscriptionManager.updateCustomerProductStatus()
                            showToast("StoreKit 2 synchronisé")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !subscriptionManager.purchasedProductIDs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Abonnement actif StoreKit")
                                .font(.body.weight(.medium))
                            Text(subscriptionManager.purchasedProductIDs.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Text("Simulation Premium")
            } footer: {
                Text("Permet de basculer instantanément entre l'expérience gratuite et premium pour tester les bridages et paywalls.")
            }
    }
}

/// Simulation du mode hors ligne, sans couper le Wi-Fi.
struct DeveloperNetworkSection: View {
    @State private var networkMonitor = NetworkMonitor.shared

    var body: some View {
            Section {
                Toggle(isOn: $networkMonitor.simulatedOffline) {
                    HStack(spacing: 12) {
                        Image(systemName: networkMonitor.simulatedOffline ? "wifi.slash" : "wifi")
                            .foregroundStyle(networkMonitor.simulatedOffline ? .orange : .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simuler mode hors ligne")
                                .font(.body.weight(.medium))
                            Text(networkMonitor.simulatedOffline ? "Réseau désactivé artificiellement" : "Connectivité réelle")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .tint(.orange)

                HStack {
                    Text("État réseau réel")
                    Spacer()
                    Text(networkMonitor.isConnected ? "En ligne" : "Hors ligne")
                        .foregroundStyle(networkMonitor.isConnected ? .green : .red)
                        .font(.footnote.weight(.medium))
                }
            } header: {
                Text("Simulation Réseau")
            } footer: {
                Text("Active ce toggle pour tester le mode hors ligne sans avoir besoin d'activer le mode Avion de ton iPhone.")
            }
    }
}

/// File d'attente hors ligne (`OfflineSyncQueue`).
struct DeveloperSyncQueueSection: View {
    let showToast: (String) -> Void

    @State private var syncQueue = OfflineSyncQueue.shared

    var body: some View {
            Section {
                HStack {
                    Text("Actions en attente")
                    Spacer()
                    Text("\(syncQueue.pendingActions.count)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(syncQueue.pendingActions.isEmpty ? Color.appSecondaryText : .orange)
                }

                if !syncQueue.pendingActions.isEmpty {
                    Button {
                        Task { await syncQueue.processQueue() }
                        showToast("Traitement de la file d'attente lancé")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Forcer le traitement de la file")
                        }
                    }

                    Button(role: .destructive) {
                        syncQueue.clearQueue()
                        showToast("File d'attente vidée")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                            Text("Vider la file d'attente")
                        }
                    }
                }
            } header: {
                Text("File d'attente locale (Sync Queue)")
            }
    }
}

/// Synchronisation iCloud (`CloudSyncEngine`).
struct DeveloperCloudSyncSection: View {
    let showToast: (String) -> Void

    @State private var cloudSyncEngine = CloudSyncEngine.shared

    var body: some View {
            Section {
                HStack {
                    Text("Compte actif")
                    Spacer()
                    Text(cloudSyncEngine.activeUsername ?? "—")
                        .foregroundStyle(Color.appSecondaryText)
                }

                Button {
                    cloudSyncEngine.resetInitialSyncForActiveAccount()
                    showToast("Poussée initiale relancée pour ce compte sur cet appareil.")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Forcer une nouvelle poussée initiale")
                                .font(.body.weight(.medium))
                                .foregroundStyle(cloudSyncEngine.activeUsername == nil ? .secondary : .primary)
                            Text("Récupère et repousse tags, sessions, préférences et historique de valeur")
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .disabled(cloudSyncEngine.activeUsername == nil)
            } header: {
                Text("Synchronisation iCloud")
            } footer: {
                Text("Oublie que la synchro initiale a déjà eu lieu sur cet appareil pour ce compte, et la redéclenche immédiatement (récupération puis poussée). Utile pour retester la réconciliation entre deux appareils, ou repousser des données pré-existantes après l'ajout d'un nouveau genre synchronisé.")
            }
    }
}

#endif
