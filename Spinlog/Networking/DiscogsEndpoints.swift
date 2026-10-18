import Foundation

/// Endpoints Discogs utilisés par l'app, au-dessus du client HTTP générique.
/// Référence : https://www.discogs.com/developers
extension DiscogsAPIClient {
    func search(
        query: String,
        type: String? = nil,
        page: Int = 1,
        perPage: Int = DiscogsConstants.maxPageSize,
        credentials: DiscogsCredentials? = nil
    ) async throws -> SearchResponse {
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        if let type {
            items.append(URLQueryItem(name: "type", value: type))
        }
        return try await request(path: "database/search", queryItems: items, credentials: credentials)
    }

    func searchByBarcode(_ barcode: String, credentials: DiscogsCredentials? = nil) async throws -> SearchResponse {
        try await request(
            path: "database/search",
            queryItems: [URLQueryItem(name: "barcode", value: barcode), URLQueryItem(name: "type", value: "release")],
            credentials: credentials
        )
    }

    func release(id: Int, credentials: DiscogsCredentials? = nil) async throws -> Release {
        try await request(path: "releases/\(id)", credentials: credentials)
    }

    func masterRelease(id: Int, credentials: DiscogsCredentials? = nil) async throws -> MasterRelease {
        try await request(path: "masters/\(id)", credentials: credentials)
    }

    func masterVersions(masterId: Int, page: Int = 1, credentials: DiscogsCredentials? = nil) async throws -> MasterVersionsResponse {
        try await request(
            path: "masters/\(masterId)/versions",
            queryItems: [URLQueryItem(name: "page", value: String(page))],
            credentials: credentials
        )
    }

    func artist(id: Int, credentials: DiscogsCredentials? = nil) async throws -> Artist {
        try await request(path: "artists/\(id)", credentials: credentials)
    }

    /// Une page de la discographie d'un artiste, de la plus récente à la plus ancienne. Inclut
    /// ses apparitions secondaires : à filtrer avec `DiscogsDiscography.mainWorks`.
    func artistReleases(
        artistId: Int,
        page: Int = 1,
        perPage: Int = DiscogsConstants.maxPageSize,
        credentials: DiscogsCredentials? = nil
    ) async throws -> ArtistReleasesResponse {
        try await request(
            path: "artists/\(artistId)/releases",
            queryItems: [
                URLQueryItem(name: "sort", value: "year"),
                URLQueryItem(name: "sort_order", value: "desc"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ],
            credentials: credentials
        )
    }

    func userProfile(username: String, credentials: DiscogsCredentials? = nil) async throws -> DiscogsUserProfile {
        try await request(path: "users/\(username)", credentials: credentials)
    }

    /// Nombre d'exemplaires en vente et prix le plus bas, avec la devise exacte (plus fiable
    /// que `num_for_sale`/`lowest_price` de `/releases/{id}`, qui suppose l'USD par défaut).
    func marketplaceStats(
        releaseId: Int,
        currency: String? = nil,
        credentials: DiscogsCredentials? = nil
    ) async throws -> MarketplaceStats {
        var queryItems: [URLQueryItem] = []
        if let currency, !currency.isEmpty {
            queryItems.append(URLQueryItem(name: "curr_abbr", value: currency.uppercased()))
        }
        return try await request(
            path: "marketplace/stats/\(releaseId)",
            queryItems: queryItems,
            credentials: credentials
        )
    }

    /// Estimation de prix par état du disque. Nécessite un compte connecté (n'importe lequel,
    /// pas seulement le vendeur) ; Discogs ne renvoie que les états pour lesquels il a assez
    /// d'historique de ventes, donc certaines entrées peuvent être absentes.
    func priceSuggestions(releaseId: Int, credentials: DiscogsCredentials) async throws -> [String: MarketplacePrice] {
        try await request(path: "marketplace/price_suggestions/\(releaseId)", credentials: credentials)
    }

    func label(id: Int, credentials: DiscogsCredentials? = nil) async throws -> DiscogsLabel {
        try await request(path: "labels/\(id)", credentials: credentials)
    }

    // MARK: - Collection

    func collectionFolders(username: String, credentials: DiscogsCredentials?) async throws -> CollectionFoldersResponse {
        try await request(path: "users/\(username)/collection/folders", credentials: credentials)
    }

    private struct FolderNamePayload: Encodable {
        let name: String
    }

    func createCollectionFolder(username: String, name: String, credentials: DiscogsCredentials) async throws {
        try await requestVoid(
            path: "users/\(username)/collection/folders",
            method: "POST",
            body: JSONEncoder().encode(FolderNamePayload(name: name)),
            credentials: credentials
        )
    }

    func renameCollectionFolder(username: String, folderId: Int, name: String, credentials: DiscogsCredentials) async throws {
        try await requestVoid(
            path: "users/\(username)/collection/folders/\(folderId)",
            method: "POST",
            body: JSONEncoder().encode(FolderNamePayload(name: name)),
            credentials: credentials
        )
    }

    /// Discogs refuse la suppression d'un dossier non vide : vider le dossier d'abord.
    func deleteCollectionFolder(username: String, folderId: Int, credentials: DiscogsCredentials) async throws {
        try await requestVoid(
            path: "users/\(username)/collection/folders/\(folderId)",
            method: "DELETE",
            credentials: credentials
        )
    }

    /// Estimation globale de la collection basée sur l'historique réel des ventes Discogs
    /// (pas les annonces en cours) — un seul appel, pas besoin d'interroger chaque release.
    func collectionValue(username: String, credentials: DiscogsCredentials) async throws -> CollectionValueResponse {
        try await request(path: "users/\(username)/collection/value", credentials: credentials)
    }

    /// Liste les exemplaires d'une release précise déjà présents dans la collection de
    /// l'utilisateur (tous dossiers confondus), pour savoir s'il la possède déjà.
    func collectionInstances(
        username: String,
        releaseId: Int,
        credentials: DiscogsCredentials
    ) async throws -> CollectionReleasesResponse {
        try await request(path: "users/\(username)/collection/releases/\(releaseId)", credentials: credentials)
    }

    func collectionItems(
        username: String,
        folderId: Int,
        page: Int = 1,
        perPage: Int = DiscogsConstants.maxPageSize,
        sort: String? = nil,
        sortOrder: String? = nil,
        credentials: DiscogsCredentials?
    ) async throws -> CollectionReleasesResponse {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        if let sort {
            items.append(URLQueryItem(name: "sort", value: sort))
        }
        if let sortOrder {
            items.append(URLQueryItem(name: "sort_order", value: sortOrder))
        }
        return try await request(
            path: "users/\(username)/collection/folders/\(folderId)/releases",
            queryItems: items,
            credentials: credentials
        )
    }

    /// Parcourt toutes les pages d'un dossier et retourne l'ensemble des éléments d'un coup —
    /// chaque page passe par le throttle du client, donc reste sûr même pour une grosse
    /// collection. Réservé aux besoins ponctuels de calcul (stats...) : les écrans de liste
    /// doivent eux rester en pagination paresseuse (voir `CollectionViewModel`).
    func fetchAllCollectionItems(
        username: String,
        folderId: Int,
        sort: String? = nil,
        sortOrder: String? = nil,
        credentials: DiscogsCredentials?
    ) async throws -> [CollectionItem] {
        var page = 1
        var totalPages = 1
        var all: [CollectionItem] = []
        while page <= totalPages {
            let response = try await collectionItems(
                username: username, folderId: folderId, page: page, sort: sort, sortOrder: sortOrder, credentials: credentials
            )
            totalPages = response.pagination.pages
            all.append(contentsOf: response.releases)
            page += 1
        }
        return all
    }

    func collectionFields(username: String, credentials: DiscogsCredentials?) async throws -> CollectionFieldsResponse {
        try await request(path: "users/\(username)/collection/fields", credentials: credentials)
    }

    @discardableResult
    func updateCollectionField(
        username: String,
        folderId: Int,
        releaseId: Int,
        instanceId: Int,
        fieldId: Int,
        value: String,
        credentials: DiscogsCredentials
    ) async throws -> Bool {
        struct FieldPayload: Encodable {
            let value: String
        }
        let bodyData = try JSONEncoder().encode(FieldPayload(value: value))
        let targetFolderId = folderId > 0 ? folderId : 0
        return try await requestVoid(
            path: "users/\(username)/collection/folders/\(targetFolderId)/releases/\(releaseId)/instances/\(instanceId)/fields/\(fieldId)",
            method: "POST",
            body: bodyData,
            credentials: credentials
        )
    }

    @discardableResult
    func updateCollectionRating(
        username: String,
        folderId: Int,
        releaseId: Int,
        instanceId: Int,
        rating: Int,
        credentials: DiscogsCredentials
    ) async throws -> Bool {
        struct RatingPayload: Encodable {
            let rating: Int
        }
        let bodyData = try JSONEncoder().encode(RatingPayload(rating: rating))
        let targetFolderId = folderId > 0 ? folderId : 0
        return try await requestVoid(
            path: "users/\(username)/collection/folders/\(targetFolderId)/releases/\(releaseId)/instances/\(instanceId)",
            method: "POST",
            body: bodyData,
            credentials: credentials
        )
    }

    /// Déplace un exemplaire vers un autre dossier. Même point d'entrée que
    /// `updateCollectionRating` (Discogs y traite rating et dossier indifféremment) : seul le
    /// corps JSON change.
    @discardableResult
    func moveCollectionInstance(
        username: String,
        folderId: Int,
        releaseId: Int,
        instanceId: Int,
        toFolderId: Int,
        credentials: DiscogsCredentials
    ) async throws -> Bool {
        struct MovePayload: Encodable {
            let folderId: Int
            private enum CodingKeys: String, CodingKey {
                case folderId = "folder_id"
            }
        }
        let bodyData = try JSONEncoder().encode(MovePayload(folderId: toFolderId))
        let targetFolderId = folderId > 0 ? folderId : 0
        return try await requestVoid(
            path: "users/\(username)/collection/folders/\(targetFolderId)/releases/\(releaseId)/instances/\(instanceId)",
            method: "POST",
            body: bodyData,
            credentials: credentials
        )
    }

    @discardableResult
    func addToCollection(
        username: String,
        folderId: Int,
        releaseId: Int,
        credentials: DiscogsCredentials
    ) async throws -> AddToCollectionResponse {
        try await request(
            path: "users/\(username)/collection/folders/\(folderId)/releases/\(releaseId)",
            method: "POST",
            credentials: credentials
        )
    }

    @discardableResult
    func removeFromCollection(
        username: String,
        folderId: Int,
        releaseId: Int,
        instanceId: Int,
        credentials: DiscogsCredentials
    ) async throws -> Bool {
        try await requestVoid(
            path: "users/\(username)/collection/folders/\(folderId)/releases/\(releaseId)/instances/\(instanceId)",
            method: "DELETE",
            credentials: credentials
        )
    }

    // MARK: - Wantlist

    func wantlist(
        username: String,
        page: Int = 1,
        perPage: Int = DiscogsConstants.maxPageSize,
        sort: String? = nil,
        sortOrder: String? = nil,
        credentials: DiscogsCredentials?
    ) async throws -> WantlistResponse {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        if let sort {
            items.append(URLQueryItem(name: "sort", value: sort))
        }
        if let sortOrder {
            items.append(URLQueryItem(name: "sort_order", value: sortOrder))
        }
        return try await request(
            path: "users/\(username)/wants",
            queryItems: items,
            credentials: credentials
        )
    }

    /// Récupère un item précis de la wantlist (répond 404 s'il n'y est pas), pour savoir si
    /// l'utilisateur souhaite déjà cette release.
    func wantlistItem(username: String, releaseId: Int, credentials: DiscogsCredentials) async throws -> WantlistItem {
        try await request(path: "users/\(username)/wants/\(releaseId)", credentials: credentials)
    }

    @discardableResult
    func addToWantlist(username: String, releaseId: Int, credentials: DiscogsCredentials) async throws -> Bool {
        try await requestVoid(path: "users/\(username)/wants/\(releaseId)", method: "PUT", credentials: credentials)
    }

    @discardableResult
    func removeFromWantlist(username: String, releaseId: Int, credentials: DiscogsCredentials) async throws -> Bool {
        try await requestVoid(path: "users/\(username)/wants/\(releaseId)", method: "DELETE", credentials: credentials)
    }

}
