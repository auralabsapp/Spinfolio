import Foundation
import Observation
import SwiftUI
import OSLog

private let collectionDebugLogger = Logger(subsystem: AppInfo.logSubsystem, category: "LibrarySyncDebug")

@Observable
@MainActor
final class CollectionViewModel {
    /// Singleton plutôt qu'une instance propre à `CollectionView` : ses observateurs
    /// NotificationCenter (ajout/retrait déclenchés depuis une fiche release) doivent exister dès
    /// le lancement de l'app, pas seulement à partir de la première visite de l'onglet Collection —
    /// sinon toute notification envoyée avant cette première visite est perdue (NotificationCenter
    /// ne rejoue jamais les notifications manquées), et la liste ne reflète pas l'ajout/retrait.
    static let shared = CollectionViewModel()

    private(set) var folders: [CollectionFolder] = []
    private(set) var selectedFolderId: Int?
    private(set) var fields: [CollectionField] = []
    /// Le tri/regroupement (`localizedStandardCompare` sur toute la liste) est coûteux à refaire
    /// à chaque lecture : `sections` est donc recalculé une seule fois par changement réel via
    /// `display.recomputeSections()`, plutôt que d'être une computed property réévaluée à chaque accès
    /// (elle est lue plusieurs fois par passage de vue : la liste elle-même, `indexEntries`...).
    private(set) var items: [CollectionItem] = [] {
        didSet {
            display.itemsChanged()
            display.resolveMissingMastersIfNeeded()
        }
    }
    private(set) var isLoading = false
    /// Vrai tant que le premier chargement du compte n'est pas terminé (et après `reset()`). Sans
    /// lui, la vue montrait d'abord l'état « Collection vide » (un `ScrollView`) le temps de lire le
    /// cache, puis basculait sur la `List` du squelette : la barre de navigation restait attachée à
    /// la première vue de défilement et le grand titre ne se réduisait plus au défilement (entrée en
    /// démo, connexion).
    private(set) var isAwaitingFirstLoad = true
    private(set) var errorMessage: String?
    /// Résultat d'une action de l'utilisateur (retrait, déplacement…) à lui signaler, affiché en
    /// alerte par `CollectionView`. Distinct de `errorMessage`, qui n'est visible que lorsque la
    /// liste est vide (échec de chargement) : les messages d'action y restaient invisibles.
    var actionMessage: String?
    private(set) var isOfflineAndStale: Bool = false

    /// Recherche, tri, filtres, sections et valeurs dérivées affichés (voir `CollectionDisplayState`).
    let display = CollectionDisplayState()

    /// Apparition de l'onglet : rechargement depuis Discogs au plus toutes les 5 min (voir
    /// `ReloadThrottle`) ; le cache déjà affiché suffit entre-temps.
    func loadOnAppear() async {
        guard let username = authManager.username else { return }
        guard items.isEmpty || reloadThrottle.shouldReload(for: username) else { return }
        await loadFoldersAndItems()
    }

    /// Vide entièrement l'état en mémoire : appelé à la déconnexion pour qu'aucune donnée du
    /// compte Discogs qui vient de se déconnecter (items, dossiers, filtres) ne reste affichée
    /// ni ne se mélange avec celle du compte suivant lors du prochain chargement (`items` est
    /// fusionné et non remplacé par `loadFoldersAndItems`/`loadFirstPage`, voir leurs commentaires).
    func reset() {
        reloadThrottle.reset()
        // Sans cette annulation, la synchro de fond du compte précédent continuait de charger
        // ses pages (avec ses identifiants) et pouvait les mélanger aux items du compte suivant.
        pagination.reset()
        items = []
        folders = []
        selectedFolderId = nil
        fields = []
        errorMessage = nil
        isOfflineAndStale = false
        isLoading = false
        isAwaitingFirstLoad = true
        display.resetFilters()
    }

    /// Liste ordonnée de tous les formats rencontrés dans le dossier courant (ex: "Vinyl", "CD", etc.)
    var availableFormats: [String] { items.availableLibraryFormats }

    private let authManager = DiscogsAuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let localStore = LocalDataStore.shared
    private let syncQueue = OfflineSyncQueue.shared
    /// Dernier rechargement depuis Discogs (voir `loadOnAppear`).
    @ObservationIgnored private var reloadThrottle = ReloadThrottle()

    init() {
        connectPagination()
        connectDisplay()
        addLibraryObserver(for: .collectionItemAdded, payloadKey: "item") { [weak self] (item: CollectionItem) in
            self?.handleCollectionItemAdded(item)
        }

        addCollectionRemovalObserver { [weak self] releaseId, instanceId in
            self?.handleCollectionItemRemoved(releaseId: releaseId, instanceId: instanceId)
        }
        addCollectionReplacementObserver { [weak self] oldInstanceId, newItem in
            self?.handleCollectionInstanceReplaced(oldInstanceId: oldInstanceId, newItem: newItem)
        }

        // Action hors ligne refusée par Discogs : l'affichage optimiste est faux, on recharge.
        addOfflineActionDroppedObserver { [weak self] type in
            guard let self, type != .addToWantlist, type != .removeFromWantlist else { return }
            Task { await self.refresh() }
        }
    }

    private func handleCollectionInstanceReplaced(oldInstanceId: Int, newItem: CollectionItem) {
        // Voir `handleCollectionItemAdded` : protège le nouvel exemplaire de l'élagage en fin de parcours.
        pagination.noteLocallyAdded(instanceId: newItem.instanceId)
        if let index = items.firstIndex(where: { $0.id == oldInstanceId }) {
            items[index] = newItem
        }
    }

    private func handleCollectionItemAdded(_ item: CollectionItem) {
        collectionDebugLogger.debug("RECV collectionItemAdded release=\(item.releaseId, privacy: .private(mask: .hash)) instance=\(item.instanceId, privacy: .private(mask: .hash)) folder=\(item.folderId) selectedFolderId=\(self.selectedFolderId ?? -999) itemsCountBefore=\(self.items.count)")
        // Ajouté localement pendant un parcours des pages : Discogs peut ne pas le renvoyer dans
        // ce parcours (page déjà chargée), il ne doit donc pas être élagué à la fin.
        pagination.noteLocallyAdded(instanceId: item.instanceId)
        let change = CollectionLocalChanges.afterExternalAdd(of: item, items: items, folders: folders, selectedFolderId: selectedFolderId)
        if let newItems = change.items {
            withAnimation(.optimisticToggle) { items = newItems }
        }
        folders = change.folders
    }

    private func handleCollectionItemRemoved(releaseId: Int, instanceId: Int?) {
        display.animatesNextSectionsUpdate = true
        collectionDebugLogger.debug("RECV collectionItemRemoved release=\(releaseId, privacy: .private(mask: .hash)) instance=\(instanceId ?? -1, privacy: .private(mask: .hash)) itemsCountBefore=\(self.items.count)")
        let change = CollectionLocalChanges.afterExternalRemoval(
            releaseId: releaseId, instanceId: instanceId, items: items, folders: folders, selectedFolderId: selectedFolderId
        )
        withAnimation(.optimisticToggle) { items = change.items }
        folders = change.folders
    }

    /// Pagination paresseuse et synchro de fond des pages (voir `CollectionPagination`).
    private let pagination = CollectionPagination()

    /// Relie l'affichage à la liste et aux préférences du compte (appelé depuis `init`).
    private func connectDisplay() {
        display.currentItems = { [unowned self] in items }
        display.onSortChanged = { [unowned self] criterionChanged in
            if let username = authManager.username {
                if criterionChanged {
                    CollectionPreferencesStore.setSortOption(display.sortOption, for: username)
                }
                CollectionPreferencesStore.setSortAscending(display.sortAscending, for: username)
            }
            if criterionChanged, display.sortOption == .shelf {
                display.resolveMissingMastersIfNeeded()
            }
            guard let folderId = selectedFolderId else { return }
            Task { await loadFirstPage(folderId: folderId) }
        }
    }

    /// Relie la pagination à la liste affichée (appelé depuis `init`).
    private func connectPagination() {
        pagination.currentItems = { [unowned self] in items }
        pagination.applyItems = { [unowned self] in items = $0 }
        pagination.isCurrent = { [unowned self] context in
            selectedFolderId == context.folderId && authManager.username == context.username
        }
        pagination.sortParameters = { [unowned self] in
            (display.sortOption.apiSortValue, display.sortOption.apiSortOrder(ascending: display.sortAscending))
        }
    }

    func loadFoldersAndItems(isSilent: Bool = false) async {
        guard let username = authManager.username else { return }
        defer { isAwaitingFirstLoad = false }

        pagination.cancelBackgroundSync()

        restoreSavedSort(username: username)

        // Récupération du dernier dossier consulté mémorisé
        let preferredFolderId = selectedFolderId ?? CollectionPreferencesStore.lastConsultedFolderId(for: username) ?? DiscogsConstants.allFolderId
        selectedFolderId = preferredFolderId

        // Chargement immédiat depuis le cache SwiftData pour un affichage instantané et correctement classé
        await loadFromLocalStore(username: username, folderId: preferredFolderId)

        // Si l'appareil est hors ligne : on conserve l'affichage du cache local
        if !networkMonitor.isConnected {
            return
        }
        reloadThrottle.recordReload(for: username)

        guard let credentials = authManager.credentials else { return }
        if !isSilent && items.isEmpty {
            isLoading = true
        }
        errorMessage = nil

        do {
            async let foldersRequest = DiscogsAPIClient.shared.collectionFolders(username: username, credentials: credentials)
            async let fieldsRequest = CollectionFieldsService.fields(username: username, credentials: credentials)
            let foldersResponse = try await foldersRequest
            folders = foldersResponse.folders
            fields = await fieldsRequest

            // Sauvegarde des dossiers dans SwiftData
            localStore.saveFolders(folders, username: username)
            let validFolderIds = Set(folders.map(\.id))
            CollectionPreferencesStore.resetDefaultAddFolderIfMissing(validFolderIds: validFolderIds, for: username)
            syncQueue.retargetActionsForDeletedFolders(validFolderIds: validFolderIds, username: username)

            // Validation du dossier sélectionné
            let validFolderId = folders.contains(where: { $0.id == preferredFolderId })
                ? preferredFolderId
                : folders.first?.id ?? DiscogsConstants.allFolderId
            rememberSelectedFolder(validFolderId, username: username)

        } catch {
            // Repli gracieux sur le cache local
            await loadFromLocalStore(username: username, folderId: selectedFolderId ?? preferredFolderId)
            if items.isEmpty && !error.isCancellation {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            return
        }
        await loadFirstPageFromDiscogs(username: username, folderId: selectedFolderId ?? preferredFolderId, credentials: credentials)
    }

    private func loadFromLocalStore(username: String, folderId: Int? = nil) async {
        let cachedFolders = localStore.getFolders(username: username)
        if !cachedFolders.isEmpty {
            self.folders = cachedFolders
        }
        restoreSavedSort(username: username)

        let preferredFolderId = folderId ?? selectedFolderId ?? CollectionPreferencesStore.lastConsultedFolderId(for: username)
        let targetFolderId = folderId
            ?? preferredFolderId.flatMap { id in folders.contains { $0.id == id } ? id : nil }
            ?? folders.first?.id ?? DiscogsConstants.allFolderId
        rememberSelectedFolder(targetFolderId, username: username)

        localStore.cleanupPhantomCollectionEntries(username: username)
        let cachedItems = await localStore.getCollectionItems(username: username, folderId: targetFolderId)
            .filter { $0.instanceId > 0 && $0.instanceId != $0.releaseId }
        self.items = cachedItems
        self.isOfflineAndStale = localStore.isCollectionStale(username: username, folderId: targetFolderId)
        self.isLoading = false
        localStore.updateWidgetSnapshotIfBehind(cachedItems)
    }

    /// Dès que la connexion est rétablie et que le TTL est dépassé, lance un rafraîchissement silencieux.
    func silentRefreshIfNeeded() async {
        guard let username = authManager.username, let folderId = selectedFolderId else { return }
        if networkMonitor.isConnected && localStore.isCollectionStale(username: username, folderId: folderId) {
            await loadFoldersAndItems(isSilent: true)
        }
    }

    /// Rafraîchissement manuel déclenché par l'utilisateur via le pull-down (pull-to-refresh).
    func refresh() async {
        await loadFoldersAndItems(isSilent: true)
    }

    func selectFolder(_ folderId: Int) async {
        pagination.cancelBackgroundSync()

        selectedFolderId = folderId
        if let username = authManager.username {
            rememberSelectedFolder(folderId, username: username)
            // Charge immédiatement le cache local du nouveau dossier pour éviter toute incohérence d'affichage
            await loadFromLocalStore(username: username, folderId: folderId)
        }
        if networkMonitor.isConnected {
            await loadFirstPage(folderId: folderId)
        }
    }

    /// Réagit à une modification externe des préférences (ex: restauration de sauvegarde).
    func handlePreferencesChanged() async {
        guard let username = authManager.username else { return }
        restoreSavedSort(username: username)

        let savedFolderId = CollectionPreferencesStore.lastConsultedFolderId(for: username)
        if let savedFolderId, savedFolderId != selectedFolderId {
            await selectFolder(savedFolderId)
        } else if let folderId = selectedFolderId {
            if networkMonitor.isConnected {
                await loadFirstPage(folderId: folderId)
            } else {
                await loadFromLocalStore(username: username, folderId: folderId)
            }
        }
    }

    /// Déclenché depuis la ligne affichée près de la fin de la liste : par sécurité si la
    /// synchronisation de fond n'a pas encore rattrapé le défilement (ne double-charge pas,
    /// `startBackgroundSync` s'en charge déjà dans l'immense majorité des cas).
    func loadMoreIfNeeded(current item: CollectionItem) async {
        guard networkMonitor.isConnected else { return }
        guard let (username, credentials) = authManager.session,
              let folderId = selectedFolderId else { return }
        guard let last = items.last, last.id == item.id, pagination.hasMorePages, !pagination.isSyncingInBackground else { return }
        do {
            let context = CollectionPagination.Context(username: username, folderId: folderId, credentials: credentials)
            try await pagination.fetchPage(pagination.currentPage + 1, context: context, append: true)
        } catch {
            // On garde les éléments déjà affichés
        }
    }

    private func loadFirstPage(folderId: Int) async {
        guard let username = authManager.username else { return }
        pagination.cancelBackgroundSync()

        if !networkMonitor.isConnected {
            await loadFromLocalStore(username: username, folderId: folderId)
            return
        }
        guard let credentials = authManager.credentials else { return }
        if items.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        await loadFirstPageFromDiscogs(username: username, folderId: folderId, credentials: credentials)
    }

    /// Page 1 puis synchro de fond des suivantes ; repli sur le cache local en cas d'échec.
    /// `append: true` : préserve le plein instantané déjà affiché par `loadFromLocalStore` (ou par
    /// un tri/dossier précédent) plutôt que de l'écraser par la seule page 1 — sans ça, la liste et
    /// la barre de navigation rapide (A-Z) se réduisaient brutalement à la première page avant de
    /// regrossir progressivement, surtout visible en tri alphabétique.
    private func loadFirstPageFromDiscogs(username: String, folderId: Int, credentials: DiscogsCredentials) async {
        defer { isLoading = false }
        do {
            let context = CollectionPagination.Context(username: username, folderId: folderId, credentials: credentials)
            try await pagination.fetchPage(1, context: context, append: true)
            isOfflineAndStale = false
            pagination.startBackgroundSync(context: context)
        } catch {
            await loadFromLocalStore(username: username, folderId: folderId)
            if items.isEmpty && !error.isCancellation {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Critère et sens de tri mémorisés pour ce compte. Le sens est écrit sans repasser par
    /// `sortAscending`, qui relancerait un chargement.
    private func restoreSavedSort(username: String) {
        if let savedSort = CollectionPreferencesStore.sortOption(for: username) {
            display.sortOption = savedSort
        }
        if let savedAscending = CollectionPreferencesStore.sortAscending(for: username) {
            display.restoreSortAscending(savedAscending)
        }
    }

    /// Dossier affiché, mémorisé (avec son nom) comme dernier dossier consulté du compte.
    private func rememberSelectedFolder(_ folderId: Int, username: String) {
        selectedFolderId = folderId
        CollectionPreferencesStore.setLastConsultedFolderId(folderId, for: username)
        if let folderName = folders.first(where: { $0.id == folderId })?.name {
            CollectionPreferencesStore.setLastConsultedFolderName(folderName, for: username)
        }
    }

    /// Déplace plusieurs exemplaires vers un même dossier (édition en lot). Discogs n'expose
    /// aucun endpoint de déplacement groupé : chaque exemplaire passe donc par `moveInstance`,
    /// qui gère déjà individuellement l'état optimiste, les compteurs de dossiers et la file
    /// hors ligne.
    func moveInstances(_ items: [CollectionItem], toFolderId: Int) async {
        for item in items {
            await moveInstance(item, toFolderId: toFolderId)
        }
    }

    /// Supprime plusieurs exemplaires de la collection (édition en lot). Tous disparaissent de la
    /// liste d'un seul coup (une seule mise à jour des sections), puis Discogs est mis à jour un
    /// exemplaire après l'autre en arrière-plan : retirer d'abord un exemplaire, attendre le réseau,
    /// puis passer au suivant les faisait disparaître un par un.
    func removeInstances(_ targets: [CollectionItem]) async {
        guard !targets.isEmpty, let username = beginChange(demoMessage: AppMessages.demoRemovalBlocked) else { return }

        let targetIds = Set(targets.map(\.id))
        display.animatesNextSectionsUpdate = true
        items.removeAll { targetIds.contains($0.id) }
        for item in targets {
            removeFromLocalState(item, username: username)
        }
        for item in targets {
            // Compte changé pendant la boucle : ne pas envoyer la suite avec les identifiants d'un autre.
            guard authManager.username == username else { return }
            await sendRemoval(item, username: username)
        }
    }

    func remove(_ item: CollectionItem) async {
        await removeInstances([item])
    }

    /// Garde commune aux retraits et déplacements : mode démo, hors ligne avec données périmées.
    /// Renvoie le nom d'utilisateur du compte actif si la modification peut avoir lieu.
    private func beginChange(demoMessage: String) -> String? {
        if DemoMode.isActive {
            actionMessage = demoMessage
            return nil
        }
        guard let username = authManager.username else { return nil }

        // Si l'appareil est hors ligne et que les données ont plus de 6 heures (Option B) :
        // maintien de l'affichage en lecture seule et blocage des modifications
        if !networkMonitor.isConnected && isOfflineAndStale {
            actionMessage = AppMessages.offlineStaleModificationBlocked
            return nil
        }
        return username
    }

    /// Retrait d'un exemplaire du cache SwiftData et des états partagés ; `items` est déjà à jour.
    private func removeFromLocalState(_ item: CollectionItem, username: String) {
        localStore.removeCollectionItemFromFolderAndAll(item, username: username)

        let remainingCopies = items.filter { $0.releaseId == item.releaseId }
        if remainingCopies.isEmpty {
            localStore.removeCollectionItems(username: username, releaseId: item.releaseId)
        }
        LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: item.releaseId, instanceId: item.instanceId)
    }

    /// Répercute un retrait déjà affiché sur Discogs (voir `DiscogsWriteService`) ; sur un refus
    /// définitif, l'exemplaire est réaffiché plutôt que de laisser la file échouer trois fois.
    private func sendRemoval(_ item: CollectionItem, username: String) async {
        let outcome = await DiscogsWriteService.removeInstance(item, username: username)
        switch outcome {
        case .queuedOffline:
            LibraryMembershipStore.shared.noteQueuedOffline(.collectionRemoved)
        case .refused:
            if !items.contains(where: { $0.id == item.id }) {
                withAnimation(.optimisticToggle) { items.append(item) }
            }
            await localStore.saveCollectionItemInFolderAndAll(item, username: username)
            LibraryMembershipStore.shared.markInCollection(item.releaseId)
            actionMessage = AppMessages.removalFailed
        case .queuedAfterFailure, .done:
            actionMessage = outcome.failureQueuedMessage ?? actionMessage
        }
    }

    /// Déplace un exemplaire vers un autre dossier Discogs, en répercutant les compteurs des
    /// dossiers concernés. Hors ligne, mis en file pour une synchro différée (même mécanique
    /// que `remove`).
    func moveInstance(_ item: CollectionItem, toFolderId: Int) async {
        guard item.folderId != toFolderId,
              let username = beginChange(demoMessage: AppMessages.demoModificationBlocked) else { return }

        let movedItem = item.moved(toFolderId: toFolderId)
        applyMove(from: item, to: movedItem)
        await localStore.replaceCollectionItemInCache(item, with: movedItem, username: username)

        let outcome = await DiscogsWriteService.moveInstance(item, toFolderId: toFolderId, username: username)
        if let message = outcome.failureQueuedMessage {
            actionMessage = message
        } else if outcome == .refused {
            // Refus définitif : on annule le déplacement optimiste (exemplaire, compteurs des
            // dossiers, cache) au lieu de laisser la file échouer trois fois.
            applyMove(from: movedItem, to: item, reverting: true)
            await localStore.replaceCollectionItemInCache(movedItem, with: item, username: username)
            actionMessage = AppMessages.moveFailed
        }
    }

    /// Mise à jour optimiste d'un déplacement (ou son annulation) : liste et compteurs des dossiers.
    private func applyMove(from source: CollectionItem, to destination: CollectionItem, reverting: Bool = false) {
        withAnimation(.optimisticToggle) {
            items = reverting
                ? CollectionLocalChanges.itemsAfterRevertingMove(items, original: destination, moved: source, selectedFolderId: selectedFolderId)
                : CollectionLocalChanges.itemsAfterMove(items, original: source, moved: destination, selectedFolderId: selectedFolderId)
            folders = CollectionLocalChanges.adjustingCounts(of: folders, by: [source.folderId: -1, destination.folderId: 1])
        }
    }

    /// Reflète localement une note/des champs personnalisés déjà enregistrés par
    /// `CollectionItemEditSheet` (qui gère lui-même les appels réseau).
    func applyEditedValues(for item: CollectionItem, rating: Int, notes: [CollectionFieldValue]) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].rating = rating
        items[index].notes = notes
        guard let username = authManager.username else { return }
        let updated = items[index]
        await localStore.saveCollectionItemInFolderAndAll(updated, username: username)
    }
}
