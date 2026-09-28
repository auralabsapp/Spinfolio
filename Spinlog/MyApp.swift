import SwiftUI

@main struct MyApp: App {
    init() {
        KingfisherConfig.configure()
        _ = NetworkMonitor.shared
        _ = OfflineSyncQueue.shared
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
