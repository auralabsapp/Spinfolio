import SwiftUI
import CloudKit

/// Diagnostic de la synchro iCloud, affiché seulement hors App Store et après déverrouillage (voir
/// `SubscriptionDiagnosticUnlock`), comme `SubscriptionDiagnosticSection` : dit si le moteur tourne,
/// quel compte est synchronisé, ce qui reste à envoyer et la dernière erreur. Jamais visible des
/// utilisateurs de l'App Store ; textes volontairement non traduits (`verbatim`), réservés aux tests.
struct CloudSyncDiagnosticSection: View {
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var cloudSyncEngine = CloudSyncEngine.shared
    @State private var accountStatus: CKAccountStatus?
    @State private var isRefreshing = false

    private static let dateFormat = Date.FormatStyle(date: .abbreviated, time: .standard)

    var body: some View {
        if subscriptionManager.showsDiagnostic {
            // Relu à chaque passage : `CloudSyncEngine` est `@Observable`, la section suit ses changements.
            let snapshot = cloudSyncEngine.diagnosticSnapshot()
            Section {
                row("Moteur démarré", yesNo(snapshot.engineRunning))
                row("Accès Premium", yesNo(snapshot.hasPremiumAccess))
                row("Interrupteur iCloud", snapshot.isUserEnabled ? "activé" : "coupé")
                row("Compte iCloud de l'appareil", accountStatus.map(describe) ?? "inconnu")
                row("Compte Discogs synchronisé", snapshot.activeUsername ?? "aucun")
                row("Fusion initiale faite", yesNo(snapshot.hydrated))
                row("Poussée initiale faite", yesNo(snapshot.initialPushDone))
                row("En attente d'envoi", "\(snapshot.pendingChangesForActiveAccount) (tous comptes : \(snapshot.pendingChanges))")
                if let summary = snapshot.lastSendSummary, let date = snapshot.lastSendDate {
                    row("Dernier envoi", "\(summary) · \(date.formatted(Self.dateFormat))")
                } else {
                    row("Dernier envoi", "aucun depuis le lancement")
                }
                if let failure = snapshot.lastFailure, let date = snapshot.lastFailureDate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Dernière erreur · \(date.formatted(Self.dateFormat))")
                            .font(.footnote.weight(.semibold))
                        Text(verbatim: failure)
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                } else {
                    row("Dernière erreur", "aucune depuis le lancement")
                }
                Button {
                    Task { await refresh() }
                } label: {
                    HStack {
                        Text(verbatim: "Actualiser")
                        if isRefreshing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefreshing)
                Button {
                    cloudSyncEngine.resetInitialSyncForActiveAccount()
                    Task { await refresh() }
                } label: {
                    Text(verbatim: "Relancer la fusion et la poussée initiales")
                }
                .disabled(snapshot.activeUsername == nil || !snapshot.engineRunning)
            } header: {
                Text(verbatim: "Diagnostic synchro iCloud (test)")
            } footer: {
                Text(verbatim: "La poussée initiale envoie tous les tags, écoutes et préférences locaux vers iCloud.")
            }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        isRefreshing = true
        accountStatus = await cloudSyncEngine.iCloudAccountStatus()
        isRefreshing = false
    }

    private func yesNo(_ value: Bool) -> String { value ? "oui" : "non" }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }

    private func describe(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: "connecté"
        case .noAccount: "aucun compte"
        case .restricted: "restreint"
        case .couldNotDetermine: "indéterminé"
        case .temporarilyUnavailable: "indisponible (temporaire)"
        @unknown default: "inconnu"
        }
    }
}
