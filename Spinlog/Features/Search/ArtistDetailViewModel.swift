import Foundation
import UIKit
import Kingfisher

@Observable
@MainActor
final class ArtistDetailViewModel {
    /// Nom de l'artiste tel que connu de Discogs, qui ne sert qu'à l'identifier : nom à
    /// rechercher sur Apple Music, repli du titre (voir `title`). Tiré de la fiche Discogs, ou
    /// à défaut (hors ligne) de la collection/wantlist locale. `nil` : page non chargée.
    /// Tout ce qui s'affiche sur cette page vient d'Apple Music (photo, nom, biographie,
    /// discographie), sauf les indications de possession, tirées de la collection et de la
    /// wantlist de l'utilisateur.
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

    /// Les éditions d'un même album au catalogue Apple Music (Deluxe, Explicit, remasterisée…),
    /// regroupées sous un titre normalisé — voir `AppleMusicArtistArtworkService.normalizeTitle`.
    struct AlbumGroup: Identifiable {
        let titleKey: String
        /// Édition affichée : le titre le plus court (en général l'édition standard), puis la
        /// plus ancienne à égalité.
        let representative: AppleMusicAlbumSummary
        let versionCount: Int
        /// Année de la plus ancienne des éditions, soit celle de la sortie originale.
        let originalYear: String?
        var id: String { representative.id }
    }

    /// État de chargement d'une section de discographie Apple Music. Distingue explicitement
    /// « indisponible » (artiste introuvable ou erreur réseau) de « en cours » : confondre les
    /// deux laissait un indicateur de chargement tourner indéfiniment après un échec. Les
    /// groupes sont calculés une seule fois au chargement, pas à chaque rendu : la vue est
    /// réévaluée à chaque image du défilement (fondu du titre).
    enum SectionState {
        case loading
        case loaded([AlbumGroup])
        case unavailable
    }

    private(set) var sectionStates: [DiscographySection: SectionState] = [:]
    var selectedSection: DiscographySection = .albums

    /// Statut d'une œuvre par rapport à la collection locale de l'utilisateur, déterminé par
    /// rapprochement de titre (Apple Music ne connaît pas les identifiants Discogs).
    enum OwnershipStatus {
        case owned
        case inWantlist
    }

    struct DiscographyEntry: Identifiable {
        let group: AlbumGroup
        /// Les deux indicateurs sont indépendants : un album peut être à la fois possédé et en
        /// wantlist (ex. un pressage différent désiré en plus de celui déjà possédé) — un simple
        /// statut unique masquerait l'un des deux badges.
        let isOwned: Bool
        let isInWantlist: Bool
        /// Fiche album à ouvrir (ton exemplaire, ou le master qui regroupe tes pressages) si
        /// possédé ou en wantlist — `nil` sinon (rien à ouvrir).
        let destination: SearchDestination?
        var id: String { group.id }
    }

    /// Un exemplaire de la collection ou de la wantlist locale crédité à cet artiste.
    private struct LibraryRecord {
        let releaseId: Int
        let titleKey: String
        let masterId: Int?
        let coverURL: String?
        let dateAdded: Date?
    }

    /// Indexés par identifiant de release : une notification d'ajout/retrait (voir
    /// `observeLibraryChanges`) met à jour une entrée précise sans tout relire.
    private var ownedRecords: [Int: LibraryRecord] = [:] { didSet { rebuildMembershipIndex() } }
    private var wantedRecords: [Int: LibraryRecord] = [:] { didSet { rebuildMembershipIndex() } }

    /// Titres normalisés possédés/désirés de cet artiste, dérivés des exemplaires ci-dessus.
    private(set) var ownedKeys: Set<String> = []
    private(set) var wantlistKeys: Set<String> = []

    /// Nombre d'albums distincts de cet artiste présents dans la collection/wantlist locales,
    /// affiché en résumé sous la photo. Un même album peut compter dans les deux.
    var ownedCount: Int { ownedKeys.count }
    var wantlistCount: Int { wantlistKeys.count }

    private var artistId: Int?
    @ObservationIgnored private var appleMusicPreparation: Task<Void, Never>?
    @ObservationIgnored private var isRefreshingAppleMusic = false
    @ObservationIgnored nonisolated(unsafe) private var observerTokens: [NSObjectProtocol] = []

    init() {
        observeLibraryChanges()
    }

    deinit {
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }

    /// Titre de la page : le nom Apple Music. Seule exception à la règle « rien de Discogs »,
    /// quand l'artiste est introuvable sur Apple Music (ou l'accès refusé) : le nom Discogs,
    /// débarrassé de son suffixe d'homonymie (« Ghost (32) » → « Ghost »), pour ne pas laisser
    /// la page sans titre.
    var title: String {
        if let appleMusicName { return appleMusicName }
        return AppleMusicArtistArtworkService.strippingDiscogsDisambiguation(artistName ?? "")
    }

    var visibleSectionState: SectionState {
        sectionStates[selectedSection] ?? .loading
    }

    /// Vrai s'il manque encore un élément Apple Music à la page (artiste non identifié, photo
    /// ou section affichée non chargée) — pour n'afficher le bandeau hors ligne qu'à bon escient.
    var hasIncompleteAppleMusicContent: Bool {
        if appleMusicName == nil || artworkURL == nil { return true }
        if case .loaded = visibleSectionState { return false }
        return true
    }

    /// Lignes de discographie à afficher, à partir des groupes déjà calculés et de l'index de
    /// possession : un ajout/retrait de collection ou de wantlist se reflète immédiatement sur
    /// les badges, sans recharger la discographie.
    func entries(for groups: [AlbumGroup]) -> [DiscographyEntry] {
        groups.map { group in
            DiscographyEntry(
                group: group,
                isOwned: ownedKeys.contains(group.titleKey),
                isInWantlist: wantlistKeys.contains(group.titleKey),
                destination: destination(forTitleKey: group.titleKey)
            )
        }
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
        await refreshAppleMusic(for: name)
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
        guard let artistName else {
            await load(artistId: artistId)
            return
        }
        guard appleMusicAccess == .authorized else { return }
        await refreshAppleMusic(for: artistName)
    }

    /// Unique chemin de chargement Apple Music (premier affichage, retour depuis les Réglages,
    /// retour du réseau) : ne recharge que ce qui manque encore, sans effacer ce qui est déjà
    /// affiché. Les autres sections de discographie sont chargées paresseusement (voir
    /// `loadSectionIfNeeded`), au moment où l'utilisateur les sélectionne.
    private func refreshAppleMusic(for name: String) async {
        guard !isRefreshingAppleMusic else { return }
        isRefreshingAppleMusic = true
        defer { isRefreshingAppleMusic = false }

        // Une section restée indisponible sera retentée à sa prochaine sélection.
        for (section, state) in sectionStates {
            if case .unavailable = state { sectionStates[section] = nil }
        }
        let section = selectedSection
        var needsSection = true
        if case .loaded = sectionStates[section] { needsSection = false }
        if needsSection { sectionStates[section] = .loading }
        if appleMusicName == nil { isResolvingAppleMusicArtist = true }
        if artworkURL == nil { isLoadingArtwork = true }

        // Mémorisée avant toute suspension, pour qu'une section sélectionnée entre-temps
        // l'attende (voir `loadSectionIfNeeded`).
        let preparation = Task { await self.prepareAppleMusic(for: name) }
        appleMusicPreparation = preparation
        await preparation.value
        await loadAppleMusicContent(for: name, section: needsSection ? section : nil)
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
            sectionStates = [:]
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            isResolvingAppleMusicArtist = false
            isLoadingArtwork = false
            markLoadingSectionsUnavailable()
            return
        }
        await service.prepareArtist(named: name, knownAlbumTitles: ownedKeys.union(wantlistKeys))
        // Déjà en cache après `prepareArtist` : aucune requête supplémentaire.
        appleMusicName = await service.catalogName(for: name)
        appleMusicURL = await service.catalogURL(for: name)
        isResolvingAppleMusicArtist = false
    }

    /// Photo et biographie si elles manquent encore, et la section demandée.
    private func loadAppleMusicContent(for name: String, section: DiscographySection?) async {
        guard appleMusicAccess == .authorized, NetworkMonitor.shared.isConnected else { return }
        let service = AppleMusicArtistArtworkService.shared
        let needsArtwork = artworkURL == nil
        let needsBiography = biography == nil
        await withTaskGroup(of: Void.self) { group in
            if needsArtwork {
                group.addTask { @MainActor in
                    defer { self.isLoadingArtwork = false }
                    guard let url = await service.artworkURL(for: name, size: 600) else { return }
                    // Préchargée avant d'être affichée : l'en-tête passe directement de
                    // l'indicateur de chargement à la photo complète, par un fondu.
                    _ = try? await KingfisherManager.shared.retrieveImage(with: url)
                    self.artworkURL = url
                }
            }
            if needsBiography {
                group.addTask { @MainActor in
                    self.biography = await service.editorialNotes(for: name)
                }
            }
            if let section {
                group.addTask { @MainActor in
                    await self.fetchSection(section, artistName: name)
                }
            }
        }
    }

    /// Appelée quand l'utilisateur sélectionne une section. Recharge aussi une section restée
    /// indisponible (ex. erreur réseau passagère) : revenir dessus suffit à retenter.
    func loadSectionIfNeeded(_ section: DiscographySection) async {
        guard let artistName, appleMusicAccess != .denied else { return }
        switch sectionStates[section] {
        case .loading, .loaded:
            return
        case .unavailable, nil:
            sectionStates[section] = .loading
            await appleMusicPreparation?.value
            guard appleMusicAccess == .authorized else {
                sectionStates[section] = nil
                return
            }
            guard NetworkMonitor.shared.isConnected else {
                sectionStates[section] = .unavailable
                return
            }
            await fetchSection(section, artistName: artistName)
        }
    }

    func retrySelectedSection() async {
        await loadSectionIfNeeded(selectedSection)
    }

    private func markLoadingSectionsUnavailable() {
        for (section, state) in sectionStates {
            if case .loading = state { sectionStates[section] = .unavailable }
        }
    }

    /// Suppose la section déjà marquée `.loading` par l'appelant (ce qui évite qu'un second
    /// appel concurrent ne relance la même requête).
    private func fetchSection(_ section: DiscographySection, artistName: String) async {
        if let albums = await AppleMusicArtistArtworkService.shared.albums(for: artistName, section: section) {
            sectionStates[section] = .loaded(Self.groupEditions(albums))
        } else {
            sectionStates[section] = .unavailable
        }
    }

    /// Regroupe les éditions d'un même album en conservant l'ordre du catalogue (position de la
    /// première édition rencontrée).
    private static func groupEditions(_ albums: [AppleMusicAlbumSummary]) -> [AlbumGroup] {
        var order: [String] = []
        var versionsByKey: [String: [AppleMusicAlbumSummary]] = [:]
        for album in albums {
            let key = AppleMusicArtistArtworkService.normalizeTitle(album.name)
            if versionsByKey[key] == nil {
                order.append(key)
            }
            versionsByKey[key, default: []].append(album)
        }
        return order.compactMap { key in
            guard let versions = versionsByKey[key],
                  let representative = versions.min(by: { lhs, rhs in
                      if lhs.name.count != rhs.name.count { return lhs.name.count < rhs.name.count }
                      return (lhs.releaseDate ?? "9999") < (rhs.releaseDate ?? "9999")
                  }) else { return nil }
            // Dates au format ISO (« 1991-09-24 », parfois juste « 1991 ») : l'ordre
            // lexicographique est aussi l'ordre chronologique.
            let earliestDate = versions.compactMap(\.releaseDate).min()
            return AlbumGroup(
                titleKey: key,
                representative: representative,
                versionCount: versions.count,
                originalYear: earliestDate.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
            )
        }
    }

    // MARK: - Possession locale

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

    /// Exemplaires de la collection et de la wantlist locales crédités à cet artiste, identifié
    /// par son identifiant Discogs plutôt que par son nom : une comparaison de noms par
    /// inclusion rattachait à tort « Ghostface Killah » à « Ghost », par exemple.
    private func applyLocalMembership(collection: [LibraryPayloadSummary], wantlist: [LibraryPayloadSummary]) {
        var owned: [Int: LibraryRecord] = [:]
        for summary in collection {
            guard let record = record(for: summary) else { continue }
            owned[summary.releaseId] = record
        }
        var wanted: [Int: LibraryRecord] = [:]
        for summary in wantlist {
            guard let record = record(for: summary) else { continue }
            wanted[summary.releaseId] = record
        }
        ownedRecords = owned
        wantedRecords = wanted
    }

    private func record(for summary: LibraryPayloadSummary) -> LibraryRecord? {
        guard isCredited(artistIds: summary.artistIds, artistNames: summary.artistNames) else { return nil }
        return LibraryRecord(
            releaseId: summary.releaseId,
            titleKey: AppleMusicArtistArtworkService.normalizeTitle(summary.title),
            masterId: summary.masterId,
            coverURL: summary.thumb,
            dateAdded: summary.dateAdded
        )
    }

    private func record(for info: BasicInformation, releaseId: Int, dateAdded: Date?) -> LibraryRecord? {
        guard isCredited(artistIds: (info.artists ?? []).map(\.id), artistNames: info.artistNames) else { return nil }
        return LibraryRecord(
            releaseId: releaseId,
            titleKey: AppleMusicArtistArtworkService.normalizeTitle(info.title),
            masterId: info.masterId,
            coverURL: info.thumb,
            dateAdded: dateAdded
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
        ownedKeys = Set(ownedRecords.values.map(\.titleKey))
        wantlistKeys = Set(wantedRecords.values.map(\.titleKey))
    }

    /// Fiche à ouvrir pour un titre : l'exemplaire possédé (à défaut, celui en wantlist). Si
    /// plusieurs pressages différents de ce titre sont concernés, la fiche master — qui les
    /// regroupe tous — plutôt qu'un pressage pris arbitrairement ; à défaut de master commun,
    /// le pressage ajouté le plus récemment.
    private func destination(forTitleKey key: String) -> SearchDestination? {
        let owned = ownedRecords.values.filter { $0.titleKey == key }
        let candidates = owned.isEmpty ? wantedRecords.values.filter { $0.titleKey == key } : owned
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1, let only = candidates.first {
            return .release(only.releaseId, coverURL: only.coverURL)
        }
        let masterIds = Set(candidates.map(\.masterId))
        if masterIds.count == 1, let masterId = masterIds.first ?? nil {
            return .master(masterId)
        }
        let mostRecent = candidates.max { ($0.dateAdded ?? .distantPast) < ($1.dateAdded ?? .distantPast) }
        return mostRecent.map { .release($0.releaseId, coverURL: $0.coverURL) }
    }

    /// Suit les ajouts/retraits faits ailleurs dans l'app (ex. depuis une fiche album ouverte
    /// depuis cette page) à partir du contenu des notifications : le cache local SwiftData
    /// n'est réécrit qu'au prochain chargement des onglets Collection/Wantlist, le relire ici
    /// ne refléterait pas le changement. Suit aussi le retour du réseau, pour compléter la page
    /// sans action de l'utilisateur.
    private func observeLibraryChanges() {
        let center = NotificationCenter.default
        observerTokens = [
            center.addObserver(forName: .collectionItemAdded, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let item = note.userInfo?["item"] as? CollectionItem else { return }
                    self.handleCollectionItemAdded(item)
                }
            },
            center.addObserver(forName: .collectionInstanceReplaced, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let item = note.userInfo?["newItem"] as? CollectionItem else { return }
                    self.handleCollectionItemAdded(item)
                }
            },
            center.addObserver(forName: .collectionItemRemoved, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let releaseId = note.userInfo?["releaseId"] as? Int else { return }
                    // Retiré seulement s'il ne reste aucun autre exemplaire de cette release.
                    if !LibraryMembershipStore.shared.isInCollection(releaseId) {
                        self.ownedRecords[releaseId] = nil
                    }
                }
            },
            center.addObserver(forName: .wantlistItemAdded, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let item = note.userInfo?["item"] as? WantlistItem,
                          let record = self.record(for: item.basicInformation, releaseId: item.id, dateAdded: item.dateAddedDate) else { return }
                    self.wantedRecords[item.id] = record
                }
            },
            center.addObserver(forName: .wantlistItemRemoved, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let releaseId = note.userInfo?["releaseId"] as? Int else { return }
                    self.wantedRecords[releaseId] = nil
                }
            },
            center.addObserver(forName: .networkConnectionRestored, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.handleConnectionRestored() }
                }
            }
        ]
    }

    private func handleCollectionItemAdded(_ item: CollectionItem) {
        guard let record = record(for: item.basicInformation, releaseId: item.releaseId, dateAdded: item.dateAddedDate) else { return }
        ownedRecords[item.releaseId] = record
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
        let title: String
        let thumb: String?
        let masterId: Int?
        let artists: [ArtistRef]?

        private enum CodingKeys: String, CodingKey {
            case title, thumb, artists
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
