import Foundation
import UIKit
import Kingfisher

@Observable
@MainActor
final class ArtistDetailViewModel {
    /// Nom de l'artiste tel que connu de Discogs, qui ne sert qu'à l'identifier : nom à
    /// rechercher sur Apple Music, repli du titre (voir `title`). Tiré de la fiche Discogs, ou
    /// à défaut (hors ligne) de la collection/wantlist locale. `nil` : page non chargée.
    /// La page affiche Apple Music (photo, nom, biographie) puis la discographie Discogs ; les
    /// indications de possession viennent de la collection et de la wantlist de l'utilisateur.
    private(set) var artistName: String?
    private(set) var artworkURL: URL?
    /// Vrai tant que la photo Apple Music est en cours de recherche/téléchargement.
    private(set) var isLoadingArtwork = true
    /// Nom de l'artiste au catalogue Apple Music — voir `title`.
    private(set) var appleMusicName: String?
    /// Vrai tant que l'artiste Apple Music n'a pas encore été identifié.
    private(set) var isResolvingAppleMusicArtist = true
    /// Page de l'artiste sur Apple Music, pour les boutons « Partager » et « Ouvrir dans Apple
    /// Music » de la barre de navigation (masqués tant qu'elle est inconnue).
    private(set) var appleMusicURL: URL?
    /// Couleur moyenne de la photo, pour teinter le fond comme sur la fiche album (voir
    /// `UIColor.infoBackgroundColor(for:)`). `nil` : fond système.
    var averageColor: UIColor?
    /// Note éditoriale Apple Music, uniquement si disponible pour cet artiste — voir
    /// `AppleMusicArtistArtworkService.editorialNotes(for:)`.
    private(set) var biography: String?
    /// Accès au catalogue Apple Music, `nil` tant qu'il n'a pas été vérifié. Refusé, la page
    /// explique pourquoi elle est vide et renvoie vers les Réglages (voir `ArtistDetailView`).
    private(set) var appleMusicAccess: AppleMusicArtistArtworkService.Access?
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    /// Vrai si le cache local de la collection a plus de 6 heures (règle des CGU Discogs, voir
    /// `LocalDataStore.isCollectionStale`) : hors ligne, la page affiche alors le même bandeau
    /// « Instantané archivé du… » que la Collection, puisque la possession et le nom affichés en
    /// proviennent. Évalué au chargement et au retour du réseau (lecture SwiftData : pas à chaque
    /// rendu).
    private(set) var isLibrarySnapshotStale = false

    /// Collection et wantlist locales, avec leurs index dérivés (titres de cet artiste, masters).
    private var library = ArtistLibraryIndex()

    /// Titres normalisés possédés/désirés de cet artiste.
    var ownedKeys: Set<String> { library.ownedKeys }
    var wantlistKeys: Set<String> { library.wantlistKeys }

    /// Nombre d'albums distincts de cet artiste présents dans la collection/wantlist locales,
    /// affiché en résumé sous la photo. Un même album peut compter dans les deux.
    var ownedCount: Int { ownedKeys.count }
    var wantlistCount: Int { wantlistKeys.count }

    private var artistId: Int?
    @ObservationIgnored private var isRefreshingAppleMusic = false
    @ObservationIgnored nonisolated(unsafe) private var observerTokens: [NSObjectProtocol] = []

    init() {
        observeLibraryChanges()
    }

    deinit {
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }

    /// Titre de la page : le nom Apple Music ; à défaut (artiste introuvable sur Apple Music, ou
    /// accès refusé), le nom Discogs, débarrassé de son suffixe d'homonymie (« Ghost (32) » →
    /// « Ghost »), pour ne pas laisser la page sans titre.
    var title: String {
        if let appleMusicName { return appleMusicName }
        return AppleMusicArtistArtworkService.strippingDiscogsDisambiguation(artistName ?? "")
    }

    // MARK: - Discographie Discogs

    /// Page de l'artiste sur discogs.com, pour la mention d'attribution exigée par les CGU de
    /// l'API Discogs sous la section qui affiche leurs données (voir `DiscogsAttributionLink`).
    var discogsArtistURL: URL? {
        artistId.map { DiscogsConstants.websiteURL.appendingPathComponent("artist/\($0)") }
    }

    private(set) var discogsDiscographyState: DiscogsDiscographyState = .loading
    private(set) var discogsWorks: [ArtistReleaseItem] = []
    @ObservationIgnored private var isLoadingDiscogsDiscography = false

    /// Section de chaque œuvre (clé : `ArtistReleaseItem.id`), au fur et à mesure du classement.
    /// Une œuvre absente n'est pas encore classée et n'apparaît dans aucune section.
    private(set) var discogsCategories: [String: DiscogsWorkCategory] = [:]

    var selectedDiscogsFilter: DiscogsSectionFilter = .category(.albums)

    /// Classement en cours (masters dont il faut lire le pressage principal) ; `nil` sinon.
    private(set) var discogsClassificationProgress: ClassificationProgress?
    @ObservationIgnored private var isClassifyingDiscogsWorks = false

    /// La liste brute inclut toutes les apparitions de l'artiste (des milliers d'entrées pour
    /// un artiste prolifique), alors que le filtre « rôle principal » ne peut se faire que côté
    /// app : au-delà de ce plafond (1 000 entrées brutes), la liste est signalée comme partielle.
    private static let maxDiscogsDiscographyPages = 10

    /// Lignes de la discographie Discogs, avec leur statut de possession (voir
    /// `ArtistLibraryIndex.ownership(of:)`).
    func discogsEntries() -> [DiscogsWorkEntry] {
        discogsWorks.filter { work in
            switch selectedDiscogsFilter {
            case .category(let category): discogsCategories[work.id] == category
            case .pending: discogsCategories[work.id] == nil
            }
        }.map { work in
            let ownership = library.ownership(of: work)
            return DiscogsWorkEntry(
                work: work,
                isOwned: ownership.isOwned,
                isInWantlist: ownership.isInWantlist,
                destination: ownership.destination
            )
        }
    }

    func retryDiscogsDiscography() async {
        await loadDiscogsDiscography()
    }

    func retryDiscogsClassification() async {
        await classifyDiscogsWorks()
    }

    /// Range chaque œuvre dans une section (Albums, Singles & EP, Compilations, Autres), comme
    /// sur le site discogs.com — l'API ne fournit pas ces sections, elles se déduisent du format.
    /// Sans requête quand c'est possible : release isolée (format fourni par la liste), master
    /// déjà classé (cache permanent), ou master dont l'utilisateur possède ou recherche un
    /// pressage (format présent dans la collection/wantlist locale). Sinon, par la recherche
    /// Discogs puis le pressage principal (voir `DiscogsWorkClassifier`), au rythme imposé par
    /// l'API ; la liste se range au fil de l'eau et le résultat est mémorisé pour les fois
    /// suivantes.
    private func classifyDiscogsWorks() async {
        guard !isClassifyingDiscogsWorks else { return }
        isClassifyingDiscogsWorks = true
        defer {
            isClassifyingDiscogsWorks = false
            discogsClassificationProgress = nil
            DiscogsWorkCategoryCache.shared.flush()
        }

        let pending = applyImmediateCategories()
        guard !pending.isEmpty else {
            leavePendingFilterIfEmpty()
            return
        }

        guard let artistName else { return }
        var done = 0
        discogsClassificationProgress = ClassificationProgress(done: 0, total: pending.count)
        let workIdsByMaster = Dictionary(pending.map { ($0.work.discogsId, $0.work.id) }, uniquingKeysWith: { first, _ in first })
        // Classement progressif en tâche de fond pendant que l'utilisateur consulte déjà la
        // discographie — même appel que `DiscogsCategoryBackfillService`, qui le priorise déjà en
        // `.background` ; ce point d'appel-ci ne le faisait pas, incohérence corrigée ici.
        await DiscogsRateLimiter.$priority.withValue(.background) {
            await DiscogsWorkClassifier.classify(
                pending.map { DiscogsWorkClassifier.PendingMaster(masterId: $0.work.discogsId, mainRelease: $0.mainRelease) },
                artistName: artistName
            ) { masterId, category in
                guard let workId = workIdsByMaster[masterId] else { return }
                discogsCategories[workId] = category
                done += 1
                discogsClassificationProgress = ClassificationProgress(done: done, total: pending.count)
                leavePendingFilterIfEmpty()
            }
        }
    }

    /// « Tri en cours » disparaît du sélecteur une fois vide : s'il était sélectionné, on revient
    /// sur Albums plutôt que de laisser une sélection sans option correspondante.
    private func leavePendingFilterIfEmpty() {
        if selectedDiscogsFilter == .pending && pendingDiscogsCount == 0 {
            selectedDiscogsFilter = .category(.albums)
        }
    }

    /// Classe tout ce qui peut l'être sans requête et renvoie les masters restants (avec leur
    /// pressage principal à lire). Appelé à chaque page reçue : les sections se remplissent dès
    /// le chargement, sans attendre la dernière page.
    @discardableResult
    private func applyImmediateCategories() -> [(work: ArtistReleaseItem, mainRelease: Int)] {
        var pending: [(work: ArtistReleaseItem, mainRelease: Int)] = []
        for work in discogsWorks where discogsCategories[work.id] == nil {
            if let category = immediateCategory(for: work) {
                discogsCategories[work.id] = category
            } else if let mainRelease = work.mainRelease {
                pending.append((work, mainRelease))
            } else {
                // Master sans pressage principal renseigné : rien à lire, rangé dans « Autres ».
                discogsCategories[work.id] = .other
            }
        }
        return pending
    }

    private func immediateCategory(for work: ArtistReleaseItem) -> DiscogsWorkCategory? {
        ArtistDiscographyRules.immediateCategory(
            for: work,
            cachedCategory: work.kind == .master ? DiscogsWorkCategoryCache.shared.category(forMasterId: work.discogsId) : nil,
            localFormatTokens: work.kind == .master ? library.localFormatTokens(forMasterId: work.discogsId) : nil
        )
    }

    /// Charge la discographie page par page : la liste s'affiche et s'enrichit à chaque page
    /// reçue, sans attendre la dernière (chaque page passe par le limiteur de débit du client
    /// Discogs, soit environ une par seconde).
    private func loadDiscogsDiscography() async {
        guard let artistId, !isLoadingDiscogsDiscography else { return }
        if case .loaded(isLoadingMore: false, isTruncated: false) = discogsDiscographyState {
            // Liste complète : il peut seulement rester des œuvres à classer (ex. retour du réseau).
            await classifyDiscogsWorks()
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            if discogsWorks.isEmpty { discogsDiscographyState = .unavailable }
            return
        }
        isLoadingDiscogsDiscography = true
        defer { isLoadingDiscogsDiscography = false }

        discogsDiscographyState = .loading
        discogsWorks = []
        var rawItems: [ArtistReleaseItem] = []
        var page = 1
        var totalPages = 1
        while page <= min(totalPages, Self.maxDiscogsDiscographyPages) {
            do {
                let response = try await DiscogsAPIClient.shared.artistReleases(
                    artistId: artistId,
                    page: page,
                    credentials: DiscogsAuthManager.shared.credentials
                )
                totalPages = response.pagination.pages
                rawItems += response.releases
                discogsWorks = DiscogsDiscography.mainWorks(from: rawItems)
                applyImmediateCategories()
                discogsDiscographyState = ArtistDiscographyRules.stateAfterPage(
                    page,
                    totalPages: totalPages,
                    maxPages: Self.maxDiscogsDiscographyPages
                )
                page += 1
            } catch {
                discogsDiscographyState = rawItems.isEmpty
                    ? .unavailable
                    : .loaded(isLoadingMore: false, isTruncated: true)
                break
            }
        }
        await classifyDiscogsWorks()
    }

    /// Vrai s'il manque encore un élément Apple Music à la page (artiste non identifié ou
    /// photo non chargée) — pour n'afficher le bandeau hors ligne qu'à bon escient.
    var hasIncompleteAppleMusicContent: Bool {
        appleMusicName == nil || artworkURL == nil
    }

    /// Charge la page en deux temps. D'abord l'identité de l'artiste (son nom, à rechercher sur
    /// Apple Music) et la possession locale : la page s'affiche dès cette étape, avec des
    /// emplacements en cours de chargement. Ensuite Apple Music (voir `refreshAppleMusic`).
    ///
    /// Le nom vient de la fiche Discogs ; si elle est injoignable (hors ligne), il est retrouvé
    /// dans la collection ou la wantlist locale, qui crédite l'artiste par son identifiant :
    /// la page reste consultable pour tout artiste dont l'utilisateur possède ou recherche un
    /// disque, au lieu d'un écran d'erreur.
    /// Chargement à l'apparition de la vue. Au retour d'un écran poussé depuis celui-ci, les données
    /// sont déjà affichées : on ne repasse PAS par l'état « chargement », qui remplacerait le
    /// contenu défilant par le squelette et ferait perdre la position de lecture (même règle que
    /// `ReleaseDetailViewModel.loadIfNeeded`). Le rafraîchissement d'Apple Music et du réseau a ses
    /// propres déclencheurs (voir `refreshAfterReturningToForeground`)..
    func loadIfNeeded(artistId: Int) async {
        guard self.artistId != artistId || artistName == nil || errorMessage != nil else { return }
        await load(artistId: artistId)
    }

    func load(artistId: Int) async {
        self.artistId = artistId
        isLoading = true
        errorMessage = nil
        // Lecture locale lancée tout de suite, en parallèle de la requête Discogs.
        let localLibrary = ArtistLocalLibrary.startDecoding(username: DiscogsAuthManager.shared.username)
        refreshLibrarySnapshotStaleness()
        var discogsName: String?
        var discogsError: Error?
        // Testé avant la requête : le mode hors ligne simulé (options développeur) coupe
        // `isConnected` sans couper le réseau réel.
        if NetworkMonitor.shared.isConnected {
            do {
                discogsName = try await DiscogsAPIClient.shared.artist(id: artistId, credentials: DiscogsAuthManager.shared.credentials).name
            } catch {
                discogsError = error
            }
        }
        let (collection, wantlist) = await localLibrary.value
        guard let name = discogsName ?? ArtistLocalLibrary.artistName(id: artistId, in: collection + wantlist) else {
            if NetworkMonitor.shared.isConnected, let discogsError {
                errorMessage = discogsError.localizedDescription
            } else {
                errorMessage = String(localized: "Cet artiste n'est ni dans ta collection ni dans ta wantlist : sa fiche nécessite une connexion réseau.")
            }
            isLoading = false
            return
        }
        artistName = name
        applyLocalMembership(collection: collection, wantlist: wantlist)
        isLoading = false
        // Discographie Discogs et contenu Apple Music se chargent en parallèle.
        async let discogsDiscography: Void = loadDiscogsDiscography()
        await refreshAppleMusic(for: name)
        await discogsDiscography
    }

    /// À appeler au retour au premier plan : si l'accès à Apple Music était refusé et vient
    /// d'être accordé dans les Réglages, la page se complète sans avoir à la rouvrir.
    func refreshAfterReturningToForeground() async {
        guard appleMusicAccess == .denied, let artistName,
              await AppleMusicArtistArtworkService.shared.ensureAccess() == .authorized else { return }
        await refreshAppleMusic(for: artistName)
    }

    /// Au retour du réseau : complète ce qui n'a pas pu être chargé hors ligne, ou relance
    /// toute la page si elle s'était arrêtée sur une erreur.
    private func handleConnectionRestored() async {
        guard let artistId else { return }
        refreshLibrarySnapshotStaleness()
        guard let artistName else {
            await load(artistId: artistId)
            return
        }
        // Ne relance rien si la discographie Discogs est déjà complète (voir sa garde).
        async let discogsDiscography: Void = loadDiscogsDiscography()
        if appleMusicAccess == .authorized {
            await refreshAppleMusic(for: artistName)
        }
        await discogsDiscography
    }

    /// Unique chemin de chargement Apple Music (premier affichage, retour depuis les Réglages,
    /// retour du réseau) : ne recharge que ce qui manque encore, sans effacer ce qui est déjà
    /// affiché.
    private func refreshAppleMusic(for name: String) async {
        guard !isRefreshingAppleMusic else { return }
        isRefreshingAppleMusic = true
        defer { isRefreshingAppleMusic = false }

        if appleMusicName == nil { isResolvingAppleMusicArtist = true }
        if artworkURL == nil { isLoadingArtwork = true }

        await prepareAppleMusic(for: name)
        await loadAppleMusicContent(for: name)
    }

    /// Vérifie l'accès (avec l'invite système si elle n'a jamais été présentée), puis identifie
    /// l'artiste Apple Music en départageant d'éventuels homonymes à partir des albums que
    /// l'utilisateur possède ou recherche. Hors ligne, rien n'est demandé : la page affiche le
    /// bandeau hors ligne et se complétera au retour du réseau (`handleConnectionRestored`).
    private func prepareAppleMusic(for name: String) async {
        let service = AppleMusicArtistArtworkService.shared
        let access = await service.ensureAccess()
        appleMusicAccess = access
        guard access == .authorized else {
            isResolvingAppleMusicArtist = false
            isLoadingArtwork = false
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            isResolvingAppleMusicArtist = false
            isLoadingArtwork = false
            return
        }
        await service.prepareArtist(named: name, knownAlbumTitles: library.ownedKeys.union(library.wantlistKeys))
        // Déjà en cache après `prepareArtist` : aucune requête supplémentaire.
        appleMusicName = await service.catalogName(for: name)
        appleMusicURL = await service.catalogURL(for: name)
        isResolvingAppleMusicArtist = false
    }

    /// Photo et biographie si elles manquent encore.
    private func loadAppleMusicContent(for name: String) async {
        guard appleMusicAccess == .authorized, NetworkMonitor.shared.isConnected else { return }
        // `async let` plutôt qu'un groupe de tâches : photo et biographie se chargent toujours en
        // parallèle, et le vérificateur de concurrence de Swift 6 sait analyser ce motif.
        async let artworkLoad: Void = artworkURL == nil ? loadArtwork(for: name) : ()
        async let biographyLoad: Void = biography == nil ? loadBiography(for: name) : ()
        _ = await (artworkLoad, biographyLoad)
    }

    private func loadArtwork(for name: String) async {
        defer { isLoadingArtwork = false }
        guard let url = await AppleMusicArtistArtworkService.shared.artworkURL(for: name, size: 600) else { return }
        // Préchargée avant d'être affichée : l'en-tête passe directement de l'indicateur de
        // chargement à la photo complète, par un fondu.
        _ = try? await KingfisherManager.shared.retrieveImage(with: url)
        artworkURL = url
    }

    private func loadBiography(for name: String) async {
        biography = await AppleMusicArtistArtworkService.shared.editorialNotes(for: name)
    }

    // MARK: - Possession locale

    private func refreshLibrarySnapshotStaleness() {
        guard let username = DiscogsAuthManager.shared.username else {
            isLibrarySnapshotStale = false
            return
        }
        isLibrarySnapshotStale = LocalDataStore.shared.isCollectionStale(username: username, folderId: DiscogsConstants.allFolderId)
    }

    /// Index de la collection et de la wantlist locales (voir `ArtistCredit` pour le rattachement
    /// des disques à cet artiste).
    private func applyLocalMembership(collection: [ArtistLibraryPayloadSummary], wantlist: [ArtistLibraryPayloadSummary]) {
        let credit = ArtistCredit(artistId: artistId, artistName: artistName)
        library.replace(
            owned: Dictionary(collection.map { ($0.releaseId, ArtistLibraryIndex.Record(summary: $0, credit: credit)) }, uniquingKeysWith: { _, last in last }),
            wanted: Dictionary(wantlist.map { ($0.releaseId, ArtistLibraryIndex.Record(summary: $0, credit: credit)) }, uniquingKeysWith: { _, last in last })
        )
    }

    private func record(for info: BasicInformation, releaseId: Int, dateAdded: Date?) -> ArtistLibraryIndex.Record {
        ArtistLibraryIndex.Record(
            info: info,
            releaseId: releaseId,
            dateAdded: dateAdded,
            credit: ArtistCredit(artistId: artistId, artistName: artistName)
        )
    }

    /// Suit les ajouts/retraits faits ailleurs dans l'app (ex. depuis une fiche album ouverte
    /// depuis cette page) à partir du contenu des notifications : le cache local SwiftData
    /// n'est réécrit qu'au prochain chargement des onglets Collection/Wantlist, le relire ici
    /// ne refléterait pas le changement. Suit aussi le retour du réseau, pour compléter la page
    /// sans action de l'utilisateur.
    private func observeLibraryChanges() {
        observerTokens = [
            addLibraryObserver(for: .collectionItemAdded, payloadKey: "item") { [weak self] (item: CollectionItem) in
                self?.handleCollectionItemAdded(item)
            },
            addLibraryObserver(for: .collectionInstanceReplaced, payloadKey: "newItem") { [weak self] (item: CollectionItem) in
                self?.handleCollectionItemAdded(item)
            },
            addLibraryObserver(for: .collectionItemRemoved, payloadKey: "releaseId") { [weak self] (releaseId: Int) in
                guard let self else { return }
                // Retiré seulement s'il ne reste aucun autre exemplaire de cette release.
                if !LibraryMembershipStore.shared.isInCollection(releaseId) {
                    self.library.setOwned(nil, forReleaseId: releaseId)
                }
            },
            addLibraryObserver(for: .wantlistItemAdded, payloadKey: "item") { [weak self] (item: WantlistItem) in
                guard let self else { return }
                self.library.setWanted(self.record(for: item.basicInformation, releaseId: item.id, dateAdded: item.dateAddedDate), forReleaseId: item.id)
            },
            addLibraryObserver(for: .wantlistItemRemoved, payloadKey: "releaseId") { [weak self] (releaseId: Int) in
                self?.library.setWanted(nil, forReleaseId: releaseId)
            },
            addLibraryObserver(for: .networkConnectionRestored) { [weak self] in
                guard let self else { return }
                Task { await self.handleConnectionRestored() }
            }
        ]
    }

    private func handleCollectionItemAdded(_ item: CollectionItem) {
        library.setOwned(record(for: item.basicInformation, releaseId: item.releaseId, dateAdded: item.dateAddedDate), forReleaseId: item.releaseId)
    }
}
