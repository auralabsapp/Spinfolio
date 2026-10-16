import Foundation

/// Classe en tâche de fond, pendant que l'app est ouverte, les discographies Discogs de tous les
/// artistes de la collection et de la wantlist (sections Albums, Singles & EP… de
/// `ArtistDetailView`) : à l'ouverture d'une page artiste, ses œuvres sont alors déjà rangées.
///
/// Discret par construction :
/// - toutes ses requêtes sont de priorité `.background` (voir `DiscogsRateLimiter`) : elles
///   attendent quelques secondes sans autre requête Discogs, n'utilisent jamais plus de la
///   moitié du quota et partent au plus toutes les 3 secondes. Une action de l'utilisateur, la
///   synchro de la collection ou la résolution des années originales passent donc toujours
///   avant ;
/// - uniquement en Wi-Fi (réseau non « coûteux »), hors mode économie d'énergie ;
/// - suspendu dès que l'app passe en arrière-plan, repris au retour au premier plan.
///
/// Les artistes les plus présents dans la collection passent en premier ; « Various » (les
/// compilations multi-artistes) est ignoré. Un artiste traité jusqu'au bout n'est revu qu'au
/// bout de 30 jours (nouvelles sorties) ; ses masters déjà classés ne coûtent alors plus rien.
/// Seul le classement est conservé (voir `DiscogsWorkCategoryCache`), jamais les listes Discogs.
@MainActor
final class DiscogsCategoryBackfillService {
    static let shared = DiscogsCategoryBackfillService()

    private let processedStorageKey = "discogsCategoryBackfillProcessedArtists"
    /// Identifiant Discogs de l'artiste « Various ».
    private let variousArtistId = 194
    private let revisitInterval: TimeInterval = 30 * 24 * 3600
    /// Même plafond que la page artiste : au-delà, les entrées brutes d'un artiste prolifique
    /// ne seraient de toute façon pas affichées.
    private let maxDiscographyPages = 10
    /// Laisse la synchro de la collection et la résolution des années démarrer d'abord.
    private let startDelay: Duration = .seconds(20)

    private var worker: Task<Void, Never>?
    /// Distingue les exécutions successives : une exécution annulée qui se termine après le
    /// démarrage de la suivante ne doit pas effacer la référence à celle-ci.
    private var generation = 0

    private init() {}

    /// À appeler à chaque passage au premier plan.
    func start() {
        guard worker == nil, DiscogsAuthManager.shared.isAuthenticated else { return }
        generation += 1
        let current = generation
        worker = Task { [weak self] in
            // Sans ce `@TaskLocal`, ces requêtes de fond consommaient le quota Discogs à la même
            // priorité qu'une ouverture de fiche release par l'utilisateur (voir le même
            // correctif sur `CollectionViewModel.startBackgroundSync`).
            await DiscogsRateLimiter.$priority.withValue(.background) {
                await self?.run()
            }
            if self?.generation == current {
                self?.worker = nil
            }
        }
    }

    /// À appeler au passage en arrière-plan.
    func stop() {
        worker?.cancel()
        worker = nil
        DiscogsWorkCategoryCache.shared.flush(forceSync: true)
    }

    private func run() async {
        do {
            try await Task.sleep(for: startDelay)
        } catch {
            return
        }
        let artists = await libraryArtists()
        var processed = loadProcessed()
        let now = Date()
        let toProcess = artists.filter { artist in
            guard let date = processed[String(artist.id)] else { return true }
            return now.timeIntervalSince(date) >= revisitInterval
        }

        await DiscogsRateLimiter.$priority.withValue(.background) {
            for artist in toProcess {
                guard await waitUntilAllowed() else { return }
                if await classifyDiscography(of: artist) {
                    processed[String(artist.id)] = Date()
                    saveProcessed(processed)
                }
                DiscogsWorkCategoryCache.shared.flush()
            }
        }
        DiscogsWorkCategoryCache.shared.flush()
    }

    /// Classe les masters pas encore classés d'un artiste. `false` si le travail s'est arrêté
    /// avant la fin (annulation, réseau, erreur) : l'artiste sera repris à la prochaine ouverture.
    private func classifyDiscography(of artist: LibraryArtist) async -> Bool {
        let credentials = DiscogsAuthManager.shared.credentials
        var rawItems: [ArtistReleaseItem] = []
        var page = 1
        var totalPages = 1
        while page <= min(totalPages, maxDiscographyPages) {
            guard await waitUntilAllowed() else { return false }
            do {
                let response = try await DiscogsAPIClient.shared.artistReleases(
                    artistId: artist.id,
                    page: page,
                    credentials: credentials
                )
                totalPages = response.pagination.pages
                rawItems += response.releases
                page += 1
            } catch {
                return false
            }
        }

        let cache = DiscogsWorkCategoryCache.shared
        let pending = DiscogsDiscography.mainWorks(from: rawItems)
            .filter { $0.kind == .master && cache.category(forMasterId: $0.discogsId) == nil }
            .map { DiscogsWorkClassifier.PendingMaster(masterId: $0.discogsId, mainRelease: $0.mainRelease) }
        guard !pending.isEmpty else { return true }
        guard await waitUntilAllowed() else { return false }
        return await DiscogsWorkClassifier.classify(pending, artistName: artist.name) { _, _ in }
    }

    /// Attend que les conditions soient réunies (Wi-Fi, pas d'économie d'énergie, connecté à
    /// Discogs), en revérifiant toutes les 30 secondes. `false` si la tâche a été annulée.
    private func waitUntilAllowed() async -> Bool {
        while !Task.isCancelled {
            let network = NetworkMonitor.shared
            if !DiscogsAuthManager.shared.isAuthenticated { return false }
            if network.isConnected, !network.isExpensive, !ProcessInfo.processInfo.isLowPowerModeEnabled {
                return true
            }
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return false
            }
        }
        return false
    }

    // MARK: - Artistes de la bibliothèque

    struct LibraryArtist: Sendable {
        let id: Int
        let name: String
    }

    /// Artistes crédités dans la collection et la wantlist locales, du plus présent au moins
    /// présent. Décodage hors du fil principal (plusieurs centaines de payloads JSON).
    private func libraryArtists() async -> [LibraryArtist] {
        guard let username = DiscogsAuthManager.shared.username else { return [] }
        let payloads = LocalDataStore.shared.collectionPayloads(username: username)
            + LocalDataStore.shared.wantlistPayloads(username: username)
        let variousArtistId = variousArtistId
        return await Task.detached(priority: .utility) {
            let decoder = JSONDecoder()
            var counts: [Int: Int] = [:]
            var names: [Int: String] = [:]
            for payload in payloads {
                guard let entry = try? decoder.decode(LibraryArtistsPayload.self, from: payload) else { continue }
                for artist in entry.basicInformation.artists ?? [] where artist.id > 0 && artist.id != variousArtistId {
                    counts[artist.id, default: 0] += 1
                    names[artist.id] = artist.name
                }
            }
            return counts
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .compactMap { id, _ in names[id].map { LibraryArtist(id: id, name: $0) } }
        }.value
    }

    private func loadProcessed() -> [String: Date] {
        let stored = UserDefaults.standard.dictionary(forKey: processedStorageKey) as? [String: Double] ?? [:]
        return stored.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func saveProcessed(_ processed: [String: Date]) {
        UserDefaults.standard.set(processed.mapValues(\.timeIntervalSince1970), forKey: processedStorageKey)
    }
}

/// Entrée de collection ou de wantlist réduite à ses artistes crédités.
nonisolated private struct LibraryArtistsPayload: Decodable, Sendable {
    nonisolated struct Info: Decodable, Sendable {
        nonisolated struct ArtistRef: Decodable, Sendable {
            let id: Int
            let name: String
        }
        let artists: [ArtistRef]?
    }
    let basicInformation: Info

    private enum CodingKeys: String, CodingKey {
        case basicInformation = "basic_information"
    }
}
