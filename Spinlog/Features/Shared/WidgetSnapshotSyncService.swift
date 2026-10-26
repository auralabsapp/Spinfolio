import Foundation
import OSLog

private let widgetSyncLogger = Logger(subsystem: AppInfo.logSubsystem, category: "WidgetSnapshotSync")

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
        // Déconnexion ou changement de compte pendant la lecture : le widget a déjà été vidé, il
        // ne doit pas se remplir avec la collection du compte qu'on vient de quitter.
        guard DiscogsAuthManager.shared.username == username else { return }
        let currentSnapshotCount = WidgetSnapshotStore.collectionCount
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
        let snapshotIsEmpty = WidgetSnapshotStore.collectionCount == 0
        guard isStale || snapshotIsEmpty else {
            widgetSyncLogger.log("Sync widget ignorée : cache déjà frais et instantané non vide.")
            return
        }
        // Renonce si une autre synchronisation complète du même dossier est déjà en cours
        // (lancement à froid : `StatsViewModel`/`CollectionViewModel`/`OfflineDownloadManager`
        // peuvent aussi vouloir tout recharger en même temps) — le widget sera de toute façon
        // alimenté par `updateWidgetSnapshot` une fois celle-ci terminée.
        guard LocalDataStore.shared.beginFullCollectionSync(username: username, folderId: DiscogsConstants.allFolderId) else {
            widgetSyncLogger.log("Sync widget ignorée : une autre synchronisation complète est déjà en cours.")
            return
        }
        defer { LocalDataStore.shared.endFullCollectionSync(username: username, folderId: DiscogsConstants.allFolderId) }
        widgetSyncLogger.log("Sync widget : récupération de la collection complète (isStale=\(isStale), snapshotIsEmpty=\(snapshotIsEmpty))...")
        // Déclenché au lancement/retour au premier plan, jamais en réponse à une action visible
        // de l'utilisateur — priorité basse pour le quota Discogs (voir le même correctif sur
        // `CollectionViewModel.startBackgroundSync`).
        await DiscogsRateLimiter.$priority.withValue(.background) {
            do {
                let items = try await DiscogsAPIClient.shared.fetchAllCollectionItems(
                    username: username, folderId: DiscogsConstants.allFolderId, credentials: credentials
                )
                widgetSyncLogger.log("Sync widget : \(items.count) exemplaire(s) récupéré(s) depuis Discogs.")
                // Déconnexion ou changement de compte pendant le téléchargement : ce résultat
                // n'appartient plus au compte actif et ne doit pas atterrir dans le widget.
                guard DiscogsAuthManager.shared.username == username else { return }
                await LocalDataStore.shared.syncCollectionFolder(username: username, folderId: DiscogsConstants.allFolderId, fullItems: items)
                widgetSyncLogger.log("Sync widget : instantané écrit, \(WidgetSnapshotStore.collectionCount) disque(s) désormais visibles par le widget.")
            } catch {
                widgetSyncLogger.error("Sync widget : échec de récupération de la collection — \(error.localizedDescription)")
                // En cas d'erreur réseau, si le widget n'a toujours rien, repli gracieux sur le cache local
                if WidgetSnapshotStore.collectionCount == 0 {
                    let cached = await LocalDataStore.shared.getAllCollectionItems(username: username)
                    if !cached.isEmpty {
                        LocalDataStore.shared.updateWidgetSnapshot(cached)
                    }
                }
            }
        }
    }
}
