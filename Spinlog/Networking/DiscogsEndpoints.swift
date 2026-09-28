import Foundation

/// Endpoints Discogs utilisés par l'app, au-dessus du client HTTP générique.
/// Référence : https://www.discogs.com/developers
extension DiscogsAPIClient {
    func search(
        query: String,
        type: String? = nil,
        page: Int = 1,
        credentials: DiscogsCredentials? = nil
    ) async throws -> SearchResponse {
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "page", value: String(page))]
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

    func artist(id: Int, credentials: DiscogsCredentials? = nil) async throws -> Artist {
        try await request(path: "artists/\(id)", credentials: credentials)
    }

    // MARK: - Collection

    func collectionFolders(username: String, credentials: DiscogsCredentials?) async throws -> CollectionFoldersResponse {
        try await request(path: "users/\(username)/collection/folders", credentials: credentials)
    }

    func collectionItems(
        username: String,
        folderId: Int,
        page: Int = 1,
        credentials: DiscogsCredentials?
    ) async throws -> CollectionReleasesResponse {
        try await request(
            path: "users/\(username)/collection/folders/\(folderId)/releases",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: "50")],
            credentials: credentials
        )
    }

    @discardableResult
    func addToCollection(
        username: String,
        folderId: Int,
        releaseId: Int,
        credentials: DiscogsCredentials
    ) async throws -> Bool {
        try await requestVoid(
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

    func wantlist(username: String, page: Int = 1, credentials: DiscogsCredentials?) async throws -> WantlistResponse {
        try await request(
            path: "users/\(username)/wants",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: "50")],
            credentials: credentials
        )
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
