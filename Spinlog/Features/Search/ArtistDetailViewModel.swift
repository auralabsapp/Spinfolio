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

    /// Un exemplaire de la collection ou de la wantlist locale (tous artistes confondus : la
    /// discographie Discogs rapproche par identifiant de master/release, sans dépendre des
    /// crédits d'artiste du disque).
    private struct LibraryRecord {
        let releaseId: Int
        /// Titre normalisé, seulement pour les disques crédités à cet artiste : compte les albums
        /// distincts du résumé (`ownedCount`/`wantlistCount`) et aide à identifier l'artiste
        /// sur Apple Music (voir `prepareAppleMusic`). `nil` pour les disques d'autres artistes.
        let titleKey: String?
        let masterId: Int?
        let coverURL: String?
        let dateAdded: Date?
        /// Noms et descriptions de formats du pressage (« Vinyl », « LP », « Album »…) : classent
        /// sans requête la section Discogs d'un master dont l'utilisateur possède un pressage.
        let formatTokens: [String]
    }

    /// Indexés par identifiant de release : une notification d'ajout/retrait (voir
    /// `observeLibraryChanges`) met à jour une entrée précise sans tout relire.
    private var ownedRecords: [Int: LibraryRecord] = [:] { didSet { rebuildMembershipIndex() } }
    private var wantedRecords: [Int: LibraryRecord] = [:] { didSet { rebuildMembershipIndex() } }

    /// Titres normalisés possédés/désirés de cet artiste, dérivés des exemplaires ci-dessus.
    private(set) var ownedKeys: Set<String> = []
    private(set) var wantlistKeys: Set<String> = []
    /// Exemplaires regroupés par master, pour les badges de la discographie Discogs : calculés
    /// une fois par changement, pas à chaque rendu (la vue est réévaluée à chaque image du
    /// défilement).
    private var ownedByMaster: [Int: [LibraryRecord]] = [:]
    private var wantedByMaster: [Int: [LibraryRecord]] = [:]

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

    /// État de la section « Discographie Discogs » : œuvres principales de l'artiste, avec
    /// possession rapprochée par identifiant de master/release.
    enum DiscogsDiscographyState: Equatable {
        /// Aucune page encore reçue.
        case loading
        /// Au moins une page reçue. `isLoadingMore` : pages suivantes en cours ; `isTruncated` :
        /// liste partielle (plafond de pages atteint, ou échec d'une page suivante).
        case loaded(isLoadingMore: Bool, isTruncated: Bool)
        /// Échec avant la première page (erreur réseau, hors ligne).
        case unavailable
    }

    struct DiscogsWorkEntry: Identifiable {
        let work: ArtistReleaseItem
        let isOwned: Bool
        let isInWantlist: Bool
        /// Fiche de ton exemplaire (à défaut, de celui en wantlist) ; sinon, pour un master, sa
        /// fiche master. `nil` pour une release isolée ni possédée ni en wantlist : la ligne reste
        /// alors purement informative.
        let destination: SearchDestination?
        var id: String { work.id }
    }

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

    /// Choix du sélecteur de la discographie Discogs : une section, ou l'option temporaire
    /// « Tri en cours » qui regroupe les œuvres pas encore ventilées. Distinct de
    /// `DiscogsWorkCategory`, dont les valeurs sont persistées (cache, iCloud) : une œuvre n'est
    /// jamais « classée » en cours de tri.
    enum DiscogsSectionFilter: Hashable, Identifiable {
        case category(DiscogsWorkCategory)
        case pending

        var id: String {
            switch self {
            case .category(let category): category.rawValue
            case .pending: "pending"
            }
        }
    }

    var selectedDiscogsFilter: DiscogsSectionFilter = .category(.albums)

    /// Œuvres pas encore ventilées dans une section.
    var pendingDiscogsCount: Int {
        discogsWorks.reduce(0) { count, work in discogsCategories[work.id] == nil ? count + 1 : count }
    }

    /// Les quatre sections, puis « Tri en cours » tant qu'il reste des œuvres à ventiler : elle
    /// se vide au fil du classement et disparaît une fois vide.
    var discogsFilterOptions: [DiscogsSectionFilter] {
        let categories = DiscogsWorkCategory.allCases.map(DiscogsSectionFilter.category)
        return pendingDiscogsCount > 0 ? categories + [.pending] : categories
    }

    func title(for filter: DiscogsSectionFilter) -> String {
        switch filter {
        case .category(let category):
            return category.title
        case .pending:
            // Après un classement interrompu (erreurs réseau), les œuvres restantes ne sont plus
            // « en cours » de tri : on le dit plutôt que de laisser croire que ça avance.
            return isSortingDiscogsWorks ? String(localized: "Tri en cours") : String(localized: "Non classées")
        }
    }

    /// Vrai tant que des œuvres peuvent encore être ventilées : pages en cours de chargement, ou
    /// classement en cours.
    var isSortingDiscogsWorks: Bool {
        if discogsClassificationProgress != nil { return true }
        switch discogsDiscographyState {
        case .loading, .loaded(isLoadingMore: true, isTruncated: _): return true
        default: return false
        }
    }

    struct ClassificationProgress: Equatable {
        let done: Int
        let total: Int
    }

    /// Classement en cours (masters dont il faut lire le pressage principal) ; `nil` sinon.
    private(set) var discogsClassificationProgress: ClassificationProgress?
    @ObservationIgnored private var isClassifyingDiscogsWorks = false

    /// La liste brute inclut toutes les apparitions de l'artiste (des milliers d'entrées pour
    /// un artiste prolifique), alors que le filtre « rôle principal » ne peut se faire que côté
    /// app : au-delà de ce plafond (1 000 entrées brutes), la liste est signalée comme partielle.
    private static let maxDiscogsDiscographyPages = 10

    /// Lignes de la discographie Discogs, avec leur statut de possession : un master est
    /// « possédé » si l'un de tes exemplaires s'y rattache, une release isolée si tu la
    /// possèdes elle-même.
    func discogsEntries() -> [DiscogsWorkEntry] {
        discogsWorks.filter { work in
            switch selectedDiscogsFilter {
            case .category(let category): discogsCategories[work.id] == category
            case .pending: discogsCategories[work.id] == nil
            }
        }.map { work in
            let owned = libraryRecords(for: work, in: ownedRecords, byMaster: ownedByMaster)
            let wanted = libraryRecords(for: work, in: wantedRecords, byMaster: wantedByMaster)
            let target = (owned.isEmpty ? wanted : owned)
                .max { ($0.dateAdded ?? .distantPast) < ($1.dateAdded ?? .distantPast) }
            let destination: SearchDestination? = if let target {
                .release(target.releaseId, coverURL: target.coverURL)
            } else if work.kind == .master {
                // Œuvre ni possédée ni en wantlist : sa fiche master (la même que depuis une
                // fiche album), qui liste toutes ses éditions.
                .master(work.discogsId)
            } else {
                nil
            }
            return DiscogsWorkEntry(
                work: work,
                isOwned: !owned.isEmpty,
                isInWantlist: !wanted.isEmpty,
                destination: destination
            )
        }
    }

    private func libraryRecords(
        for work: ArtistReleaseItem,
        in records: [Int: LibraryRecord],
        byMaster: [Int: [LibraryRecord]]
    ) -> [LibraryRecord] {
        switch work.kind {
        case .master: byMaster[work.discogsId] ?? []
        case .release: records[work.discogsId].map { [$0] } ?? []
        case nil: []
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
        switch work.kind {
        case .release:
            return work.format.map(DiscogsDiscography.category(fromFormatSummary:)) ?? .other
        case .master:
            if let cached = DiscogsWorkCategoryCache.shared.category(forMasterId: work.discogsId) {
                return cached
            }
            // Pressage local de ce master : son format suffit à classer l'œuvre. Pas mémorisé
            // dans le cache : il décrit un pressage de l'utilisateur, pas le pressage principal.
            let localPressings = (ownedByMaster[work.discogsId] ?? []) + (wantedByMaster[work.discogsId] ?? [])
            if let tokens = localPressings.first(where: { !$0.formatTokens.isEmpty })?.formatTokens {
                return DiscogsDiscography.category(fromFormatTokens: tokens)
            }
            return nil
        case nil:
            return .other
        }
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
                let lastPage = min(totalPages, Self.maxDiscogsDiscographyPages)
                discogsDiscographyState = .loaded(
                    isLoadingMore: page < lastPage,
                    isTruncated: page >= lastPage && totalPages > Self.maxDiscogsDiscographyPages
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
    func load(artistId: Int) async {
        self.artistId = artistId
        isLoading = true
        errorMessage = nil
        // Lecture locale lancée tout de suite, en parallèle de la requête Discogs.
        let library = startLocalLibraryDecoding()
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
        let (collection, wantlist) = await library.value
        guard let name = discogsName ?? Self.localArtistName(id: artistId, in: collection + wantlist) else {
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
        await service.prepareArtist(named: name, knownAlbumTitles: ownedKeys.union(wantlistKeys))
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

    /// Lit la collection et la wantlist locales. Le décodage JSON des payloads se fait hors du
    /// fil principal : sur une grosse collection, il figeait l'interface à l'ouverture de la page.
    private func startLocalLibraryDecoding() -> Task<([LibraryPayloadSummary], [LibraryPayloadSummary]), Never> {
        guard let username = DiscogsAuthManager.shared.username else {
            return Task { ([], []) }
        }
        let collectionPayloads = LocalDataStore.shared.collectionPayloads(username: username)
        let wantlistPayloads = LocalDataStore.shared.wantlistPayloads(username: username)
        return Task.detached(priority: .userInitiated) {
            (LibraryPayloadSummary.decodeAll(collectionPayloads), LibraryPayloadSummary.decodeAll(wantlistPayloads))
        }
    }

    /// Nom d'un artiste d'après les disques locaux qui le créditent (repli hors ligne).
    private static func localArtistName(id: Int, in summaries: [LibraryPayloadSummary]) -> String? {
        for summary in summaries {
            if let match = summary.artists.first(where: { $0.id == id }) {
                return match.name
            }
        }
        return nil
    }

    /// Index de la collection et de la wantlist locales. Les disques crédités à cet artiste sont
    /// reconnus par son identifiant Discogs plutôt que par son nom : une comparaison de noms par
    /// inclusion rattachait à tort « Ghostface Killah » à « Ghost », par exemple.
    private func applyLocalMembership(collection: [LibraryPayloadSummary], wantlist: [LibraryPayloadSummary]) {
        var owned: [Int: LibraryRecord] = [:]
        for summary in collection {
            owned[summary.releaseId] = record(for: summary)
        }
        var wanted: [Int: LibraryRecord] = [:]
        for summary in wantlist {
            wanted[summary.releaseId] = record(for: summary)
        }
        ownedRecords = owned
        wantedRecords = wanted
    }

    private func record(for summary: LibraryPayloadSummary) -> LibraryRecord {
        let credited = isCredited(artistIds: summary.artistIds, artistNames: summary.artistNames)
        return LibraryRecord(
            releaseId: summary.releaseId,
            // Normalisation (expressions régulières) réservée aux disques de cet artiste.
            titleKey: credited ? AppleMusicArtistArtworkService.normalizeTitle(summary.title) : nil,
            masterId: summary.masterId,
            coverURL: summary.thumb,
            dateAdded: summary.dateAdded,
            formatTokens: summary.formatTokens
        )
    }

    private func record(for info: BasicInformation, releaseId: Int, dateAdded: Date?) -> LibraryRecord {
        let credited = isCredited(artistIds: (info.artists ?? []).map(\.id), artistNames: info.artistNames)
        return LibraryRecord(
            releaseId: releaseId,
            titleKey: credited ? AppleMusicArtistArtworkService.normalizeTitle(info.title) : nil,
            masterId: info.masterId,
            coverURL: info.thumb,
            dateAdded: dateAdded,
            formatTokens: (info.formats ?? []).flatMap { [$0.name] + ($0.descriptions ?? []) }
        )
    }

    private func isCredited(artistIds: [Int], artistNames: String) -> Bool {
        if !artistIds.isEmpty, let artistId {
            return artistIds.contains(artistId)
        }
        // Repli si l'entrée ne porte pas d'identifiants d'artistes : égalité stricte des noms.
        guard let name = artistName else { return false }
        let target = AppleMusicArtistArtworkService.comparableArtistName(name)
        return !target.isEmpty && AppleMusicArtistArtworkService.comparableArtistName(artistNames) == target
    }

    private func rebuildMembershipIndex() {
        ownedKeys = Set(ownedRecords.values.compactMap(\.titleKey))
        wantlistKeys = Set(wantedRecords.values.compactMap(\.titleKey))
        ownedByMaster = Dictionary(grouping: ownedRecords.values.filter { $0.masterId != nil }) { $0.masterId ?? 0 }
        wantedByMaster = Dictionary(grouping: wantedRecords.values.filter { $0.masterId != nil }) { $0.masterId ?? 0 }
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
                    self.ownedRecords[releaseId] = nil
                }
            },
            addLibraryObserver(for: .wantlistItemAdded, payloadKey: "item") { [weak self] (item: WantlistItem) in
                guard let self else { return }
                self.wantedRecords[item.id] = self.record(for: item.basicInformation, releaseId: item.id, dateAdded: item.dateAddedDate)
            },
            addLibraryObserver(for: .wantlistItemRemoved, payloadKey: "releaseId") { [weak self] (releaseId: Int) in
                self?.wantedRecords[releaseId] = nil
            },
            addLibraryObserver(for: .networkConnectionRestored) { [weak self] in
                guard let self else { return }
                Task { await self.handleConnectionRestored() }
            }
        ]
    }

    private func handleCollectionItemAdded(_ item: CollectionItem) {
        ownedRecords[item.releaseId] = record(for: item.basicInformation, releaseId: item.releaseId, dateAdded: item.dateAddedDate)
    }
}

/// Lecture partielle d'un payload de collection ou de wantlist en cache (même structure JSON
/// pour les deux : `id` = release, `date_added`, `basic_information`), limitée aux champs utiles
/// à la page artiste. `nonisolated` : décodée dans une tâche détachée, hors du fil principal.
nonisolated private struct LibraryPayloadSummary: Decodable, Sendable {
    nonisolated struct Info: Decodable, Sendable {
        nonisolated struct ArtistRef: Decodable, Sendable {
            let id: Int
            let name: String
        }
        nonisolated struct FormatRef: Decodable, Sendable {
            let name: String
            let descriptions: [String]?
        }
        let title: String
        let thumb: String?
        let masterId: Int?
        let artists: [ArtistRef]?
        let formats: [FormatRef]?

        private enum CodingKeys: String, CodingKey {
            case title, thumb, artists, formats
            case masterId = "master_id"
        }
    }

    let releaseId: Int
    let dateAddedRaw: String?
    let info: Info
    /// Renseignée par `decodeAll`, après le décodage JSON.
    var dateAdded: Date?

    var title: String { info.title }
    var thumb: String? { info.thumb }
    var masterId: Int? { info.masterId }
    var artists: [Info.ArtistRef] { info.artists ?? [] }
    var formatTokens: [String] { (info.formats ?? []).flatMap { [$0.name] + ($0.descriptions ?? []) } }
    var artistIds: [Int] { (info.artists ?? []).map(\.id) }
    var artistNames: String { (info.artists ?? []).map(\.name).joined(separator: ", ") }

    private enum CodingKeys: String, CodingKey {
        case releaseId = "id"
        case dateAddedRaw = "date_added"
        case info = "basic_information"
    }

    static func decodeAll(_ payloads: [Data]) -> [LibraryPayloadSummary] {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFraction = ISO8601DateFormatter()
        return payloads.compactMap { payload in
            guard var summary = try? decoder.decode(LibraryPayloadSummary.self, from: payload) else { return nil }
            if let raw = summary.dateAddedRaw {
                summary.dateAdded = withoutFraction.date(from: raw) ?? withFraction.date(from: raw)
            }
            return summary
        }
    }
}
