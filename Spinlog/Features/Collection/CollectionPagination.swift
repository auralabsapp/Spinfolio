import Foundation

/// Pagination paresseuse de la Collection : la 1re page s'affiche tout de suite (jamais toute la
/// collection d'un coup), puis une tâche de fond charge les pages suivantes — c'est la seconde
/// option explicitement permise par l'API Discogs pour les grosses collections, et c'est
/// nécessaire pour que la barre de navigation rapide (lettres/années) reflète tout le dossier
/// plutôt que seulement ce qui a déjà défilé à l'écran.
///
/// Extrait de `CollectionViewModel`, qui garde la liste affichée : il la fournit et l'applique
/// par les fermetures ci-dessous, et vérifie que le dossier et le compte n'ont pas changé.
@MainActor
final class CollectionPagination {
    /// Dossier et compte d'un parcours des pages.
    struct Context {
        let username: String
        let folderId: Int
        let credentials: DiscogsCredentials
    }

    private(set) var currentPage = 1
    private(set) var totalPages = 1
    private var backgroundSyncTask: Task<Void, Never>?
    /// Exemplaires effectivement renvoyés par Discogs depuis la dernière page 1 chargée (plus
    /// ceux ajoutés localement entre-temps). La liste part du cache et ne fait qu'accumuler les
    /// pages fraîches, pour éviter qu'elle se réduise à la seule page 1 : une fois toutes les
    /// pages parcourues, ce qui n'y figure pas a été supprimé ou déplacé ailleurs (ex. depuis
    /// discogs.com) et est retiré — sans quoi ces disques restaient affichés indéfiniment.
    private var serverInstanceIds: Set<Int> = []

    /// Liste actuellement affichée.
    var currentItems: () -> [CollectionItem] = { [] }
    /// Remplace la liste affichée.
    var applyItems: ([CollectionItem]) -> Void = { _ in }
    /// Le dossier et le compte de ce parcours sont-ils toujours ceux affichés ?
    var isCurrent: (Context) -> Bool = { _ in false }
    /// Critère et ordre de tri Discogs du moment.
    var sortParameters: () -> (sort: String?, order: String?) = { (nil, nil) }

    var isSyncingInBackground: Bool { backgroundSyncTask != nil }
    var hasMorePages: Bool { currentPage < totalPages }

    func cancelBackgroundSync() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
    }

    func reset() {
        cancelBackgroundSync()
        serverInstanceIds = []
        currentPage = 1
        totalPages = 1
    }

    /// Exemplaire ajouté localement pendant un parcours : Discogs peut ne pas le renvoyer dans
    /// ce parcours (page déjà chargée), il ne doit donc pas être élagué à la fin.
    func noteLocallyAdded(instanceId: Int) {
        serverInstanceIds.insert(instanceId)
    }

    /// Charge une page et la fusionne à la liste (`append`, voir `CollectionLocalChanges.merging`).
    func fetchPage(_ page: Int, context: Context, append: Bool) async throws {
        guard isCurrent(context) else { return }
        let sort = sortParameters()
        let response = try await DiscogsAPIClient.shared.collectionItems(
            username: context.username,
            folderId: context.folderId,
            page: page,
            sort: sort.sort,
            sortOrder: sort.order,
            credentials: context.credentials
        )
        // Le compte a pu changer pendant la requête (déconnexion puis connexion à un autre
        // compte, souvent sur le même dossier "Tous") : la page reçue ne lui appartient pas.
        guard isCurrent(context) else { return }
        let validReleases = response.releases.filter { $0.instanceId > 0 && $0.instanceId != $0.releaseId }
        let pageInstanceIds = Set(validReleases.map(\.instanceId))
        if page == 1 {
            serverInstanceIds = pageInstanceIds
        } else {
            serverInstanceIds.formUnion(pageInstanceIds)
        }
        applyItems(CollectionLocalChanges.merging(page: validReleases, into: currentItems(), append: append))
        currentPage = page
        totalPages = response.pagination.pages

        // Sauvegarde dans le cache local SwiftData avec horodatage : seulement les exemplaires de
        // cette page (le reste de la liste y est déjà). Réencoder et réinsérer toute la liste
        // cumulée à chaque page rendait la synchro d'une grosse collection quadratique. Le cache
        // complet du dossier est réécrit une fois, en fin de synchro (`syncCollectionFolder`).
        await LocalDataStore.shared.saveCollectionItems(validReleases, username: context.username, folderId: context.folderId)
    }

    /// Continue de charger les pages suivantes une par une derrière l'écran (chaque appel passe
    /// par le throttle Discogs), jusqu'à couvrir tout le dossier ou jusqu'à ce qu'un changement
    /// de dossier/tri annule cette tâche pour la remplacer par une nouvelle.
    ///
    /// `Task(priority: .utility)` ne règle que l'ordonnancement CPU : le throttle Discogs lit un
    /// `@TaskLocal` différent (`DiscogsRateLimiter.priority`), lié ici à `.background` pour que la
    /// synchro de fond cède la place aux requêtes de l'utilisateur. `withValue` propage la valeur
    /// à tous les `await` de cette tâche, y compris dans `fetchPage`.
    func startBackgroundSync(context: Context) {
        backgroundSyncTask?.cancel()
        let localStore = LocalDataStore.shared
        // Renonce si une autre synchronisation complète du même dossier est déjà en cours
        // (lancement à froid : `StatsViewModel`/`WidgetSnapshotSyncService`/
        // `OfflineDownloadManager` peuvent aussi vouloir tout recharger en même temps) — la
        // page 1 déjà affichée reste valide, un prochain passage sur cet onglet réessaiera.
        guard localStore.beginFullCollectionSync(username: context.username, folderId: context.folderId) else { return }
        backgroundSyncTask = Task(priority: .utility) { [weak self] in
            defer { localStore.endFullCollectionSync(username: context.username, folderId: context.folderId) }
            await DiscogsRateLimiter.$priority.withValue(.background) {
                guard let self else { return }
                var reachedLastPage = false
                while !Task.isCancelled, self.isCurrent(context) {
                    guard self.hasMorePages else {
                        reachedLastPage = true
                        break
                    }
                    do {
                        try await self.fetchPage(self.currentPage + 1, context: context, append: true)
                    } catch {
                        break
                    }
                }
                guard !Task.isCancelled else { return }
                self.backgroundSyncTask = nil
                // Élagage seulement après un parcours complet et réussi : après une erreur ou un
                // changement de dossier, la liste des exemplaires renvoyés serait incomplète.
                // Dossier ou compte changé en route : la liste affichée n'est plus celle de ce
                // dossier, elle ne doit pas remplacer son cache.
                guard self.isCurrent(context) else { return }
                if reachedLastPage {
                    let serverIds = self.serverInstanceIds
                    let items = self.currentItems()
                    if items.contains(where: { !serverIds.contains($0.instanceId) }) {
                        self.applyItems(items.filter { serverIds.contains($0.instanceId) })
                    }
                }
                await localStore.syncCollectionFolder(username: context.username, folderId: context.folderId, fullItems: self.currentItems())
            }
        }
    }
}
