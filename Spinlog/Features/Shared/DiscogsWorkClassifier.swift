import Foundation

/// Classe les masters d'un artiste dans les sections de sa discographie (Albums, Singles & EP…),
/// pour la page artiste comme pour le classement en tâche de fond
/// (`DiscogsCategoryBackfillService`). Chaque classement obtenu est mémorisé dans
/// `DiscogsWorkCategoryCache`.
///
/// Deux étapes, de la moins coûteuse à la plus coûteuse :
/// 1. la recherche Discogs des masters portant le nom de l'artiste : chaque résultat donne le
///    format de son master, jusqu'à 100 par requête. Elle se fait par nom et mélange donc les
///    homonymes : seuls les résultats dont l'identifiant figure parmi les masters demandés sont
///    retenus, ce qui écarte d'office ceux des autres artistes ;
/// 2. pour les masters que la recherche n'a pas trouvés, une requête par master pour lire les
///    formats de son pressage principal.
///
/// Les réponses sont décodées hors du fil principal, dans des types minimaux (sans liste de
/// titres ni crédits).
@MainActor
enum DiscogsWorkClassifier {
    struct PendingMaster: Sendable {
        let masterId: Int
        let mainRelease: Int?
    }

    /// Au-delà, la recherche ne rapporte presque plus rien (résultats triés par pertinence, de
    /// plus en plus éloignés de l'artiste) : le reste passe par le pressage principal.
    private static let maxSearchPages = 3

    /// - Parameters:
    ///   - masters: masters encore jamais classés.
    ///   - artistName: nom Discogs de l'artiste, suffixe d'homonymie compris (retiré ici).
    ///   - onClassified: appelé pour chaque master classé, au fil de l'eau.
    /// - Returns: `.complete`, ou `.interrupted` (annulation, perte du réseau, master isolé
    ///   illisible), ou `.transientFailure` (quota Discogs dépassé, panne passagère) : dans ce cas
    ///   l'appelant de fond doit s'arrêter plutôt que de passer à l'artiste suivant et brûler le
    ///   quota. Les masters restants pourront être repris plus tard.
    @discardableResult
    static func classify(
        _ masters: [PendingMaster],
        artistName: String,
        onClassified: (Int, DiscogsWorkCategory) -> Void
    ) async -> Outcome {
        var remaining = Dictionary(masters.map { ($0.masterId, $0) }, uniquingKeysWith: { first, _ in first })
        guard !remaining.isEmpty else { return .complete }
        let credentials = DiscogsAuthManager.shared.credentials

        func record(_ category: DiscogsWorkCategory, for masterId: Int) {
            DiscogsWorkCategoryCache.shared.store(category, forMasterId: masterId)
            remaining[masterId] = nil
            onClassified(masterId, category)
        }

        // 1. Recherche : rentable dès deux masters (un seul coûte autant par son pressage).
        let searchName = AppleMusicArtistArtworkService.strippingDiscogsDisambiguation(artistName)
        if remaining.count >= 2, !searchName.isEmpty {
            var page = 1
            var totalPages = 1
            while page <= min(totalPages, maxSearchPages), !remaining.isEmpty {
                guard !Task.isCancelled, NetworkMonitor.shared.isConnected else { return .interrupted }
                do {
                    let response: MasterSearchResponse = try await DiscogsAPIClient.shared.searchMastersDecodedInBackground(
                        artist: searchName,
                        page: page,
                        credentials: credentials
                    )
                    totalPages = response.pagination.pages
                    var matched = 0
                    for hit in response.results {
                        guard remaining[hit.id] != nil, let format = hit.format, !format.isEmpty else { continue }
                        record(DiscogsDiscography.category(fromFormatTokens: format), for: hit.id)
                        matched += 1
                    }
                    // Une page sans aucun master de l'artiste : les suivantes, moins
                    // pertinentes encore, n'en contiendront guère plus.
                    if matched == 0 && page > 1 { break }
                    page += 1
                } catch {
                    if error.isCancellation { return .interrupted }
                    if error.isTransientNetworkFailure { return .transientFailure }
                    break
                }
            }
        }

        // 2. Pressage principal, pour ce que la recherche n'a pas trouvé.
        for master in masters where remaining[master.masterId] != nil {
            guard !Task.isCancelled, NetworkMonitor.shared.isConnected else { return .interrupted }
            guard let mainRelease = master.mainRelease else {
                // Rien à lire : rangé dans « Autres ».
                record(.other, for: master.masterId)
                continue
            }
            do {
                let release: ReleaseFormatsResponse = try await DiscogsAPIClient.shared.releaseDecodedInBackground(
                    id: mainRelease,
                    credentials: credentials
                )
                let tokens = (release.formats ?? []).flatMap { [$0.name] + ($0.descriptions ?? []) }
                record(DiscogsDiscography.category(fromFormatTokens: tokens), for: master.masterId)
            } catch {
                if error.isCancellation { return .interrupted }
                // Quota ou panne : les suivants échoueraient de même, et le master reste à classer.
                if error.isTransientNetworkFailure { return .transientFailure }
                // Échec isolé (ex. réponse invalide) : on continue avec les suivants.
            }
        }
        return remaining.isEmpty ? .complete : .interrupted
    }

    enum Outcome: Equatable {
        case complete
        case interrupted
        case transientFailure
    }
}

/// Résultat de `GET /database/search?type=master` réduit au strict nécessaire. `format` agrège
/// noms et descriptions (« Vinyl », « LP », « Album »…), comme le format résumé d'une release.
nonisolated private struct MasterSearchResponse: Decodable, Sendable {
    nonisolated struct Hit: Decodable, Sendable {
        let id: Int
        let format: [String]?
    }
    nonisolated struct Pages: Decodable, Sendable {
        let pages: Int
    }
    let pagination: Pages
    let results: [Hit]
}

/// Fiche d'une release réduite à ses formats.
nonisolated private struct ReleaseFormatsResponse: Decodable, Sendable {
    nonisolated struct Format: Decodable, Sendable {
        let name: String
        let descriptions: [String]?
    }
    let formats: [Format]?
}
