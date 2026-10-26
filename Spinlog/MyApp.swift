import SwiftUI
import UserNotifications
import BackgroundTasks
import OSLog

private nonisolated let appDelegateLogger = Logger(subsystem: AppInfo.logSubsystem, category: "AppDelegate")

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // File principale plutôt que `nil` (file de fond par défaut) : ce gestionnaire est déclaré
        // dans un type isolé sur l'acteur principal ; en Swift 6, l'appeler depuis une autre file
        // déclencherait l'arrêt de l'app par la vérification d'isolation à l'exécution.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: wantlistAlertsTaskIdentifier,
            using: .main
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                // Ce réveil sert aussi à fermer une écoute arrivée à échéance pendant que l'app
                // était suspendue (voir `NowPlayingActivityManager.scheduleBackgroundExpiryCheck`).
                await NowPlayingActivityManager.shared.checkExpiry()
                WantlistAlertStore.shared.scheduleBackgroundCheck()
                // Vraie tâche de fond iOS (l'utilisateur ne regarde pas l'app) : priorité basse
                // pour le quota Discogs, par cohérence avec les autres synchros de fond.
                await DiscogsRateLimiter.$priority.withValue(.background) {
                    await WantlistAlertStore.shared.checkAlerts()
                }
                appRefreshTask.setTaskCompleted(success: !Task.isCancelled)
            }
            // Sans ce handler, une vérification trop longue (nombreuses alertes, quota Discogs)
            // dépassait le temps accordé par iOS, qui tuait alors l'app et réduisait ses futurs
            // créneaux d'arrière-plan. L'annulation interrompt la boucle et les requêtes en cours ;
            // la tâche est ensuite marquée terminée ci-dessus.
            appRefreshTask.expirationHandler = {
                work.cancel()
            }
        }
        application.registerForRemoteNotifications()
        return true
    }

    nonisolated func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        appDelegateLogger.log("didRegisterForRemoteNotificationsWithDeviceToken — \(deviceToken.count) octets")
    }

    nonisolated func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        appDelegateLogger.error("didFailToRegisterForRemoteNotificationsWithError : \(error, privacy: .public)")
    }

    // Réveil par notification silencieuse CloudKit : on attend la fin du fetch avant de rendre
    // la main, pour rester dans la fenêtre d'exécution en arrière-plan accordée par l'OS.
    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        appDelegateLogger.log("didReceiveRemoteNotification reçu")
        let didFetch = await CloudSyncEngine.shared.handleRemoteNotification()
        appDelegateLogger.log("didReceiveRemoteNotification — fetch terminé, didFetch=\(didFetch)")
        return didFetch ? .newData : .noData
    }

    // Permet d'afficher la bannière de notification même quand l'application est active au premier plan
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if userInfo["type"] as? String == "wantlist_alert",
           let releaseId = userInfo["releaseId"] as? Int {
            TabNavigationCoordinator.shared.openWantlistAlert(releaseId: releaseId)
        }
        completionHandler()
    }

    // Interdit formellement toute orientation paysage (Landscape) sur iPhone comme sur iPad
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return [.portrait, .portraitUpsideDown]
    }
}

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Tout premier : avant qu'un store ne lise les jetons ou n'écrive ses réglages.
        FreshInstallKeychainReset.runIfNeeded()
        KingfisherConfig.configure()
        _ = NetworkMonitor.shared
        _ = OfflineSyncQueue.shared
        SubscriptionManager.shared.start()
        #if DEBUG
        UITestLaunchOptions.apply()
        #endif

        // Au démarrage de l'app, aucun filtre n'est appliqué dans Collection et Wantlist
        CollectionViewModel.shared.display.clearFilters()
        WantlistViewModel.shared.clearFilters()
        if let username = DiscogsAuthManager.shared.username {
            CollectionPreferencesStore.clearFilterPreferences(for: username)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onOpenURL { url in
                    guard url.scheme == "spinlog" else { return }
                    let releaseIdStr = url.path.replacingOccurrences(of: "/", with: "")

                    switch url.host {
                    case "end-session":
                        // Seul le bouton de la Live Activity (lien avec jeton) peut arrêter l'écoute ;
                        // un lien sans identifiant de disque, qui arrêtait tout, est ignoré.
                        if let request = NowPlayingActivityAttributes.endSessionRequest(from: url) {
                            Task {
                                await NowPlayingActivityManager.shared.endActivityFromLink(releaseId: request.releaseId, token: request.token)
                            }
                        }
                    case "release":
                        if let releaseId = Int(releaseIdStr) {
                            TabNavigationCoordinator.shared.openRelease(id: releaseId)
                        }
                    default:
                        break
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        WantlistAlertStore.shared.scheduleBackgroundCheck()
                        DiscogsCategoryBackfillService.shared.stop()
                    } else if newPhase == .active {
                        // Classement des discographies de la bibliothèque, discret (voir le service).
                        DiscogsCategoryBackfillService.shared.start()
                        // Expiration, remboursement ou achat fait sur un autre appareil pendant que
                        // l'app était suspendue : `Transaction.updates` ne les signale pas toujours.
                        Task {
                            await SubscriptionManager.shared.updateCustomerProductStatus()
                        }
                        // Actions hors ligne restées en attente pendant que l'app était suspendue
                        // (le réseau a pu revenir sans que `networkConnectionRestored` soit reçu).
                        Task {
                            await OfflineSyncQueue.shared.processQueue()
                        }
                        Task {
                            await NowPlayingActivityManager.shared.checkExpiry()
                        }
                        // Lancement et retour au premier plan (voir `checkAlertsOnAppOpen`).
                        Task {
                            await WantlistAlertStore.shared.checkAlertsOnAppOpen()
                        }
                    }
                }
        }
    }
}
