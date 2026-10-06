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
            guard let appRefreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                WantlistAlertStore.shared.scheduleBackgroundCheck()
                await WantlistAlertStore.shared.checkAlerts()
                appRefreshTask.setTaskCompleted(success: true)
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
                    } else if newPhase == .active {
                        Task {
                            await NowPlayingActivityManager.shared.checkExpiry()
                        }
                    }
                }
        }
    }
}
