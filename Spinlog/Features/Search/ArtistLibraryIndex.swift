import Foundation

/// Identité de l'artiste de la page, pour reconnaître les disques locaux qui lui sont crédités.
/// Un disque est rattaché par l'identifiant Discogs de l'artiste plutôt que par son nom : une
/// comparaison de noms par inclusion rattachait à tort « Ghostface Killah » à « Ghost », par
/// exemple.
struct ArtistCredit {
    let artistId: Int?
    let artistName: String?

    func isCredited(artistIds: [Int], artistNames: String) -> Bool {
        if !artistIds.isEmpty, let artistId {
            return artistIds.contains(artistId)
        }
        // Repli si l'entrée ne porte pas d'identifiants d'artistes : égalité stricte des noms.
        guard let artistName else { return false }
        let target = AppleMusicArtistArtworkService.comparableArtistName(artistName)
        return !target.isEmpty && AppleMusicArtistArtworkService.comparableArtistName(artistNames) == target
    }
}

/// Collection et wantlist locales telles que la page artiste les utilise : exemplaires indexés
/// par release, titres normalisés de cet artiste (résumé et identification Apple Music) et
/// regroupement par master (badges de la discographie Discogs). Type valeur : les index dérivés
/// sont recalculés à chaque changement, jamais à chaque rendu (la vue est réévaluée à chaque
/// image du défilement).
struct ArtistLibraryIndex {
    /// Un exemplaire de la collection ou de la wantlist locale (tous artistes confondus : la
    /// discographie Discogs rapproche par identifiant de master/release, sans dépendre des
    /// crédits d'artiste du disque).
    struct Record {
        let releaseId: Int
        /// Titre normalisé, seulement pour les disques crédités à cet artiste : compte les albums
        /// distincts du résumé (`ownedCount`/`wantlistCount`) et aide à identifier l'artiste
        /// sur Apple Music. `nil` pour les disques d'autres artistes.
        let titleKey: String?
        let masterId: Int?
        let coverURL: String?
        let dateAdded: Date?
        /// Noms et descriptions de formats du pressage (« Vinyl », « LP », « Album »…) : classent
        /// sans requête la section Discogs d'un master dont l'utilisateur possède un pressage.
        let formatTokens: [String]

        init(summary: ArtistLibraryPayloadSummary, credit: ArtistCredit) {
            let credited = credit.isCredited(artistIds: summary.artistIds, artistNames: summary.artistNames)
            releaseId = summary.releaseId
            // Normalisation (expressions régulières) réservée aux disques de cet artiste.
            titleKey = credited ? AppleMusicArtistArtworkService.normalizeTitle(summary.title) : nil
            masterId = summary.masterId
            coverURL = summary.thumb
            dateAdded = summary.dateAdded
            formatTokens = summary.formatTokens
        }

        init(info: BasicInformation, releaseId: Int, dateAdded: Date?, credit: ArtistCredit) {
            let credited = credit.isCredited(artistIds: (info.artists ?? []).map(\.id), artistNames: info.artistNames)
            self.releaseId = releaseId
            titleKey = credited ? AppleMusicArtistArtworkService.normalizeTitle(info.title) : nil
            masterId = info.masterId
            coverURL = info.thumb
            self.dateAdded = dateAdded
            formatTokens = (info.formats ?? []).flatMap { [$0.name] + ($0.descriptions ?? []) }
        }
    }

    /// Possession d'une œuvre de la discographie, et fiche où mener un toucher sur sa ligne.
    struct Ownership {
        let isOwned: Bool
        let isInWantlist: Bool
        /// Fiche de ton exemplaire (à défaut, de celui en wantlist) ; sinon, pour un master, sa
        /// fiche master. `nil` pour une release isolée ni possédée ni en wantlist : la ligne reste
        /// alors purement informative.
        let destination: SearchDestination?
    }

    /// Indexés par identifiant de release : une notification d'ajout/retrait met à jour une
    /// entrée précise sans tout relire.
    private(set) var owned: [Int: Record] = [:]
    private(set) var wanted: [Int: Record] = [:]
    /// Titres normalisés possédés/désirés de cet artiste, dérivés des exemplaires ci-dessus.
    private(set) var ownedKeys: Set<String> = []
    private(set) var wantlistKeys: Set<String> = []
    private var ownedByMaster: [Int: [Record]] = [:]
    private var wantedByMaster: [Int: [Record]] = [:]

    mutating func replace(owned: [Int: Record], wanted: [Int: Record]) {
        self.owned = owned
        self.wanted = wanted
        rebuild()
    }

    mutating func setOwned(_ record: Record?, forReleaseId releaseId: Int) {
        owned[releaseId] = record
        rebuild()
    }

    mutating func setWanted(_ record: Record?, forReleaseId releaseId: Int) {
        wanted[releaseId] = record
        rebuild()
    }

    private mutating func rebuild() {
        ownedKeys = Set(owned.values.compactMap(\.titleKey))
        wantlistKeys = Set(wanted.values.compactMap(\.titleKey))
        ownedByMaster = Dictionary(grouping: owned.values.filter { $0.masterId != nil }) { $0.masterId ?? 0 }
        wantedByMaster = Dictionary(grouping: wanted.values.filter { $0.masterId != nil }) { $0.masterId ?? 0 }
    }

    /// Un master est « possédé » si l'un de tes exemplaires s'y rattache, une release isolée si
    /// tu la possèdes elle-même.
    func ownership(of work: ArtistReleaseItem) -> Ownership {
        let ownedRecords = records(for: work, in: owned, byMaster: ownedByMaster)
        let wantedRecords = records(for: work, in: wanted, byMaster: wantedByMaster)
        let target = (ownedRecords.isEmpty ? wantedRecords : ownedRecords)
            .max { ($0.dateAdded ?? .distantPast) < ($1.dateAdded ?? .distantPast) }
        let destination: SearchDestination? = if let target {
            .release(target.releaseId, coverURL: target.coverURL)
        } else if work.kind == .master {
            // Œuvre ni possédée ni en wantlist : sa fiche master (la même que depuis une fiche
            // album), qui liste toutes ses éditions.
            .master(work.discogsId)
        } else {
            nil
        }
        return Ownership(isOwned: !ownedRecords.isEmpty, isInWantlist: !wantedRecords.isEmpty, destination: destination)
    }

    private func records(for work: ArtistReleaseItem, in records: [Int: Record], byMaster: [Int: [Record]]) -> [Record] {
        switch work.kind {
        case .master: byMaster[work.discogsId] ?? []
        case .release: records[work.discogsId].map { [$0] } ?? []
        case nil: []
        }
    }

    /// Formats d'un pressage local (possédé ou en wantlist) de ce master, s'il y en a un.
    func localFormatTokens(forMasterId masterId: Int) -> [String]? {
        let pressings = (ownedByMaster[masterId] ?? []) + (wantedByMaster[masterId] ?? [])
        return pressings.first(where: { !$0.formatTokens.isEmpty })?.formatTokens
    }
}

/// Règles de la discographie Discogs de la page artiste, sans état : testées dans `SpinlogTests`.
enum ArtistDiscographyRules {
    /// Section d'une œuvre déterminable sans requête, ou `nil` s'il faut lire son pressage
    /// principal. Release isolée : format fourni par la liste. Master : cache permanent, sinon
    /// pressage local — son format suffit à classer l'œuvre, sans être mémorisé dans le cache
    /// (il décrit un pressage de l'utilisateur, pas le pressage principal).
    static func immediateCategory(
        for work: ArtistReleaseItem,
        cachedCategory: DiscogsWorkCategory?,
        localFormatTokens: [String]?
    ) -> DiscogsWorkCategory? {
        switch work.kind {
        case .release:
            return work.format.map(DiscogsDiscography.category(fromFormatSummary:)) ?? .other
        case .master:
            if let cachedCategory { return cachedCategory }
            return localFormatTokens.map(DiscogsDiscography.category(fromFormatTokens:))
        case nil:
            return .other
        }
    }

    /// État de la liste après la réception de la page `page` sur `totalPages` : tant qu'il reste
    /// des pages (jusqu'à `maxPages`) la liste se charge encore ; au plafond, elle est partielle
    /// si l'artiste en a davantage.
    static func stateAfterPage(
        _ page: Int,
        totalPages: Int,
        maxPages: Int
    ) -> ArtistDetailViewModel.DiscogsDiscographyState {
        let lastPage = min(totalPages, maxPages)
        return .loaded(isLoadingMore: page < lastPage, isTruncated: page >= lastPage && totalPages > maxPages)
    }
}
