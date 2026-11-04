import Foundation
import OSLog

private let paginationLogger = Logger(subsystem: AppInfo.logSubsystem, category: "CollectionPagination")

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
    /// Dernier parcours annulé, gardé pour que le suivant attende sa fin (voir `startBackgroundSync`).
    private var cancelledSyncTask: Task<Void, Never>?
    /// Exemplaires effectivement renvoyés par Discogs depuis la dernière page 1 chargée (plus
    /// ceux ajoutés localement entre-temps). La liste part du cache et ne fait qu'accumuler les
    /// pages fraîches, pour éviter qu'elle se réduise à la seule page 1 : une fois toutes les
    /// pages parcourues, ce qui n'y figure pas a été supprimé ou déplacé ailleurs (ex. depuis
    /// discogs.com) et est retiré — sans quoi ces disques restaient affichés indéfiniment.
    private var serverInstanceIds: Set<Int> = []
    /// Diagnostic d'un parcours : total annoncé par Discogs, exemplaires reçus (doublons compris)
    /// et écartés comme « fantômes » (voir `fetchPage`).
    /// Pages reçues par la synchro de fond, pas encore appliquées à la liste affichée (voir
    /// `fetchPage(coalesced:)`).
    private var pendingPageItems: [CollectionItem] = []
    private var lastDisplayUpdate = Date.distantPast
    /// Intervalle minimal entre deux mises à jour de la liste pendant la synchro de fond.
    private static let displayUpdateInterval: TimeInterval = 3
    private var announcedTotal = 0
    private var receivedCount = 0
    private var phantomCount = 0

    /// Liste actuellement affichée.
    var currentItems: () -> [CollectionItem] = { [] }
    /// Remplace la liste affichée.
    var applyItems: ([CollectionItem]) -> Void = { _ in }
    /// Le dossier et le compte de ce parcours sont-ils toujours ceux affichés ?
    var isCurrent: (Context) -> Bool = { _ in false }
    /// Recharge la liste affichée depuis le cache, rempli entre-temps par une autre synchro.
    var reloadFromCache: (Context) async -> Void = { _ in }
    /// Critère et ordre de tri Discogs du moment.
    var sortParameters: () -> (sort: String?, order: String?) = { (nil, nil) }

    var isSyncingInBackground: Bool { backgroundSyncTask != nil }
    var hasMorePages: Bool { currentPage < totalPages }

    /// Applique à la liste affichée les pages reçues en attente.
    func flushPendingPages() {
        guard !pendingPageItems.isEmpty else { return }
        let pending = pendingPageItems
        pendingPageItems = []
        lastDisplayUpdate = Date()
        applyItems(CollectionLocalChanges.merging(page: pending, into: currentItems(), append: true))
    }

    func cancelBackgroundSync() {
        pendingPageItems = []
        if let backgroundSyncTask {
            backgroundSyncTask.cancel()
            cancelledSyncTask = backgroundSyncTask
        }
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
    /// `coalesced` : pour les pages de la synchro de fond. Chaque mise à jour de la liste recalcule
    /// sections, badges et tags sur tous les exemplaires puis redessine l'écran ; à une page toutes
    /// les secondes sur une collection de 2 000 albums, l'interface saccadait pendant tout le
    /// chargement. Les pages sont donc regroupées et appliquées toutes les 3 s environ (et à la fin).
    func fetchPage(_ page: Int, context: Context, append: Bool, coalesced: Bool = false) async throws {
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
            receivedCount = 0
            phantomCount = 0
        } else {
            serverInstanceIds.formUnion(pageInstanceIds)
        }
        announcedTotal = response.pagination.items
        receivedCount += response.releases.count
        phantomCount += response.releases.count - validReleases.count
        if coalesced {
            pendingPageItems += validReleases
            if Date().timeIntervalSince(lastDisplayUpdate) >= Self.displayUpdateInterval { flushPendingPages() }
        } else {
            applyItems(CollectionLocalChanges.merging(page: validReleases, into: currentItems(), append: append))
        }
        currentPage = page
        totalPages = response.pagination.pages

        // Sauvegarde dans le cache local SwiftData avec horodatage : seulement les exemplaires de
        // cette page (le reste de la liste y est déjà). Réencoder et réinsérer toute la liste
        // cumulée à chaque page rendait la synchro d'une grosse collection quadratique. Le cache
        // complet du dossier est réécrit une fois, en fin de synchro (`syncCollectionFolder`).
        // Sans horodatage de fraîcheur : le dossier n'est « complet » qu'à la fin du parcours
        // (`syncCollectionFolder`), pas après chaque page.
        // Pages de la synchro de fond : pas d'écriture page par page. Chaque écriture (encodage
        // et enregistrement SwiftData) se fait sur le fil principal et saccadait l'interface ;
        // la fin du parcours réécrit de toute façon tout le dossier. Un parcours interrompu
        // laisse le cache non frais, il sera repris au prochain passage.
        guard !coalesced else { return }
        await LocalDataStore.shared.saveCollectionItems(
            validReleases, username: context.username, folderId: context.folderId, stampsFreshness: false
        )
    }

    /// Continue de charger les pages suivantes une par une derrière l'écran (chaque appel passe
    /// par le throttle Discogs), jusqu'à couvrir tout le dossier ou jusqu'à ce qu'un changement
    /// de dossier/tri annule cette tâche pour la remplacer par une nouvelle.
    ///
    /// `Task(priority: .utility)` ne règle que l'ordonnancement CPU : le throttle Discogs lit un
    /// `@TaskLocal` différent (`DiscogsRateLimiter.priority`), lié ici à `.normal` (voir plus bas
    /// pourquoi la priorité basse ne convient pas à ce parcours). `withValue` propage la valeur
    /// à tous les `await` de cette tâche, y compris dans `fetchPage`.
    func startBackgroundSync(context: Context) {
        cancelBackgroundSync()
        let previous = cancelledSyncTask
        cancelledSyncTask = nil
        let localStore = LocalDataStore.shared
        backgroundSyncTask = Task(priority: .utility) { [weak self] in
            // Le parcours précédent, à peine annulé (rechargement, retour sur l'onglet), garde le
            // verrou de synchro tant que sa requête en cours n'est pas revenue : sans cette
            // attente, le nouveau parcours renonçait aussitôt et la collection restait aux
            // seules premières pages.
            await previous?.value
            guard !Task.isCancelled else { return }
            // Toujours en priorité normale : en priorité basse, ce parcours attendait 8 s de calme
            // après chaque requête normale et partageait le quota de fond avec la résolution des
            // années originales — sur une grosse collection, il ne se terminait pratiquement
            // jamais. Une vingtaine de requêtes pour 2 000 albums : l'impact sur les recherches et
            // les fiches reste bref.
            let priority: DiscogsRequestPriority = .normal
            // Une autre synchronisation complète du même dossier peut déjà tourner (Stats, widget,
            // données hors ligne) : on attend sa fin. Si elle a réussi, son cache complet et frais
            // est repris tel quel ; sinon, ce parcours prend le relais. Renoncer aussitôt (comme
            // avant) laissait la liste aux premières pages tant qu'on ne revenait pas sur l'onglet.
            let slot = await localStore.waitForFullCollectionSyncSlot(
                username: context.username, folderId: context.folderId
            ) { [weak self] in self?.isCurrent(context) ?? false }
            guard let slot else { return }
            guard let self else {
                if slot == .acquired { localStore.endFullCollectionSync(username: context.username, folderId: context.folderId) }
                return
            }
            if slot == .cacheRefreshed {
                await self.reloadFromCache(context)
                self.backgroundSyncTask = nil
                return
            }
            defer { localStore.endFullCollectionSync(username: context.username, folderId: context.folderId) }
            await DiscogsRateLimiter.$priority.withValue(priority) {
                var reachedLastPage = false
                while !Task.isCancelled, self.isCurrent(context) {
                    guard self.hasMorePages else {
                        reachedLastPage = true
                        break
                    }
                    let nextPage = self.currentPage + 1
                    // Panne passagère (quota Discogs dépassé, réseau coupé un instant) : la page est
                    // retentée après une pause plutôt que d'abandonner un parcours de plusieurs
                    // dizaines de pages, qui laissait une grosse collection chargée à moitié.
                    var succeeded = false
                    for attempt in 0..<4 {
                        do {
                            try await self.fetchPage(nextPage, context: context, append: true, coalesced: true)
                            succeeded = true
                            break
                        } catch {
                            paginationLogger.error("Page \(nextPage, privacy: .public)/\(self.totalPages, privacy: .public) échouée (essai \(attempt + 1, privacy: .public)) : \(String(describing: type(of: error)), privacy: .public)")
                            guard !Task.isCancelled, error.isTransientNetworkFailure, attempt < 3 else { break }
                            try? await Task.sleep(for: .seconds(Double(attempt + 1) * 10))
                        }
                    }
                    if !succeeded { break }
                    if nextPage % 5 == 0 {
                        paginationLogger.notice("Synchro de fond : page \(nextPage, privacy: .public)/\(self.totalPages, privacy: .public)")
                    }
                }
                guard !Task.isCancelled else { return }
                self.flushPendingPages()
                self.backgroundSyncTask = nil
                // Élagage seulement après un parcours complet et réussi : après une erreur ou un
                // changement de dossier, la liste des exemplaires renvoyés serait incomplète.
                // Dossier ou compte changé en route : la liste affichée n'est plus celle de ce
                // dossier, elle ne doit pas remplacer son cache.
                guard self.isCurrent(context) else { return }
                if reachedLastPage {
                    // Écart entre le total Discogs et les exemplaires distincts reçus : doublons
                    // d'une page à l'autre (ordre instable du tri), fantômes écartés, ou
                    // exemplaire illisible (voir `CollectionDecoding`).
                    paginationLogger.notice("Parcours complet : \(self.serverInstanceIds.count, privacy: .public) exemplaires distincts sur \(self.announcedTotal, privacy: .public) annoncés (\(self.receivedCount, privacy: .public) reçus, \(self.phantomCount, privacy: .public) fantômes écartés)")
                    let serverIds = self.serverInstanceIds
                    let items = self.currentItems()
                    if items.contains(where: { !serverIds.contains($0.instanceId) }) {
                        self.applyItems(items.filter { serverIds.contains($0.instanceId) })
                    }
                }
                // Parcours interrompu : le cache garde les pages déjà reçues mais n'est pas déclaré
                // frais, pour que le prochain passage (Collection, Stats) relance le chargement.
                guard reachedLastPage else {
                    paginationLogger.error("Synchro interrompue à la page \(self.currentPage, privacy: .public)/\(self.totalPages, privacy: .public)")
                    return
                }
                await localStore.syncCollectionFolder(username: context.username, folderId: context.folderId, fullItems: self.currentItems())
            }
        }
    }
}
