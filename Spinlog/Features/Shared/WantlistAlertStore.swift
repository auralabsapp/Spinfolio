import Foundation
import SwiftUI
import UserNotifications
import BackgroundTasks
import OSLog

private let logger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "WantlistAlerts")

/// Identifiant de tâche d'arrière-plan pour la vérification des alertes
public let wantlistAlertsTaskIdentifier = "com.aurelienscarpa.Spinlog.wantlistAlertsCheck"

/// Boîte observable individuelle pour une alerte : permet à `@Observable` de suivre la
/// mutation d'UNE seule alerte sans invalider tous les lecteurs de `WantlistAlertStore.alerts`.
/// Sans ce niveau d'indirection, muter n'importe quelle entrée du dictionnaire (ex: mise à jour
/// du prix constaté pendant `checkAlerts()`) réinvalide la propriété `alerts` dans son ensemble —
/// Observation ne suit pas les clés d'un dictionnaire individuellement — et fait donc re-rendre
/// toutes les lignes Wantlist affichant une alerte, pas seulement celle qui a changé.
@MainActor
@Observable
final class WantlistAlertBox {
    var alert: WantlistAlert
    init(alert: WantlistAlert) {
        self.alert = alert
    }
}

@MainActor
@Observable
final class WantlistAlertStore {
    static let shared = WantlistAlertStore()

    private let storageKey = "com.spinlog.wantlistAlerts"
    private(set) var alerts: [Int: WantlistAlertBox] = [:]
    private(set) var isChecking: Bool = false

    private init() {
        loadAlerts()

        // Reprend immédiatement (plutôt que d'attendre le prochain déclenchement naturel) si
        // l'utilisateur redevient premium après avoir laissé expirer son abonnement — voir les
        // garde-fous premium dans `checkAlerts()`/`scheduleBackgroundCheck()`.
        NotificationCenter.default.addObserver(
            forName: .premiumStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, PremiumStore.shared.isPremium else { return }
                self.scheduleBackgroundCheck()
                Task { await self.checkAlerts() }
            }
        }
    }

    // MARK: - CRUD

    func alert(for releaseId: Int) -> WantlistAlert? {
        alerts[releaseId]?.alert
    }

    func isTriggered(releaseId: Int) -> Bool {
        alerts[releaseId]?.alert.isTriggered ?? false
    }

    func saveAlert(_ alert: WantlistAlert) {
        upsert(alert)
        persistAlerts()
        scheduleBackgroundCheck()
        CloudSyncEngine.shared.markWantlistAlertDirty(releaseId: alert.releaseId)
        Task { [weak self] in
            await self?.checkSingleAlert(alert)
        }
    }

    func removeAlert(for releaseId: Int) {
        alerts.removeValue(forKey: releaseId)
        persistAlerts()
        // Retire d'éventuelles notifications locales en attente pour cette release
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["wantlist_alert_\(releaseId)"])
        CloudSyncEngine.shared.markWantlistAlertDeleted(releaseId: releaseId)
    }

    /// Met à jour la boîte existante en place si l'alerte existe déjà (ne réinvalide que cette
    /// boîte), sinon insère une nouvelle entrée (ajout/retrait de clé : invalide `alerts` dans
    /// son ensemble, mais c'est un événement rare comparé aux mises à jour de prix).
    private func upsert(_ alert: WantlistAlert) {
        if let box = alerts[alert.releaseId] {
            box.alert = alert
        } else {
            alerts[alert.releaseId] = WantlistAlertBox(alert: alert)
        }
    }

    // MARK: - Synchronisation iCloud (compte premium)

    /// Identifiants de toutes les releases ayant une alerte active, pour la synchronisation
    /// initiale (même besoin que `TagStore.allTaggedInstanceIds()`).
    func allAlertReleaseIds() -> [Int] {
        Array(alerts.keys)
    }

    /// Applique une alerte reçue d'iCloud (ajout ou mise à jour, y compris les champs de suivi
    /// comme le dernier prix constaté). N'écrit qu'en local : ne redéclenche pas d'envoi vers
    /// CloudKit, cette donnée en vient déjà.
    func applyRemoteAlert(_ alert: WantlistAlert) {
        upsert(alert)
        persistAlerts()
        scheduleBackgroundCheck()
    }

    /// Applique une suppression d'alerte reçue d'iCloud. N'écrit qu'en local.
    func applyRemoteAlertDeletion(releaseId: Int) {
        alerts.removeValue(forKey: releaseId)
        persistAlerts()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["wantlist_alert_\(releaseId)"])
    }

    // MARK: - Persistance

    private func loadAlerts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WantlistAlert].self, from: data) else {
            return
        }
        var dict: [Int: WantlistAlertBox] = [:]
        for item in decoded {
            dict[item.releaseId] = WantlistAlertBox(alert: item)
        }
        self.alerts = dict
    }

    private func persistAlerts() {
        let array = alerts.values.map(\.alert)
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Permissions de Notification

    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            logger.error("Erreur lors de la demande de notifications: \(error.localizedDescription)")
            return false
        }
    }

    func hasNotificationAuthorization() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // MARK: - Vérification des Alertes

    /// Vérifie l'ensemble des alertes actives auprès de l'API Discogs. No-op silencieux si
    /// l'utilisateur n'est pas (ou plus) premium : les alertes restent enregistrées localement
    /// mais plus aucun appel réseau ni notification n'est déclenché tant que l'abonnement n'est
    /// pas actif, à l'image de `CloudSyncEngine` pour la synchro iCloud.
    func checkAlerts() async {
        guard PremiumStore.shared.isPremium else { return }
        guard !alerts.isEmpty else { return }
        guard !isChecking else { return }
        guard NetworkMonitor.shared.isConnected else { return }

        isChecking = true
        defer { isChecking = false }

        logger.info("Début de la vérification de \(self.alerts.count) alerte(s)...")

        for box in Array(alerts.values) {
            await checkSingleAlert(box.alert)
        }

        persistAlerts()
        scheduleBackgroundCheck()
    }

    /// Vérifie une alerte précise et envoie une notification si le prix est inférieur au seuil
    func checkSingleAlert(_ alert: WantlistAlert) async {
        do {
            let stats = try await DiscogsAPIClient.shared.marketplaceStats(
                releaseId: alert.releaseId,
                currency: alert.currency,
                credentials: DiscogsAuthManager.shared.credentials
            )
            var updated = alert
            updated.lastCheckedAt = Date()
            updated.currentNumForSale = stats.numForSale

            if let lowest = stats.lowestPrice {
                // Convertit si besoin dans la devise de l'alerte
                let convertedPrice: Double
                if lowest.currency.uppercased() == alert.currency.uppercased() {
                    convertedPrice = lowest.value
                } else {
                    convertedPrice = await CurrencyConversionService.shared.convert(
                        lowest.value,
                        from: lowest.currency,
                        to: alert.currency
                    )
                }

                updated.currentLowestPrice = convertedPrice
                updated.currentLowestPriceCurrency = alert.currency

                // Vérifie si le prix est sous le seuil
                if convertedPrice <= alert.targetPrice {
                    // Ne notifie que si nous n'avons pas déjà notifié pour ce prix ou un prix supérieur
                    let shouldNotify: Bool
                    if let lastNotified = alert.lastNotifiedPrice {
                        shouldNotify = convertedPrice < lastNotified
                    } else {
                        shouldNotify = true
                    }

                    if shouldNotify {
                        await postNotification(for: updated, price: convertedPrice)
                        updated.lastNotifiedPrice = convertedPrice
                    }
                }
            } else {
                updated.currentLowestPrice = nil
            }

            // Mutation de la boîte existante en place (pas de réassignation de `alerts`) : seule
            // cette alerte réinvalide ses lecteurs, pas la liste Wantlist entière.
            if let box = alerts[alert.releaseId] {
                box.alert = updated
            }
            // Synchronisé pour que les autres appareils voient le dernier prix constaté et
            // n'envoient pas une seconde notification pour un prix déjà signalé par celui-ci.
            CloudSyncEngine.shared.markWantlistAlertDirty(releaseId: alert.releaseId)
        } catch {
            logger.warning("Échec de vérification marketplace pour release \(alert.releaseId): \(error.localizedDescription)")
        }
    }

    // MARK: - Envoi de Notification Locale

    private func postNotification(for alert: WantlistAlert, price: Double) async {
        let content = UNMutableNotificationContent()
        content.title = "🎯 Bonne affaire Wantlist !"
        let formattedPrice = price.formatted(.currency(code: alert.currency))
        content.body = "« \(alert.albumTitle) » (\(alert.artistName)) est disponible dès \(formattedPrice) sur Discogs !"
        content.sound = .default
        content.userInfo = [
            "releaseId": alert.releaseId,
            "type": "wantlist_alert"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "wantlist_alert_\(alert.releaseId)_\(Int(price))",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Notification programmée pour la release \(alert.releaseId) à \(formattedPrice)")
        } catch {
            logger.error("Erreur d'ajout de notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Background Task Scheduling

    /// Enregistre la tâche de fond auprès du système iOS. N'enregistre aucun réveil si
    /// l'utilisateur n'est pas premium, pour ne pas solliciter l'appareil pour une fonctionnalité
    /// à laquelle il n'a plus droit (voir `checkAlerts()`).
    func scheduleBackgroundCheck() {
        guard PremiumStore.shared.isPremium else { return }
        guard !alerts.isEmpty else { return }

        let request = BGAppRefreshTaskRequest(identifier: wantlistAlertsTaskIdentifier)
        // Demande un rafraîchissement au plus tôt après 3 heures
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)

        BGTaskScheduler.shared.submitTaskRequest(request) { error in
            if let error {
                logger.error("Impossible de soumettre la tâche d'arrière-plan: \(error.localizedDescription)")
            } else {
                logger.info("Tâche d'arrière-plan programmée avec succès.")
            }
        }
    }
}
