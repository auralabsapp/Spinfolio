import Foundation
import OSLog

private let widgetSyncLogger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "WidgetSnapshotSync")

/// Alimente le widget "Album du jour" dès le lancement de l'app (et au retour au premier plan),
/// sans dépendre du fait que l'utilisateur visite un onglet particulier (Collection tant qu'il ne
/// consulte pas spécifiquement le dossier "All", Stats seulement s'il y va) : ces écrans ne
/// synchronisent la collection complète que dans des conditions spécifiques, ce qui laissait le
/// widget vide pour beaucoup d'utilisateurs malgré une collection non vide. Extrait de
/// `RootTabView`, qui appelait `DiscogsAPIClient` directement — une `View` ne devrait piloter que
/// l'affichage, pas orchestrer des appels réseau (même principe que
/// `CollectionExportViewModel`/`OfflineDownloadManager`, déjà séparés de leurs vues).
@MainActor
final class WidgetSnapshotSyncService {
    static let shared = WidgetSnapshotSyncService()

    private init() {}

    func refreshIfNeeded(username: String, credentials: DiscogsCredentials?) async {
        // 1. Alimentation IMMÉDIATE depuis le cache local SwiftData :
        // Si le widget est vide ou a moins de disques que le cache local, on le peuple
        // instantanément sans attendre de requête réseau ni risquer de rate limit.
        let localItems = await LocalDataStore.shared.getAllCollectionItems(username: username)
        let currentSnapshotCount = WidgetSnapshotStore.loadCollection().count
        if !localItems.isEmpty && (currentSnapshotCount == 0 || localItems.count > currentSnapshotCount) {
            LocalDataStore.shared.updateWidgetSnapshot(localItems)
            widgetSyncLogger.log("Sync widget : instantané immédiatement alimenté depuis le cache local (\(localItems.count) disques).")
        }

        guard let credentials else { return }
        guard NetworkMonitor.shared.isConnected else {
            widgetSyncLogger.log("Sync widget réseau ignorée : hors ligne.")
            return
        }
        let isStale = LocalDataStore.shared.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId)
        let snapshotIsEmpty = WidgetSnapshotStore.loadCollection().isEmpty
        guard isStale || snapshotIsEmpty else {
            widgetSyncLogger.log("Sync widget ignorée : cache déjà frais et instantané non vide.")
            return
        }
        widgetSyncLogger.log("Sync widget : récupération de la collection complète (isStale=\(isStale), snapshotIsEmpty=\(snapshotIsEmpty))...")
        do {
            let items = try await DiscogsAPIClient.shared.fetchAllCollectionItems(
                username: username, folderId: DiscogsConstants.allFolderId, credentials: credentials
            )
            widgetSyncLogger.log("Sync widget : \(items.count) exemplaire(s) récupéré(s) depuis Discogs.")
            LocalDataStore.shared.syncCollectionFolder(username: username, folderId: DiscogsConstants.allFolderId, fullItems: items)
            widgetSyncLogger.log("Sync widget : instantané écrit, \(WidgetSnapshotStore.loadCollection().count) disque(s) désormais visibles par le widget.")
        } catch {
            widgetSyncLogger.error("Sync widget : échec de récupération de la collection — \(error.localizedDescription)")
            // En cas d'erreur réseau, si le widget n'a toujours rien, repli gracieux sur le cache local
            if WidgetSnapshotStore.loadCollection().isEmpty {
                let cached = await LocalDataStore.shared.getAllCollectionItems(username: username)
                if !cached.isEmpty {
                    LocalDataStore.shared.updateWidgetSnapshot(cached)
                }
            }
        }
    }
}
