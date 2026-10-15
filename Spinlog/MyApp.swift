import SwiftUI
import UserNotifications
import BackgroundTasks
import OSLog

private nonisolated let appDelegateLogger = Logger(subsystem: "com.auralabs.Spinlog", category: "AppDelegate")

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: wantlistAlertsTaskIdentifier,
            using: nil
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                WantlistAlertStore.shared.scheduleBackgroundCheck()
                await WantlistAlertStore.shared.checkAlerts()
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
        KingfisherConfig.configure()
        _ = NetworkMonitor.shared
        _ = OfflineSyncQueue.shared
        SubscriptionManager.shared.start()

        // Au démarrage de l'app, aucun filtre n'est appliqué dans Collection et Wantlist
        CollectionViewModel.shared.clearFilters()
        WantlistViewModel.shared.clearFilters()
        if let username = DiscogsAuthManager.shared.username {
            CollectionPreferencesStore.clearFilterPreferences(for: username)
        }

        #if DEBUG
        // Journalise dans la console tout à-coup de défilement (voir `ScrollHitchMonitor`),
        // pour diagnostiquer les lags perçus en Liste/Mosaïque sans brancher Instruments.
        ScrollHitchMonitor.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onOpenURL { url in
                    guard url.scheme == "spinlog" else { return }
                    let releaseIdStr = url.path.replacingOccurrences(of: "/", with: "")

                    switch url.host {
                    case "end-session":
                        if let releaseId = Int(releaseIdStr) {
                            Task {
                                await NowPlayingActivityManager.shared.endActivity(for: releaseId)
                            }
                        } else {
                            Task {
                                await NowPlayingActivityManager.shared.endCurrentActivity()
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
