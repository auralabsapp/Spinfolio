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
    /// Date de la dernière vérification complète (premier plan ou arrière-plan) arrivée au bout.
    private let lastFullCheckKey = "com.spinlog.wantlistAlerts.lastFullCheckAt"
    /// Délai minimal entre deux vérifications déclenchées par l'ouverture de l'app : chaque
    /// vérification coûte une requête Discogs par alerte, et des allers-retours rapides entre
    /// apps épuiseraient sinon le quota partagé avec le reste de l'app.
    private let minimumAppOpenCheckInterval: TimeInterval = 15 * 60
    /// Garantit que la migration depuis l'ancien stockage global (avant l'isolation par compte)
    /// ne se produit qu'une seule fois, vers le premier compte activé après cette mise à jour —
    /// même principe que `TagStore.legacyMigrationFlagKey`.
    private static let legacyMigrationFlagKey = "com.spinlog.wantlistAlertStore.migratedToPerAccount"
    private(set) var alerts: [Int: WantlistAlertBox] = [:]
    private(set) var isChecking: Bool = false

    /// Compte Discogs actuellement actif, ou `nil` si personne n'est connecté. Piloté
    /// exclusivement par `DiscogsAuthManager` via `setActiveUsername` — mêmes clés `UserDefaults`
    /// que `TagStore`/`ListeningLogStore` : avant ce champ, les alertes de prix étaient stockées
    /// sous une seule clé globale, donc visibles par n'importe quel compte connecté sur
    /// l'appareil plutôt que cloisonnées par utilisateur.
    private(set) var activeUsername: String?

    private init() {
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

    /// Bascule ce store sur les données propres au compte Discogs indiqué, comme
    /// `TagStore.setActiveUsername` : sauvegarde déjà à jour (chaque mutation persiste
    /// immédiatement), donc il suffit de recharger l'état en mémoire depuis le stockage propre à
    /// ce compte. Appelé par `DiscogsAuthManager` au lancement de l'app, à la connexion et à la
    /// déconnexion.
    func setActiveUsername(_ username: String?) {
        let normalized = Self.normalize(username)
        guard normalized != activeUsername else { return }
        let previousUsername = activeUsername
        activeUsername = normalized
        // Notifications programmées ou affichées du compte qu'on quitte : elles ne doivent pas
        // s'afficher pour le compte suivant (ni après la déconnexion).
        if previousUsername != nil {
            removeAllAlertNotifications()
        }
        guard let normalized else {
            // Déconnecté : on vide l'état en mémoire sans toucher au disque, pour ne pas laisser
            // les alertes d'un compte visibles tant qu'aucun compte n'est actif, et on annule le
            // réveil en arrière-plan, qui n'a plus rien à vérifier.
            alerts = [:]
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: wantlistAlertsTaskIdentifier)
            return
        }
        loadAlerts(for: normalized)
    }

    private static func normalize(_ username: String?) -> String? {
        guard let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func key(_ base: String, for username: String) -> String {
        "\(base)_\(username)"
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
        removeNotifications(for: releaseId)
        cancelBackgroundCheckIfIdle()
        CloudSyncEngine.shared.markWantlistAlertDeleted(releaseId: releaseId)
    }

    /// Identifiant unique par release : une nouvelle bonne affaire remplace la notification
    /// précédente du même disque, et la suppression de l'alerte retrouve bien sa notification.
    /// (L'ancien identifiant, suffixé du prix, ne correspondait jamais à celui retiré ici.)
    private static let notificationIdentifierPrefix = "wantlist_alert_"

    private static func notificationIdentifier(for releaseId: Int) -> String {
        "\(notificationIdentifierPrefix)\(releaseId)"
    }

    /// Toutes les notifications d'alerte (programmées et affichées), quel que soit le disque.
    private func removeAllAlertNotifications() {
        let center = UNUserNotificationCenter.current()
        Task {
            let prefix = Self.notificationIdentifierPrefix
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            center.removeDeliveredNotifications(withIdentifiers: delivered)
        }
    }

    private func removeNotifications(for releaseId: Int) {
        let identifiers = [Self.notificationIdentifier(for: releaseId)]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
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
        removeNotifications(for: releaseId)
        cancelBackgroundCheckIfIdle()
    }

    // MARK: - Persistance

    /// Tolérant aux données partiellement illisibles (voir `PersistedStoreDecoding`).
    private func loadAlerts(for username: String) {
        var dict: [Int: WantlistAlertBox] = [:]
        for item in PersistedStoreDecoding.decodeArray(WantlistAlert.self, forKey: key(storageKey, for: username)) ?? [] {
            dict[item.releaseId] = WantlistAlertBox(alert: item)
        }
        alerts = dict
        migrateLegacyAlertsIfNeeded()
    }

    /// Reprend, une seule fois au total, les alertes créées avant l'isolation par compte
    /// (stockées sous la clé globale non préfixée) pour le premier compte activé — même
    /// mécanisme que `TagStore.migrateLegacyDataIfNeeded`. Ne remplace jamais des alertes déjà
    /// présentes pour ce compte (ne s'applique qu'au tout premier chargement après cette mise à
    /// jour, avant que quoi que ce soit n'ait encore été écrit sous une clé par compte).
    private func migrateLegacyAlertsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.legacyMigrationFlagKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.legacyMigrationFlagKey)

        guard alerts.isEmpty,
              let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WantlistAlert].self, from: data),
              !decoded.isEmpty else { return }

        var dict: [Int: WantlistAlertBox] = [:]
        for item in decoded {
            dict[item.releaseId] = WantlistAlertBox(alert: item)
        }
        alerts = dict
        persistAlerts()
    }

    private func persistAlerts() {
        guard let activeUsername else { return }
        let array = alerts.values.map(\.alert)
        if let data = try? JSONEncoder().encode(array) {
            UserDefaults.standard.set(data, forKey: key(storageKey, for: activeUsername))
        }
    }

    /// Suppression des données du compte (Réglages → Supprimer mon compte) : alertes et date de
    /// dernière vérification.
    func clearAccountData(for username: String) {
        guard let normalized = Self.normalize(username) else { return }
        UserDefaults.standard.removeObject(forKey: key(storageKey, for: normalized))
        UserDefaults.standard.removeObject(forKey: key(lastFullCheckKey, for: normalized))
        if activeUsername == normalized {
            alerts = [:]
            removeAllAlertNotifications()
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

        // Le compte peut changer pendant la vérification (déconnexion) : on s'arrête alors, pour
        // ne jamais notifier une alerte du compte qu'on vient de quitter.
        let checkedUsername = activeUsername
        var completed = true
        for box in Array(alerts.values) {
            guard activeUsername == checkedUsername else {
                completed = false
                break
            }
            // Tâche de fond expirée (voir `AppDelegate`) : on s'arrête net. Chaque alerte déjà
            // vérifiée a été enregistrée au fil de l'eau par `checkSingleAlert`.
            guard !Task.isCancelled else {
                logger.info("Vérification des alertes interrompue (tâche annulée).")
                completed = false
                break
            }
            await checkSingleAlert(box.alert)
        }
        if completed, let activeUsername {
            UserDefaults.standard.set(Date(), forKey: key(lastFullCheckKey, for: activeUsername))
        }

        scheduleBackgroundCheck()
    }

    /// Vérification déclenchée à chaque ouverture de l'app (lancement et retour au premier
    /// plan) : sans elle, un utilisateur ayant désactivé l'actualisation en arrière-plan (ou
    /// qu'iOS ne réveille pas) ne voyait ses alertes vérifiées qu'à leur création. Ignorée si
    /// une vérification complète a eu lieu il y a moins de `minimumAppOpenCheckInterval`.
    func checkAlertsOnAppOpen() async {
        if let activeUsername,
           let lastCheck = UserDefaults.standard.object(forKey: key(lastFullCheckKey, for: activeUsername)) as? Date,
           Date().timeIntervalSince(lastCheck) < minimumAppOpenCheckInterval {
            return
        }
        // Déclenché automatiquement au lancement/retour au premier plan, jamais par un geste
        // explicite (contrairement au pull-to-refresh de `WantlistView`, qui appelle `checkAlerts()`
        // directement et doit donc rester en priorité normale).
        await DiscogsRateLimiter.$priority.withValue(.background) {
            await checkAlerts()
        }
    }

    /// Vérifie une alerte précise et envoie une notification si le prix est inférieur au seuil
    func checkSingleAlert(_ alert: WantlistAlert) async {
        let checkedUsername = activeUsername
        do {
            let stats = try await DiscogsAPIClient.shared.marketplaceStats(
                releaseId: alert.releaseId,
                currency: alert.currency,
                credentials: DiscogsAuthManager.shared.credentials
            )
            // Prix le plus bas, converti si besoin dans la devise de l'alerte.
            var lowestPrice: Double?
            if let lowest = stats.lowestPrice {
                if lowest.currency.uppercased() == alert.currency.uppercased() {
                    lowestPrice = lowest.value
                } else {
                    lowestPrice = await CurrencyConversionService.shared.convert(
                        lowest.value,
                        from: lowest.currency,
                        to: alert.currency
                    )
                }
            }

            // L'alerte a pu être modifiée (prix cible, devise) ou supprimée pendant les requêtes :
            // on repart de sa version actuelle plutôt que de la copie d'avant la requête, qui
            // écrasait sinon la modification de l'utilisateur. Devise changée : ce résultat
            // n'est plus comparable, la prochaine vérification s'en chargera.
            // Compte changé pendant les requêtes : le même disque peut avoir une alerte sur l'autre
            // compte, qui ne doit recevoir ni ce prix ni sa notification.
            guard activeUsername == checkedUsername else { return }
            guard let current = alerts[alert.releaseId]?.alert, current.currency == alert.currency else { return }
            var updated = current
            updated.lastCheckedAt = Date()
            updated.currentNumForSale = stats.numForSale
            updated.currentLowestPrice = lowestPrice
            if lowestPrice != nil {
                updated.currentLowestPriceCurrency = alert.currency
            }

            if let lowestPrice, lowestPrice <= updated.targetPrice {
                // Ne notifie que si nous n'avons pas déjà notifié pour ce prix ou un prix inférieur.
                let shouldNotify = updated.lastNotifiedPrice.map { lowestPrice < $0 } ?? true
                if shouldNotify {
                    updated.lastNotifiedPrice = lowestPrice
                    // Enregistré AVANT d'envoyer la notification : si l'app est suspendue juste
                    // après (tâche de fond expirée), le passage suivant ne la renverra pas.
                    // Auparavant, rien n'était enregistré avant la fin de toute la boucle.
                    upsert(updated)
                    persistAlerts()
                    await postNotification(for: updated, price: lowestPrice)
                }
            } else {
                // Repassé au-dessus du seuil (ou plus rien en vente) : on réarme l'alerte, pour
                // qu'une nouvelle baisse sous le seuil soit à nouveau signalée — même à un prix
                // déjà notifié par le passé.
                updated.lastNotifiedPrice = nil
            }

            // Supprimée pendant l'envoi de la notification : ne pas la ressusciter.
            guard alerts[alert.releaseId] != nil else { return }
            // Mutation de la boîte existante en place (pas de réassignation de `alerts`) : seule
            // cette alerte réinvalide ses lecteurs, pas la liste Wantlist entière.
            upsert(updated)
            persistAlerts()

            // Synchronisé pour que les autres appareils voient le dernier prix constaté et
            // n'envoient pas une seconde notification pour un prix déjà signalé par celui-ci —
            // mais pas quand seule la date de vérification a changé : sinon chaque passage (toutes
            // les 3 h) renvoyait toutes les alertes vers iCloud.
            var withoutCheckDate = updated
            withoutCheckDate.lastCheckedAt = current.lastCheckedAt
            if withoutCheckDate != current {
                CloudSyncEngine.shared.markWantlistAlertDirty(releaseId: alert.releaseId)
            }
        } catch {
            logger.warning("Échec de vérification marketplace pour release \(alert.releaseId): \(error.localizedDescription)")
        }
    }

    // MARK: - Envoi de Notification Locale

    private func postNotification(for alert: WantlistAlert, price: Double) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "🎯 Bonne affaire Wantlist !")
        let formattedPrice = price.formatted(.currency(code: alert.currency))
        content.body = String(localized: "« \(alert.albumTitle) » (\(alert.artistName)) est disponible dès \(formattedPrice) sur Discogs !")
        content.sound = .default
        content.userInfo = [
            "releaseId": alert.releaseId,
            "type": "wantlist_alert"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier(for: alert.releaseId),
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
    ///
    /// Ne resoumet rien si une vérification est déjà planifiée : resoumettre remplace la demande
    /// existante et repousse donc son déclenchement à "maintenant + 3 h". Comme cette méthode est
    /// appelée à chaque passage en arrière-plan (et à chaque alerte reçue d'iCloud), un
    /// utilisateur ouvrant l'app plus souvent que toutes les 3 h ne voyait sinon jamais la
    /// vérification s'exécuter.
    func scheduleBackgroundCheck() {
        guard PremiumStore.shared.isPremium else { return }
        guard !alerts.isEmpty else { return }

        Task {
            let pending = await BGTaskScheduler.shared.pendingTaskRequests()
            guard !pending.contains(where: { $0.identifier == wantlistAlertsTaskIdentifier }) else { return }

            let request = BGAppRefreshTaskRequest(identifier: wantlistAlertsTaskIdentifier)
            // Demande un rafraîchissement au plus tôt après 3 heures
            request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
            do {
                if #available(iOS 27.0, *) {
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                } else {
                    try BGTaskScheduler.shared.submit(request)
                }
                logger.info("Tâche d'arrière-plan programmée avec succès.")
            } catch {
                logger.error("Impossible de soumettre la tâche d'arrière-plan: \(error.localizedDescription)")
            }
        }
    }

    /// Plus aucune alerte : inutile de réveiller l'app pour rien.
    private func cancelBackgroundCheckIfIdle() {
        guard alerts.isEmpty else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: wantlistAlertsTaskIdentifier)
    }
}
