import Foundation

/// Année originale d'un master Discogs : cache local d'abord, puis Discogs, résultat retenu (0 si
/// Discogs n'en a pas, pour ne pas le redemander). Les vues passent par ici plutôt que d'appeler
/// `DiscogsAPIClient` elles-mêmes.
enum MasterYearLookup {
    /// `nil` si l'année est inconnue (0 chez Discogs) ou si la requête a échoué.
    static func year(for masterId: Int) async -> Int? {
        let store = LocalDataStore.shared
        if store.isMasterResolved(masterId) {
            return store.getMasterYear(for: masterId)
        }
        do {
            let master = try await DiscogsAPIClient.shared.masterRelease(id: masterId, credentials: DiscogsAuthManager.shared.credentials)
            let year = max(master.year ?? 0, 0)
            store.saveMasterYear(year, for: masterId)
            return year > 0 ? year : nil
        } catch {
            // Silencieux : l'année est un complément d'affichage.
            return nil
        }
    }
}
