import Foundation
import Observation
import Kingfisher
import UIKit

@Observable
@MainActor
final class OfflineDownloadManager {
    static let shared = OfflineDownloadManager()

    enum DownloadState: Equatable {
        case idle
        case downloadingCollection(page: Int, totalPages: Int, itemsCount: Int)
        case downloadingWantlist(page: Int, totalPages: Int)
        case cachingCovers(current: Int, total: Int)
        case completed(Date, Int)
        case failed(String)

        var isDownloading: Bool {
            switch self {
            case .downloadingCollection, .downloadingWantlist, .cachingCovers:
                return true
            default:
                return false
            }
        }

        var statusMessage: String {
            switch self {
            case .idle:
                return "Prêt"
            case .downloadingCollection(let page, let totalPages, let itemsCount):
                return "Téléchargement de la collection (page \(page)/\(totalPages) • \(itemsCount) disques)..."
            case .downloadingWantlist(let page, let totalPages):
                return "Téléchargement de la wantlist (page \(page)/\(totalPages))..."
            case .cachingCovers(let current, let total):
                return "Mise en cache des pochettes (\(current)/\(total))..."
            case .completed(_, let count):
                return "Synchronisation terminée avec succès (\(count) disques)"
            case .failed(let error):
                return "Erreur : \(error)"
            }
        }
    }

    private(set) var state: DownloadState = .idle
    private(set) var progress: Double = 0.0

    private let userDefaults = UserDefaults.standard
    private let lastSyncDateKey = "com.spinlog.lastOfflineSyncDate"
    private let offlineItemCountKey = "com.spinlog.offlineItemCount"
    private let autoSyncOverWifiKey = "com.spinlog.autoSyncOverWifiEnabled"

    var lastSyncDate: Date? {
        get { userDefaults.object(forKey: lastSyncDateKey) as? Date }
        set { userDefaults.set(newValue, forKey: lastSyncDateKey) }
    }

    var offlineItemCount: Int {
        get { userDefaults.integer(forKey: offlineItemCountKey) }
        set { userDefaults.set(newValue, forKey: offlineItemCountKey) }
    }

    /// Réglage utilisateur (désactivé par défaut) : si activé, `autoSyncIfNeeded` relance la
    /// synchro complète silencieusement dès qu'une connexion non facturée au volume (Wi-Fi) est
    /// disponible, sans attendre que l'utilisateur appuie sur le bouton.
    var isAutoSyncOverWifiEnabled: Bool {
        get { userDefaults.bool(forKey: autoSyncOverWifiKey) }
        set { userDefaults.set(newValue, forKey: autoSyncOverWifiKey) }
    }

    private var prefetcher: ImagePrefetcher?
    private var downloadTask: Task<Void, Never>?
    private var prefetchCompletedCount: Int = 0

    private init() {}

    /// Déclenche `startDownload` silencieusement si l'utilisateur premium a activé la synchro
    /// auto Wi-Fi (`isAutoSyncOverWifiEnabled`), que la connexion actuelle n'est pas facturée au
    /// volume (`!NetworkMonitor.isExpensive` : couvre aussi bien le cellulaire que le partage de
    /// connexion, contrairement à une simple détection d'interface Wi-Fi), et que la dernière
    /// synchro remonte à plus de 6h ou n'a jamais eu lieu — même fraîcheur que le reste de l'app.
    /// À appeler aux points d'entrée déjà existants (lancement, retour au premier plan), pas en
    /// continu : pas besoin de réagir instantanément à un changement de réseau pour ce cas d'usage.
    func autoSyncIfNeeded(username: String, credentials: DiscogsCredentials?, isPremium: Bool) {
        guard isPremium, isAutoSyncOverWifiEnabled else { return }
        guard !state.isDownloading else { return }
        guard NetworkMonitor.shared.isConnected, !NetworkMonitor.shared.isExpensive else { return }
        if let lastSyncDate, Date().timeIntervalSince(lastSyncDate) < DiscogsConstants.sixHoursTTL {
            return
        }
        startDownload(username: username, credentials: credentials)
    }

    /// Lance le téléchargement complet de la collection, de la wantlist et des pochettes,
    /// en respectant scrupuleusement la limitation de débit de l'API Discogs (60 requêtes/min).
    func startDownload(username: String, credentials: DiscogsCredentials?) {
        guard !state.isDownloading else { return }
        downloadTask?.cancel()

        downloadTask = Task { @MainActor in
            let apiClient = DiscogsAPIClient.shared

            do {
                // 1. Dossiers
                let foldersResponse = try await apiClient.collectionFolders(username: username, credentials: credentials)
                LocalDataStore.shared.saveFolders(foldersResponse.folders, username: username)

                // 2. Collection complète (page par page avec suivi)
                var allCollectionItems: [CollectionItem] = []
                var page = 1
                var totalPages = 1

                while page <= totalPages {
                    guard !Task.isCancelled else { return }
                    self.state = .downloadingCollection(page: page, totalPages: totalPages, itemsCount: allCollectionItems.count)
                    self.progress = Double(page - 1) / Double(max(1, totalPages)) * 0.6

                    let response = try await apiClient.collectionItems(
                        username: username,
                        folderId: DiscogsConstants.allFolderId,
                        page: page,
                        perPage: DiscogsConstants.maxPageSize,
                        credentials: credentials
                    )
                    totalPages = max(1, response.pagination.pages)
                    allCollectionItems.append(contentsOf: response.releases)
                    page += 1
                }

                guard !Task.isCancelled else { return }
                LocalDataStore.shared.syncCollectionFolder(
                    username: username,
                    folderId: DiscogsConstants.allFolderId,
                    fullItems: allCollectionItems
                )

                // 3. Wantlist
                var allWantlistItems: [WantlistItem] = []
                var wantlistPage = 1
                var wantlistTotalPages = 1

                while wantlistPage <= wantlistTotalPages {
                    guard !Task.isCancelled else { return }
                    self.state = .downloadingWantlist(page: wantlistPage, totalPages: wantlistTotalPages)
                    self.progress = 0.6 + (Double(wantlistPage - 1) / Double(max(1, wantlistTotalPages)) * 0.15)

                    let response = try await apiClient.wantlist(
                        username: username,
                        page: wantlistPage,
                        perPage: DiscogsConstants.maxPageSize,
                        credentials: credentials
                    )
                    wantlistTotalPages = max(1, response.pagination.pages)
                    allWantlistItems.append(contentsOf: response.wants)
                    wantlistPage += 1
                }

                guard !Task.isCancelled else { return }
                LocalDataStore.shared.saveWantlistItems(allWantlistItems, username: username)

                // 4. Pré-téléchargement des pochettes Kingfisher
                let collectionUrls = allCollectionItems.compactMap {
                    URL(string: $0.basicInformation.coverImage ?? $0.basicInformation.thumb ?? "")
                }
                let wantlistUrls = allWantlistItems.compactMap {
                    URL(string: $0.basicInformation.coverImage ?? $0.basicInformation.thumb ?? "")
                }
                let allUrls = Array(Set(collectionUrls + wantlistUrls))

                if !allUrls.isEmpty {
                    self.state = .cachingCovers(current: 0, total: allUrls.count)
                    await prefetchImages(urls: allUrls)
                }

                // 5. Finalisation
                let now = Date()
                self.lastSyncDate = now
                self.offlineItemCount = allCollectionItems.count
                self.progress = 1.0
                self.state = .completed(now, allCollectionItems.count)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            } catch {
                if !Task.isCancelled {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Interrompt le téléchargement en cours.
    func cancelDownload() {
        downloadTask?.cancel()
        prefetcher?.stop()
        state = .idle
        progress = 0.0
    }

    private func prefetchImages(urls: [URL]) async {
        self.prefetchCompletedCount = 0
        let total = urls.count

        await withCheckedContinuation { continuation in
            self.prefetcher = ImagePrefetcher(
                urls: urls,
                options: KingfisherManager.shared.defaultOptions,
                progressBlock: { _, _, completed in
                    let added = completed.count
                    Task { @MainActor in
                        self.prefetchCompletedCount += added
                        let current = min(self.prefetchCompletedCount, total)
                        self.state = .cachingCovers(current: current, total: total)
                        self.progress = 0.75 + (Double(current) / Double(max(1, total)) * 0.25)
                    }
                },
                completionHandler: { _, _, _ in
                    continuation.resume()
                }
            )
            self.prefetcher?.start()
        }
    }
}
