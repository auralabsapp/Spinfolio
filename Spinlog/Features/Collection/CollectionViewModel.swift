import Foundation
import Observation
import SwiftUI
import OSLog

private let collectionDebugLogger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "LibrarySyncDebug")

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
    /// `recomputeSections()`, plutôt que d'être une computed property réévaluée à chaque accès
    /// (elle est lue plusieurs fois par passage de vue : la liste elle-même, `indexEntries`...).
    private(set) var items: [CollectionItem] = [] {
        didSet {
            recomputeSections()
            recomputeCopiesIndex()
            resolveMissingMastersIfNeeded()
        }
    }
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Résultat d'une action de l'utilisateur (retrait, déplacement…) à lui signaler, affiché en
    /// alerte par `CollectionView`. Distinct de `errorMessage`, qui n'est visible que lorsque la
    /// liste est vide (échec de chargement) : les messages d'action y restaient invisibles.
    var actionMessage: String?
    private(set) var isOfflineAndStale: Bool = false

    var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            recomputeSections()
        }
    }
    var sortOption: CollectionSortOption = .artist {
        didSet {
            guard oldValue != sortOption else { return }
            // Réinitialise le sens au défaut du nouveau critère sans repasser par le didSet
            // public de `sortAscending` (qui déclencherait un second rechargement réseau en
            // plus de celui déjà lancé plus bas pour ce changement de critère).
            sortAscendingStorage = sortOption.defaultAscending
            recomputeSections()
            if let username = authManager.username {
                CollectionPreferencesStore.setSortOption(sortOption, for: username)
                CollectionPreferencesStore.setSortAscending(sortAscendingStorage, for: username)
            }
            if sortOption == .shelf {
                resolveMissingMastersIfNeeded()
            }
            guard let folderId = selectedFolderId else { return }
            Task { await loadFirstPage(folderId: folderId) }
        }
    }

    private var sortAscendingStorage: Bool = CollectionSortOption.artist.defaultAscending

    /// Sens du tri courant (croissant/décroissant). Se réinitialise au défaut du critère choisi
    /// à chaque changement de `sortOption` ; peut ensuite être basculé indépendamment.
    var sortAscending: Bool {
        get { sortAscendingStorage }
        set {
            guard sortAscendingStorage != newValue else { return }
            sortAscendingStorage = newValue
            recomputeSections()
            if let username = authManager.username {
                CollectionPreferencesStore.setSortAscending(sortAscendingStorage, for: username)
            }
            guard let folderId = selectedFolderId else { return }
            Task { await loadFirstPage(folderId: folderId) }
        }
    }

    /// Sémantique ET : un exemplaire n'est affiché que s'il porte tous les tags sélectionnés.
    /// Les filtres sont volatils (valables pour la session courante) : aucun filtre n'est appliqué au démarrage.
    var selectedTags: Set<String> = [] {
        didSet {
            guard oldValue != selectedTags else { return }
            recomputeSections()
        }
    }

    var selectedFormat: String? = nil {
        didSet {
            guard oldValue != selectedFormat else { return }
            recomputeSections()
        }
    }

    var hasActiveFilters: Bool {
        !selectedTags.isEmpty ||
        (selectedFormat != nil && !selectedFormat!.isEmpty)
    }

    func clearFilters() {
        selectedTags = []
        selectedFormat = nil
    }

    func toggleTagFilter(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    /// Vide entièrement l'état en mémoire : appelé à la déconnexion pour qu'aucune donnée du
    /// compte Discogs qui vient de se déconnecter (items, dossiers, filtres) ne reste affichée
    /// ni ne se mélange avec celle du compte suivant lors du prochain chargement (`items` est
    /// fusionné et non remplacé par `loadFoldersAndItems`/`loadFirstPage`, voir leurs commentaires).
    func reset() {
        // Sans cette annulation, la synchro de fond du compte précédent continuait de charger
        // ses pages (avec ses identifiants) et pouvait les mélanger aux items du compte suivant.
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
        serverInstanceIdsInCurrentPass = []
        items = []
        folders = []
        selectedFolderId = nil
        fields = []
        currentPage = 1
        totalPages = 1
        errorMessage = nil
        isOfflineAndStale = false
        isLoading = false
        searchText = ""
        selectedTags = []
        selectedFormat = nil
    }

    /// Liste ordonnée de tous les formats rencontrés dans le dossier courant (ex: "Vinyl", "CD", etc.)
    var availableFormats: [String] { items.availableLibraryFormats }

    private let authManager = DiscogsAuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let localStore = LocalDataStore.shared
    private let syncQueue = OfflineSyncQueue.shared

    init() {
        NotificationCenter.default.addObserver(
            forName: .collectionItemAdded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let item = notification.userInfo?["item"] as? CollectionItem else { return }
                self.handleCollectionItemAdded(item)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .collectionItemRemoved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let releaseId = notification.userInfo?["releaseId"] as? Int else { return }
                let instanceId = notification.userInfo?["instanceId"] as? Int
                self.handleCollectionItemRemoved(releaseId: releaseId, instanceId: instanceId)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .collectionInstanceReplaced,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let oldId = notification.userInfo?["oldInstanceId"] as? Int,
                      let newItem = notification.userInfo?["newItem"] as? CollectionItem else { return }
                self.handleCollectionInstanceReplaced(oldInstanceId: oldId, newItem: newItem)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .shelfPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.sortOption == .shelf || self.sortOption == .artist {
                    self.recomputeSections()
                    if self.sortOption == .shelf && ShelfPreferencesStore.shared.sortStrategy.usesMasterYear {
                        self.resolveMissingMastersIfNeeded()
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .masterYearResolved,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.sortOption == .shelf && ShelfPreferencesStore.shared.sortStrategy.usesMasterYear {
                    self.recomputeSections()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .tagsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recomputeSections()
            }
        }
    }

    private func resolveMissingMastersIfNeeded() {
        guard sortOption == .shelf, ShelfPreferencesStore.shared.sortStrategy.usesMasterYear else { return }
        let missing = items.compactMap { item -> Int? in
            guard let masterId = item.basicInformation.masterId, masterId > 0 else { return nil }
            // `isMasterResolved` et non `getMasterYear == nil` : un master sans année sur Discogs
            // est enregistré à 0 (résolu), mais `getMasterYear` renvoie `nil` pour 0 — il était
            // donc redemandé à Discogs indéfiniment.
            return localStore.isMasterResolved(masterId) ? nil : masterId
        }
        let uniqueMissing = Array(Set(missing))
        guard !uniqueMissing.isEmpty else { return }
        Task {
            // La collection réagit déjà à `.masterYearResolved` : aucun suivi de progression ici.
            await MasterResolutionService.shared.resolveMasters(missingMasterIds: uniqueMissing, subscriberKey: "collection") { _, _, _, _ in }
        }
    }

    private func handleCollectionInstanceReplaced(oldInstanceId: Int, newItem: CollectionItem) {
        // Voir `handleCollectionItemAdded` : protège le nouvel exemplaire de l'élagage en fin de parcours.
        serverInstanceIdsInCurrentPass.insert(newItem.instanceId)
        if let index = items.firstIndex(where: { $0.id == oldInstanceId }) {
            items[index] = newItem
            recomputeSections()
        }
    }

    private func handleCollectionItemAdded(_ item: CollectionItem) {
        collectionDebugLogger.log("RECV collectionItemAdded release=\(item.releaseId) instance=\(item.instanceId) folder=\(item.folderId) selectedFolderId=\(self.selectedFolderId ?? -999) itemsCountBefore=\(self.items.count)")
        // Ajouté localement pendant un parcours des pages : Discogs peut ne pas le renvoyer dans
        // ce parcours (page déjà chargée), il ne doit donc pas être élagué à la fin.
        serverInstanceIdsInCurrentPass.insert(item.instanceId)
        if selectedFolderId == nil || selectedFolderId == DiscogsConstants.allFolderId || selectedFolderId == item.folderId {
            if !items.contains(where: { $0.id == item.id }) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    items.insert(item, at: 0)
                }
            }
        }
        folders = folders.map { folder in
            if folder.id == item.folderId || folder.id == DiscogsConstants.allFolderId {
                return CollectionFolder(id: folder.id, name: folder.name, count: folder.count + 1, resourceURL: folder.resourceURL)
            }
            return folder
        }
        recomputeSections()
    }

    private func handleCollectionItemRemoved(releaseId: Int, instanceId: Int?) {
        collectionDebugLogger.log("RECV collectionItemRemoved release=\(releaseId) instance=\(instanceId ?? -1) itemsCountBefore=\(self.items.count)")
        withAnimation(.easeInOut(duration: 0.2)) {
            if let instanceId {
                items.removeAll { $0.instanceId == instanceId }
            } else {
                items.removeAll { $0.releaseId == releaseId }
            }
        }
        folders = folders.map { folder in
            if folder.id == selectedFolderId || folder.id == DiscogsConstants.allFolderId {
                return CollectionFolder(id: folder.id, name: folder.name, count: max(0, folder.count - 1), resourceURL: folder.resourceURL)
            }
            return folder
        }
        recomputeSections()
    }

    /// Index `releaseId -> exemplaires` recalculé une seule fois par changement réel de `items`
    /// (voir `recomputeSections()` juste au-dessus pour la même logique appliquée au tri), plutôt
    /// que refiltrer toute la collection à chaque ligne affichée dans `copyBadge(for:)`.
    private var copiesByReleaseId: [Int: [CollectionItem]] = [:]

    private func recomputeCopiesIndex() {
        copiesByReleaseId = Dictionary(grouping: items, by: { $0.releaseId })
    }

    /// Renvoie un badge si l'utilisateur possède plusieurs exemplaires de ce disque
    func copyBadge(for item: CollectionItem) -> String? {
        guard let copies = copiesByReleaseId[item.releaseId], copies.count > 1 else { return nil }
        let index = (copies.firstIndex(where: { $0.id == item.id }) ?? 0) + 1
        return "Ex. \(index)/\(copies.count)"
    }

    /// Même résultat que `copyBadge(for:)` appelé item par item, mais en une seule lecture de
    /// `copiesByReleaseId` : `copiesByReleaseId` est un dictionnaire, donc une lecture de l'un de
    /// ses éléments crée une dépendance Observation sur sa valeur ENTIÈRE. Appeler `copyBadge(for:)`
    /// depuis la closure de chaque ligne visible (comme avant) en faisait donc un observateur
    /// indépendant de tout le dictionnaire — à chaque page reçue pendant la synchro de fond
    /// (qui réassigne `copiesByReleaseId` via `recomputeCopiesIndex()`), SwiftUI réinvalidait
    /// chaque ligne séparément au lieu d'une seule fois pour toute la vue-liste. À appeler une
    /// fois par passage de rendu (voir `CollectionView.collectionViewList`/`collectionViewCarousel`),
    /// puis indexer le dictionnaire résultat (une valeur captée, pas une lecture Observation) dans
    /// chaque ligne.
    func copyBadges(for items: [CollectionItem]) -> [Int: String] {
        var result: [Int: String] = [:]
        for item in items {
            if let badge = copyBadge(for: item) {
                result[item.id] = badge
            }
        }
        return result
    }

    /// Pagination paresseuse : la 1re page s'affiche tout de suite (jamais toute la collection
    /// d'un coup), puis `backgroundSyncTask` continue de charger les pages suivantes en tâche
    /// de fond — c'est la seconde option explicitement permise par l'API Discogs pour les
    /// grosses collections, et c'est nécessaire pour que la barre de navigation rapide (lettres/
    /// années) reflète tout le dossier plutôt que seulement ce qui a déjà défilé à l'écran.
    private var currentPage = 1
    private var totalPages = 1
    private var backgroundSyncTask: Task<Void, Never>?
    /// Exemplaires effectivement renvoyés par Discogs depuis la dernière page 1 chargée (plus
    /// ceux ajoutés localement entre-temps). `items` part du cache et ne fait qu'accumuler les
    /// pages fraîches, pour éviter que la liste se réduise à la seule page 1 : une fois toutes
    /// les pages parcourues, ce qui n'y figure pas a été supprimé ou déplacé ailleurs (ex: depuis
    /// discogs.com) et est retiré — sans quoi ces disques restaient affichés indéfiniment.
    private var serverInstanceIdsInCurrentPass: Set<Int> = []

    /// Éléments filtrés par la recherche et les filtres actifs, regroupés par section dans un ordre
    /// rigoureusement déterministe (même en cache ou hors-ligne). Recalculé par
    /// `recomputeSections()` uniquement quand `items`/tri/filtres changent réellement.
    private(set) var sections: [(key: String, items: [CollectionItem])] = []
    /// Vrai pendant le calcul détaché des sections (voir `recomputeSections`) : `sections` est
    /// alors vide ou périmé sans que la recherche soit en cause. Au lancement, la vue affiche un
    /// indicateur de chargement plutôt que « Aucun résultat » le temps du premier tri.
    private(set) var isComputingSections = false
    /// Stockées comme propriétés `@Observable` ci-dessus (pas déléguées au moteur) pour que
    /// SwiftUI soit bien invalidé à chaque mise à jour — voir le commentaire sur
    /// `LibrarySectionsEngine`.
    private let sectionsEngine = LibrarySectionsEngine<CollectionItem>()

    /// Tri + regroupement de la collection, délégués à `LibrarySectionsEngine` (partagé avec
    /// `WantlistViewModel`). Pendant la synchro de pages en arrière-plan juste après le lancement
    /// (`startBackgroundSync`), ce recalcul se redéclenchait à chaque page reçue — ~une fois par
    /// seconde, au rythme du débit imposé par l'API Discogs — pour un coût mesuré de 300-400ms à
    /// chaque fois, provoquant des saccades si l'utilisateur faisait défiler la liste pendant
    /// cette fenêtre ; d'où le calcul détaché du moteur. Le tri `.shelf` capture son
    /// `ShelfSortContext` une seule fois en amont (voir `LibrarySectionsEngine.recompute`) et peut
    /// donc lui aussi être détaché ; seul le filtrage par tag reste synchrone (lit `TagStore`,
    /// isolé sur l'acteur principal, mais en O(n) donc déjà bon marché).
    private func recomputeSections() {
        sectionsEngine.recompute(
            items: items, sortOption: sortOption, ascending: sortAscending,
            tags: selectedTags, format: selectedFormat, searchText: searchText,
            synchronous: !selectedTags.isEmpty,
            willStartAsync: { [weak self] in self?.isComputingSections = true },
            apply: { [weak self] result in
                self?.sections = result
                self?.isComputingSections = false
            }
        )
    }

    /// Jetons pour la barre de navigation rapide sur le bord droit : lettres pour un tri
    /// alphabétique, années sur 2 chiffres pour un tri par date d'ajout. Chaque jeton est
    /// associé à la clé de la première section correspondante, pour y faire défiler la liste.
    var indexEntries: [(token: String, sectionKey: String)] {
        var seenTokens = Set<String>()
        var result: [(token: String, sectionKey: String)] = []
        for section in sections {
            let token = indexToken(for: section)
            guard !seenTokens.contains(token) else { continue }
            seenTokens.insert(token)
            result.append((token, section.key))
        }
        return result
    }

    /// Jeton (lettre ou année sur 2 chiffres) pour la 1re ligne de l'en-tête d'une section,
    /// cohérent avec le jeton affiché dans la barre de navigation rapide.
    func indexToken(for section: (key: String, items: [CollectionItem])) -> String {
        libraryIndexToken(for: section, sort: sortOption)
    }

    /// Valeur affichée en 2e ligne de l'en-tête (voir `CollectionItem.sectionDisplayTitle`).
    func displayTitle(for section: (key: String, items: [CollectionItem])) -> String {
        section.items.first?.sectionDisplayTitle(for: sortOption) ?? section.key
    }

    /// Artistes nommés par l'en-tête de la section, cliquables (voir `LibrarySectionHeader.artists`).
    func headerArtists(for section: (key: String, items: [CollectionItem])) -> [ReleaseArtist] {
        section.items.first?.sectionHeaderArtists(for: sortOption) ?? []
    }

    func loadFoldersAndItems(isSilent: Bool = false) async {
        guard let username = authManager.username else { return }

        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil

        // Restauration des critères de tri et de filtre mémorisés
        if let savedSort = CollectionPreferencesStore.sortOption(for: username) {
            self.sortOption = savedSort
        }
        if let savedAscending = CollectionPreferencesStore.sortAscending(for: username) {
            self.sortAscendingStorage = savedAscending
        }

        // Récupération du dernier dossier consulté mémorisé
        let preferredFolderId = selectedFolderId ?? CollectionPreferencesStore.lastConsultedFolderId(for: username) ?? DiscogsConstants.allFolderId
        selectedFolderId = preferredFolderId

        // Chargement immédiat depuis le cache SwiftData pour un affichage instantané et correctement classé
        await loadFromLocalStore(username: username, folderId: preferredFolderId)

        // Si l'appareil est hors ligne : on conserve l'affichage du cache local
        if !networkMonitor.isConnected {
            return
        }

        guard let credentials = authManager.credentials else { return }
        if !isSilent && items.isEmpty {
            isLoading = true
        }
        errorMessage = nil

        do {
            async let foldersRequest = DiscogsAPIClient.shared.collectionFolders(username: username, credentials: credentials)
            async let fieldsRequest = ReleaseActions.fetchCollectionFields(username: username, credentials: credentials)
            let foldersResponse = try await foldersRequest
            folders = foldersResponse.folders
            fields = await fieldsRequest

            // Sauvegarde des dossiers dans SwiftData
            localStore.saveFolders(folders, username: username)

            // Validation du dossier sélectionné
            let validFolderId: Int
            if folders.contains(where: { $0.id == preferredFolderId }) {
                validFolderId = preferredFolderId
            } else {
                validFolderId = folders.first?.id ?? DiscogsConstants.allFolderId
            }
            selectedFolderId = validFolderId
            CollectionPreferencesStore.setLastConsultedFolderId(validFolderId, for: username)
            if let folderName = folders.first(where: { $0.id == validFolderId })?.name {
                CollectionPreferencesStore.setLastConsultedFolderName(folderName, for: username)
            }

            // `append: true` : préserve le plein instantané déjà affiché par `loadFromLocalStore`
            // (ou par un tri/dossier précédent) plutôt que de l'écraser par la seule page 1 —
            // sans ça, la liste et la barre de navigation rapide (A-Z) se réduisaient brutalement
            // à la première page avant de regrossir progressivement au fil de `startBackgroundSync`,
            // particulièrement visible en tri alphabétique où la page 1 ne couvre qu'un début d'A-Z.
            try await fetchPage(1, username: username, folderId: validFolderId, credentials: credentials, append: true)
            isOfflineAndStale = false
            startBackgroundSync(username: username, folderId: validFolderId, credentials: credentials)
        } catch {
            // Repli gracieux sur le cache local
            await loadFromLocalStore(username: username, folderId: selectedFolderId ?? preferredFolderId)
            if items.isEmpty && !error.isCancellation {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func loadFromLocalStore(username: String, folderId: Int? = nil) async {
        let cachedFolders = localStore.getFolders(username: username)
        if !cachedFolders.isEmpty {
            self.folders = cachedFolders
        }
        if let savedSort = CollectionPreferencesStore.sortOption(for: username) {
            self.sortOption = savedSort
        }
        if let savedAscending = CollectionPreferencesStore.sortAscending(for: username) {
            self.sortAscendingStorage = savedAscending
        }

        let targetFolderId: Int
        if let folderId {
            targetFolderId = folderId
        } else {
            let preferredFolderId = selectedFolderId ?? CollectionPreferencesStore.lastConsultedFolderId(for: username)
            if let preferredFolderId, folders.contains(where: { $0.id == preferredFolderId }) {
                targetFolderId = preferredFolderId
            } else {
                targetFolderId = folders.first?.id ?? DiscogsConstants.allFolderId
            }
        }
        self.selectedFolderId = targetFolderId
        CollectionPreferencesStore.setLastConsultedFolderId(targetFolderId, for: username)
        if let folderName = folders.first(where: { $0.id == targetFolderId })?.name {
            CollectionPreferencesStore.setLastConsultedFolderName(folderName, for: username)
        }

        localStore.cleanupPhantomCollectionEntries(username: username)
        let cachedItems = await localStore.getCollectionItems(username: username, folderId: targetFolderId)
            .filter { $0.instanceId > 0 && $0.instanceId != $0.releaseId }
        self.items = cachedItems
        self.isOfflineAndStale = localStore.isCollectionStale(username: username, folderId: targetFolderId)
        self.isLoading = false

        // En disques distincts, comme l'instantané du widget (dédoublonné par release) : comparer
        // le nombre d'exemplaires était toujours vrai dès qu'un disque existait en double.
        let currentSnapshotCount = WidgetSnapshotStore.loadCollection().count
        let cachedReleaseCount = Set(cachedItems.map(\.releaseId)).count
        if !cachedItems.isEmpty && (currentSnapshotCount == 0 || cachedReleaseCount > currentSnapshotCount) {
            localStore.updateWidgetSnapshot(cachedItems)
        }
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
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil

        selectedFolderId = folderId
        if let username = authManager.username {
            CollectionPreferencesStore.setLastConsultedFolderId(folderId, for: username)
            if let folderName = folders.first(where: { $0.id == folderId })?.name {
                CollectionPreferencesStore.setLastConsultedFolderName(folderName, for: username)
            }
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
        if let savedSort = CollectionPreferencesStore.sortOption(for: username) {
            self.sortOption = savedSort
        }
        if let savedAscending = CollectionPreferencesStore.sortAscending(for: username) {
            self.sortAscendingStorage = savedAscending
        }

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
        guard let last = items.last, last.id == item.id, currentPage < totalPages, backgroundSyncTask == nil else { return }
        do {
            try await fetchPage(currentPage + 1, username: username, folderId: folderId, credentials: credentials, append: true)
        } catch {
            // On garde les éléments déjà affichés
        }
    }

    private func loadFirstPage(folderId: Int) async {
        guard let username = authManager.username else { return }
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil

        if !networkMonitor.isConnected {
            await loadFromLocalStore(username: username, folderId: folderId)
            return
        }
        guard let credentials = authManager.credentials else { return }
        if items.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        do {
            // Voir `loadFoldersAndItems` : `append: true` évite le même effet de réduction
            // brutale puis regrossissement progressif de la liste et de la barre A-Z.
            try await fetchPage(1, username: username, folderId: folderId, credentials: credentials, append: true)
            isOfflineAndStale = false
            startBackgroundSync(username: username, folderId: folderId, credentials: credentials)
        } catch {
            await loadFromLocalStore(username: username, folderId: folderId)
            if items.isEmpty && !error.isCancellation {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    /// Continue de charger les pages suivantes une par une derrière l'écran (chaque appel
    /// passe par le throttle Discogs), jusqu'à couvrir tout le dossier ou jusqu'à ce qu'un
    /// changement de dossier/tri annule cette tâche pour la remplacer par une nouvelle.
    private func startBackgroundSync(username: String, folderId: Int, credentials: DiscogsCredentials) {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            var reachedLastPage = false
            while !Task.isCancelled {
                guard self.selectedFolderId == folderId else { break }
                let page = self.currentPage
                let total = self.totalPages
                guard page < total else {
                    reachedLastPage = true
                    break
                }
                do {
                    try await self.fetchPage(page + 1, username: username, folderId: folderId, credentials: credentials, append: true)
                } catch {
                    break
                }
            }
            if !Task.isCancelled {
                self.backgroundSyncTask = nil
                // Élagage seulement après un parcours complet et réussi : après une erreur ou un
                // changement de dossier, la liste des exemplaires renvoyés serait incomplète.
                if reachedLastPage, self.selectedFolderId == folderId {
                    let serverIds = self.serverInstanceIdsInCurrentPass
                    if self.items.contains(where: { !serverIds.contains($0.instanceId) }) {
                        self.items.removeAll { !serverIds.contains($0.instanceId) }
                    }
                }
                await self.localStore.syncCollectionFolder(username: username, folderId: folderId, fullItems: self.items)
            }
        }
    }

    private func fetchPage(
        _ page: Int,
        username: String,
        folderId: Int,
        credentials: DiscogsCredentials,
        append: Bool
    ) async throws {
        guard selectedFolderId == folderId else { return }
        let response = try await DiscogsAPIClient.shared.collectionItems(
            username: username,
            folderId: folderId,
            page: page,
            sort: sortOption.apiSortValue,
            sortOrder: sortOption.apiSortOrder(ascending: sortAscending),
            credentials: credentials
        )
        // Le compte a pu changer pendant la requête (déconnexion puis connexion à un autre
        // compte, souvent sur le même dossier "Tous") : la page reçue ne lui appartient pas.
        guard selectedFolderId == folderId, authManager.username == username else { return }
        let validReleases = response.releases.filter { $0.instanceId > 0 && $0.instanceId != $0.releaseId }
        let pageInstanceIds = Set(validReleases.map(\.instanceId))
        if page == 1 {
            serverInstanceIdsInCurrentPass = pageInstanceIds
        } else {
            serverInstanceIdsInCurrentPass.formUnion(pageInstanceIds)
        }
        let newItems: [CollectionItem]
        if append {
            var seen = Set<Int>()
            var combined: [CollectionItem] = []
            for item in items + validReleases {
                if item.instanceId > 0 && item.instanceId != item.releaseId && seen.insert(item.instanceId).inserted {
                    combined.append(item)
                }
            }
            newItems = combined
        } else {
            var seen = Set<Int>()
            newItems = validReleases.filter { seen.insert($0.instanceId).inserted }
        }
        items = newItems
        currentPage = page
        totalPages = response.pagination.pages

        // Sauvegarde dans le cache local SwiftData avec horodatage : seulement les exemplaires de
        // cette page (le reste de `newItems` y est déjà). Réencoder et réinsérer toute la liste
        // cumulée à chaque page rendait la synchro d'une grosse collection quadratique. Le cache
        // complet du dossier est réécrit une fois, en fin de synchro (`syncCollectionFolder`).
        await localStore.saveCollectionItems(validReleases, username: username, folderId: folderId)
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

    /// Supprime plusieurs exemplaires de la collection (édition en lot) — même logique que
    /// `moveInstances`, en réutilisant `remove` par exemplaire.
    func removeInstances(_ items: [CollectionItem]) async {
        for item in items {
            await remove(item)
        }
    }

    func remove(_ item: CollectionItem) async {
        guard let username = authManager.username else { return }

        // Si l'appareil est hors ligne et que les données ont plus de 6 heures (Option B) :
        // maintien de l'affichage en lecture seule et blocage des modifications
        if !networkMonitor.isConnected && isOfflineAndStale {
            actionMessage = AppMessages.offlineStaleModificationBlocked
            return
        }

        // Optimistic UI : retrait immédiat de la vue locale et du cache SwiftData
        items.removeAll { $0.id == item.id }
        localStore.removeCollectionItem(username: username, folderId: item.folderId, instanceId: item.instanceId)
        localStore.removeCollectionItem(username: username, folderId: DiscogsConstants.allFolderId, instanceId: item.instanceId)

        let remainingCopies = items.filter { $0.releaseId == item.releaseId }
        if remainingCopies.isEmpty {
            localStore.removeCollectionItems(username: username, releaseId: item.releaseId)
        }
        LibraryMembershipStore.shared.notifyCollectionItemRemoved(releaseId: item.releaseId, instanceId: item.instanceId)

        // Exemplaire ajouté hors ligne et pas encore envoyé : il suffit d'annuler son ajout en
        // attente (voir `OfflineSyncQueue.cancelPendingAdd`).
        if item.instanceId < 0 {
            syncQueue.cancelPendingAdd(temporaryInstanceId: item.instanceId)
            TagStore.shared.removeTags(for: item.instanceId)
            return
        }

        if networkMonitor.isConnected, let credentials = authManager.credentials {
            do {
                try await DiscogsAPIClient.shared.removeFromCollection(
                    username: username,
                    folderId: item.folderId,
                    releaseId: item.releaseId,
                    instanceId: item.instanceId,
                    credentials: credentials
                )
            } catch where error.isNotFound {
                // Déjà absent sur Discogs : le retrait est acquis.
            } catch where error.isTransientNetworkFailure {
                let action = PendingAction(
                    type: .removeFromCollection,
                    releaseId: item.releaseId,
                    folderId: item.folderId,
                    instanceId: item.instanceId
                )
                syncQueue.enqueue(action)
                actionMessage = AppMessages.discogsUnavailableQueued
            } catch {
                // Refus définitif : on réaffiche l'exemplaire plutôt que de laisser la file
                // échouer trois fois pendant qu'il semble retiré.
                withAnimation(.easeInOut(duration: 0.2)) {
                    if !items.contains(where: { $0.id == item.id }) {
                        items.append(item)
                    }
                }
                await localStore.saveCollectionItems([item], username: username, folderId: item.folderId)
                await localStore.saveCollectionItems([item], username: username, folderId: DiscogsConstants.allFolderId)
                LibraryMembershipStore.shared.markInCollection(item.releaseId)
                actionMessage = AppMessages.removalFailed
            }
        } else {
            // Hors ligne : enregistrement dans la file d'attente des mutations
            let action = PendingAction(
                type: .removeFromCollection,
                releaseId: item.releaseId,
                folderId: item.folderId,
                instanceId: item.instanceId
            )
            syncQueue.enqueue(action)
        }
    }

    /// Déplace un exemplaire vers un autre dossier Discogs, en répercutant les compteurs des
    /// dossiers concernés. Hors ligne, mis en file pour une synchro différée (même mécanique
    /// que `remove`).
    func moveInstance(_ item: CollectionItem, toFolderId: Int) async {
        guard let username = authManager.username, item.folderId != toFolderId else { return }

        if !networkMonitor.isConnected && isOfflineAndStale {
            actionMessage = AppMessages.offlineStaleModificationBlocked
            return
        }

        let originFolderId = item.folderId
        let movedItem = CollectionItem(
            releaseId: item.releaseId,
            folderId: toFolderId,
            rating: item.rating,
            dateAdded: item.dateAdded,
            basicInformation: item.basicInformation,
            instanceId: item.instanceId,
            notes: item.notes
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                // Si la vue est filtrée sur le dossier de départ, l'exemplaire déplacé n'y
                // appartient plus ; sinon (vue "Tous" ou déjà filtrée sur le nouveau dossier),
                // on reflète juste le changement en place.
                if selectedFolderId == originFolderId {
                    items.remove(at: index)
                } else {
                    items[index] = movedItem
                }
            }
            folders = folders.map { folder in
                if folder.id == originFolderId {
                    return CollectionFolder(id: folder.id, name: folder.name, count: max(0, folder.count - 1), resourceURL: folder.resourceURL)
                } else if folder.id == toFolderId {
                    return CollectionFolder(id: folder.id, name: folder.name, count: folder.count + 1, resourceURL: folder.resourceURL)
                }
                return folder
            }
        }

        localStore.removeCollectionItem(username: username, folderId: originFolderId, instanceId: item.instanceId)
        await localStore.saveCollectionItems([movedItem], username: username, folderId: toFolderId)
        await localStore.saveCollectionItems([movedItem], username: username, folderId: DiscogsConstants.allFolderId)
        LibraryMembershipStore.shared.notifyCollectionInstanceReplaced(oldInstanceId: item.instanceId, newInstance: movedItem)

        // Exemplaire ajouté hors ligne et pas encore envoyé : seul le dossier de son ajout en
        // attente change (voir `OfflineSyncQueue.retargetPendingAdd`).
        if item.instanceId < 0 {
            syncQueue.retargetPendingAdd(temporaryInstanceId: item.instanceId, toFolderId: toFolderId)
            return
        }

        if networkMonitor.isConnected, let credentials = authManager.credentials {
            do {
                try await DiscogsAPIClient.shared.moveCollectionInstance(
                    username: username,
                    folderId: originFolderId,
                    releaseId: item.releaseId,
                    instanceId: item.instanceId,
                    toFolderId: toFolderId,
                    credentials: credentials
                )
            } catch where error.isTransientNetworkFailure {
                syncQueue.enqueue(PendingAction(
                    type: .moveCollectionInstance,
                    releaseId: item.releaseId,
                    folderId: originFolderId,
                    instanceId: item.instanceId,
                    targetFolderId: toFolderId
                ))
                actionMessage = AppMessages.discogsUnavailableQueued
            } catch {
                // Refus définitif : on annule le déplacement optimiste (exemplaire, compteurs des
                // dossiers, cache) au lieu de laisser la file échouer trois fois.
                await revertMove(original: item, moved: movedItem, username: username)
                actionMessage = AppMessages.moveFailed
            }
        } else {
            syncQueue.enqueue(PendingAction(
                type: .moveCollectionInstance,
                releaseId: item.releaseId,
                folderId: originFolderId,
                instanceId: item.instanceId,
                targetFolderId: toFolderId
            ))
        }
    }

    /// Inverse exact de la mise à jour optimiste faite par `moveInstance`.
    private func revertMove(original: CollectionItem, moved: CollectionItem, username: String) async {
        let originFolderId = original.folderId
        let toFolderId = moved.folderId
        withAnimation(.easeInOut(duration: 0.2)) {
            if let index = items.firstIndex(where: { $0.id == original.id }) {
                // Vue filtrée sur le dossier de destination : l'exemplaire n'y a plus sa place.
                if selectedFolderId == toFolderId {
                    items.remove(at: index)
                } else {
                    items[index] = original
                }
            } else if selectedFolderId == originFolderId {
                // Retiré de la vue filtrée sur le dossier de départ : on l'y remet.
                items.append(original)
            }
            folders = folders.map { folder in
                if folder.id == originFolderId {
                    return CollectionFolder(id: folder.id, name: folder.name, count: folder.count + 1, resourceURL: folder.resourceURL)
                } else if folder.id == toFolderId {
                    return CollectionFolder(id: folder.id, name: folder.name, count: max(0, folder.count - 1), resourceURL: folder.resourceURL)
                }
                return folder
            }
        }
        localStore.removeCollectionItem(username: username, folderId: toFolderId, instanceId: original.instanceId)
        await localStore.saveCollectionItems([original], username: username, folderId: originFolderId)
        await localStore.saveCollectionItems([original], username: username, folderId: DiscogsConstants.allFolderId)
        LibraryMembershipStore.shared.notifyCollectionInstanceReplaced(oldInstanceId: original.instanceId, newInstance: original)
    }

    /// Reflète localement une note/des champs personnalisés déjà enregistrés par
    /// `CollectionItemEditSheet` (qui gère lui-même les appels réseau).
    func applyEditedValues(for item: CollectionItem, rating: Int, notes: [CollectionFieldValue]) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].rating = rating
        items[index].notes = notes
        guard let username = authManager.username else { return }
        let updated = items[index]
        await LocalDataStore.shared.saveCollectionItems([updated], username: username, folderId: updated.folderId)
        await LocalDataStore.shared.saveCollectionItems([updated], username: username, folderId: DiscogsConstants.allFolderId)
    }
}
