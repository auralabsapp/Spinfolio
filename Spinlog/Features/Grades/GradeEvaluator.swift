import Foundation

/// Décide quand recompter les disques et les écoutes pour `GradeStore`, et d'où vient le nombre.
///
/// Collection : disques distincts du cache local du dossier « All », mais seulement s'il est
/// complet (au moins autant d'exemplaires que le total annoncé par Discogs) et frais — un cache
/// partiel ou périmé ne doit jamais attribuer ni fêter un grade. Écoutes : le journal d'écoute sur
/// platine (jamais Apple Music), toujours fiable car local.
@MainActor
final class GradeEvaluator {
    static let shared = GradeEvaluator()

    private var observers: [NSObjectProtocol] = []
    private var collectionTask: Task<Void, Never>?
    private var lastCollectionEvaluation: Date?
    /// Délai laissé à l'ajout d'un disque (réseau, écriture dans le cache) avant de recompter.
    private static let afterAdditionDelay: Duration = .seconds(3)
    /// Intervalle minimal entre deux recomptages de routine (retour au premier plan) : décoder tout
    /// le cache d'une grosse collection n'a rien d'anodin.
    private static let routineInterval: TimeInterval = 5 * 60

    private init() {}

    /// À appeler une fois au lancement de l'app : suit les ajouts de disques et les écoutes.
    func start() {
        if observers.isEmpty {
            observers = [
                addLibraryObserver(for: .collectionItemAdded) { [weak self] in
                    self?.evaluateCollection(after: Self.afterAdditionDelay)
                },
                addLibraryObserver(for: .listeningLogChanged) { [weak self] in
                    self?.evaluateListening()
                }
            ]
        }
        // Aussi à chaque connexion (nouvelle valeur de `isAuthenticated`), pas seulement au lancement.
        evaluateListening()
        evaluateCollection()
    }

    /// Recomptage de routine (retour au premier plan), au plus toutes les 5 minutes.
    func evaluateIfDue() {
        evaluateListening()
        if let last = lastCollectionEvaluation, Date().timeIntervalSince(last) < Self.routineInterval { return }
        evaluateCollection()
    }

    func evaluateListening() {
        let sessions = ListeningLogStore.shared.sessions
        GradeStore.shared.evaluate(
            track: .listening,
            count: sessions.count,
            isReliable: true,
            eventDates: sessions.map(\.timestamp)
        )
    }

    /// Recompte la collection depuis le cache local, éventuellement après un délai. Appelé aussi à la
    /// fin d'un chargement complet de la collection (voir `StatsViewModel`).
    func evaluateCollection(after delay: Duration? = nil) {
        collectionTask?.cancel()
        collectionTask = Task { [weak self] in
            if let delay { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            await self.recountCollection()
        }
    }

    private func recountCollection() async {
        guard let username = DiscogsAuthManager.shared.username,
              !DiscogsAuthManager.shared.isDemoMode else { return }
        let localStore = LocalDataStore.shared
        let allFolderId = DiscogsConstants.allFolderId
        let items = await localStore.getCollectionItems(username: username, folderId: allFolderId)
        // Le compte a pu changer pendant le décodage : le résultat ne vaut plus.
        guard !Task.isCancelled, username == DiscogsAuthManager.shared.username else { return }
        lastCollectionEvaluation = Date()

        let announcedTotal = localStore.getFolders(username: username).first { $0.id == allFolderId }?.count
        let isReliable = Self.isCollectionCacheReliable(
            cachedCount: items.count,
            announcedTotal: announcedTotal,
            isStale: localStore.isCollectionStale(username: username, folderId: allFolderId)
        )
        GradeStore.shared.evaluate(
            track: .collection,
            count: Set(items.map(\.releaseId)).count,
            isReliable: isReliable,
            eventDates: Self.firstAdditionDates(of: items)
        )
    }

    /// Une date par disque distinct : celle de son exemplaire le plus ancien (un disque racheté en
    /// plusieurs exemplaires ne compte qu'une fois, à sa première date d'ajout).
    nonisolated static func firstAdditionDates(of items: [CollectionItem]) -> [Date] {
        var earliest: [Int: Date] = [:]
        for item in items {
            guard let date = DiscogsDateParsing.dateAdded(from: item.dateAdded) else { continue }
            if let known = earliest[item.releaseId], known <= date { continue }
            earliest[item.releaseId] = date
        }
        return Array(earliest.values)
    }

    /// Le cache du dossier « All » peut-il décider d'un grade ? Complet (au moins le total annoncé,
    /// connu) et frais. Règle pure, testée à part.
    nonisolated static func isCollectionCacheReliable(cachedCount: Int, announcedTotal: Int?, isStale: Bool) -> Bool {
        guard !isStale, let announcedTotal, announcedTotal > 0 else { return false }
        return cachedCount >= announcedTotal
    }
}
