import Foundation
import Observation

enum BatchScanItemStatus: Equatable {
    case resolving
    case found(SearchResult)
    case notFound

    static func == (lhs: BatchScanItemStatus, rhs: BatchScanItemStatus) -> Bool {
        switch (lhs, rhs) {
        case (.resolving, .resolving), (.notFound, .notFound):
            return true
        case let (.found(a), .found(b)):
            return a.id == b.id
        default:
            return false
        }
    }
}

struct BatchScanItem: Identifiable {
    var id: String { code }
    let code: String
    var status: BatchScanItemStatus
    /// Tous les pressages Discogs partageant ce code-barres (un même code-barres correspond
    /// souvent à plusieurs pressages/rééditions) : `status` retient celui actuellement
    /// sélectionné pour l'ajout, mais l'utilisateur peut en choisir un autre depuis cette liste.
    var alternatives: [SearchResult] = []
    var isSelected = true
}

/// État du scan par lot (fonctionnalité premium) : accumule les codes-barres scannés en
/// continu, résout chacun via l'API Discogs, puis permet un ajout groupé en collection ou
/// en wantlist. Réutilise `ReleaseActions` par élément pour bénéficier gratuitement de la
/// mise à jour optimiste et de la mise en file hors ligne déjà gérées là-bas.
///
/// Les codes scannés (et le pressage retenu pour chacun) sont enregistrés au fil de l'eau : fermer
/// l'écran, perdre le réseau ou voir l'app tuée par le système ne fait plus perdre une session
/// de scan en brocante. Ils sont retrouvés à la prochaine ouverture, jusqu'à leur ajout ou leur
/// suppression explicite.
@Observable
@MainActor
final class BatchScanViewModel {
    private(set) var items: [BatchScanItem] = [] {
        didSet { persistDraft() }
    }
    private(set) var isAdding = false
    var addProgressText: String?
    var message: String?
    /// Onglet où mener l'utilisateur une fois le bilan de l'ajout acquitté (`nil` : rien d'ajouté).
    private(set) var destinationAfterAdd: AppTab?
    /// Disques tout juste ajoutés en ligne, dont le prix d'achat et l'état peuvent être renseignés
    /// tout de suite : `nil` si rien à proposer (rien d'ajouté, ajouts en attente du réseau, ou
    /// aucun des deux champs configuré dans Réglages).
    private(set) var completionOffer: BatchCompletionRequest?

    private let membership = LibraryMembershipStore.shared
    /// Codes dont la recherche a échoué faute de réseau : relancés au retour de la connexion.
    private var pendingLookups: Set<String> = []
    @ObservationIgnored nonisolated(unsafe) private var networkObserver: NSObjectProtocol?

    /// Version enregistrée d'un code scanné : le résultat Discogs n'est pas stocké, il est
    /// simplement recherché de nouveau à la restauration.
    private struct DraftEntry: Codable {
        let code: String
        let isSelected: Bool
        let selectedReleaseId: Int?
    }

    private var draftKey: String? {
        DiscogsAuthManager.shared.username.map(Self.draftKey(for:))
    }

    nonisolated static func draftKey(for username: String) -> String {
        "batchScanDraft_\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    /// Suppression des données (ou sortie de la démo) : le brouillon du compte ne doit pas rester.
    static func clearDraft(for username: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: draftKey(for: username))
    }

    init() {
        restoreDraft()
        networkObserver = addLibraryObserver(for: .networkConnectionRestored) { [weak self] in
            self?.retryPendingLookups()
        }
    }

    deinit {
        if let networkObserver {
            NotificationCenter.default.removeObserver(networkObserver)
        }
    }

    func scan(code: String) {
        guard !items.contains(where: { $0.code == code }) else { return }
        items.append(BatchScanItem(code: code, status: .resolving))
        Task { await resolve(code: code) }
    }

    /// Supprime tous les codes scannés, y compris leur copie enregistrée.
    func clearAll() {
        items.removeAll()
        pendingLookups.removeAll()
    }

    private func resolve(code: String, preferredReleaseId: Int? = nil) async {
        do {
            let response = try await DiscogsAPIClient.shared.searchByBarcode(
                code, credentials: DiscogsAuthManager.shared.credentials
            )
            pendingLookups.remove(code)
            guard let index = items.firstIndex(where: { $0.code == code }) else { return }
            let releases = response.results.filter(\.isRelease)
            if let first = releases.first {
                let preferred = preferredReleaseId.flatMap { id in releases.first { $0.id == id } }
                items[index].status = .found(preferred ?? first)
                items[index].alternatives = releases
            } else {
                items[index].status = .notFound
            }
        } catch where error.isTransientNetworkFailure {
            // Pas de réseau (ou Discogs indisponible) : le code n'est pas « introuvable », sa
            // recherche est juste reportée. Il reste affiché en cours de recherche.
            pendingLookups.insert(code)
        } catch {
            guard let index = items.firstIndex(where: { $0.code == code }) else { return }
            items[index].status = .notFound
        }
    }

    private func retryPendingLookups() {
        let codes = pendingLookups
        for code in codes {
            let preferred = draftSelectedReleaseIds[code]
            Task { await resolve(code: code, preferredReleaseId: preferred) }
        }
    }

    // MARK: - Brouillon enregistré

    /// Pressages choisis à la main avant la restauration, à réappliquer une fois les codes
    /// recherchés de nouveau.
    private var draftSelectedReleaseIds: [String: Int] = [:]

    private func persistDraft() {
        guard let draftKey else { return }
        guard !items.isEmpty else {
            UserDefaults.standard.removeObject(forKey: draftKey)
            return
        }
        let entries = items.map { item in
            let releaseId: Int?
            if case let .found(result) = item.status {
                releaseId = result.id
            } else {
                releaseId = draftSelectedReleaseIds[item.code]
            }
            return DraftEntry(code: item.code, isSelected: item.isSelected, selectedReleaseId: releaseId)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: draftKey)
        }
    }

    private func restoreDraft() {
        guard let draftKey,
              let data = UserDefaults.standard.data(forKey: draftKey),
              let entries = try? JSONDecoder().decode([DraftEntry].self, from: data),
              !entries.isEmpty else { return }
        draftSelectedReleaseIds = Dictionary(
            entries.compactMap { entry in entry.selectedReleaseId.map { (entry.code, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        items = entries.map { BatchScanItem(code: $0.code, status: .resolving, isSelected: $0.isSelected) }
        for entry in entries {
            Task { await resolve(code: entry.code, preferredReleaseId: entry.selectedReleaseId) }
        }
    }

    func remove(_ item: BatchScanItem) {
        items.removeAll { $0.id == item.id }
    }

    /// Codes à traiter (en cours de recherche ou reconnus) : ceux que compte « Terminer ».
    var pendingItems: [BatchScanItem] {
        items.filter { $0.status != .notFound }
    }

    /// Codes sans disque trouvé : conservés tant que l'utilisateur ne les retire pas.
    var unrecognizedItems: [BatchScanItem] {
        items.filter { $0.status == .notFound }
    }

    /// Relance la recherche d'un code non reconnu (échec passager, code mal lu puis rescanné…).
    func retry(_ item: BatchScanItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }), items[index].status == .notFound else { return }
        items[index].status = .resolving
        let code = item.code
        Task { await resolve(code: code) }
    }

    func toggleSelection(_ item: BatchScanItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isSelected.toggle()
    }

    /// Change le pressage retenu pour ce code-barres parmi les alternatives détectées (même
    /// code-barres partagé par plusieurs éditions/rééditions).
    func selectMatch(_ result: SearchResult, for item: BatchScanItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].status = .found(result)
    }

    func isAlreadyInCollection(_ item: BatchScanItem) -> Bool {
        guard case let .found(result) = item.status else { return false }
        return membership.isInCollection(result.id)
    }

    func isAlreadyInWantlist(_ item: BatchScanItem) -> Bool {
        guard case let .found(result) = item.status else { return false }
        return membership.isInWantlist(result.id)
    }

    var selectedFoundItems: [BatchScanItem] {
        items.filter { item in
            guard item.isSelected, case .found = item.status else { return false }
            return true
        }
    }

    // MARK: - Actions groupées

    func addSelectedToCollection(folderId: Int?) async {
        if DemoMode.isActive {
            message = AppMessages.demoAddBlocked
            return
        }
        let targets = selectedFoundItems
        guard !targets.isEmpty else { return }
        isAdding = true
        var count = 0
        var queuedCount = 0
        var failedIds: Set<BatchScanItem.ID> = []
        var addedItems: [CollectionItem] = []
        completionOffer = nil
        for target in targets {
            guard case let .found(result) = target.status else { continue }
            count += 1
            addProgressText = String(localized: "Ajout en collection (\(count)/\(targets.count))…")
            let actions = ReleaseActions()
            // Sans l'objet `Release`, `addToCollection` ne notifie pas les onglets Collection/
            // Wantlist (voir `ReleaseActions.addToCollection`) : la liste ne se met alors pas à
            // jour tant que l'utilisateur ne recharge pas manuellement.
            let release = try? await DiscogsAPIClient.shared.release(id: result.id, credentials: DiscogsAuthManager.shared.credentials)
            await actions.addToCollection(releaseId: result.id, release: release, targetFolderId: folderId)
            switch Self.addOutcome(forActionMessage: actions.message, isOffline: !NetworkMonitor.shared.isConnected) {
            case .added:
                // Identifiant définitif seulement : un ajout en file n'a qu'un identifiant temporaire,
                // sur lequel une écriture de champ ne pourrait pas être rejouée.
                if let item = actions.collectionInstances.last, item.instanceId > 0 { addedItems.append(item) }
            case .queued: queuedCount += 1
            case .failed: failedIds.insert(target.id)
            }
        }
        // Les codes dont l'ajout a échoué restent dans la liste, pour pouvoir réessayer.
        let targetIds = Set(targets.map(\.id)).subtracting(failedIds)
        items.removeAll { targetIds.contains($0.id) }
        addProgressText = nil
        isAdding = false
        let addedCount = count - failedIds.count
        message = String(localized: "\(addedCount) albums ajoutés à la collection.")
        destinationAfterAdd = addedCount > 0 ? .collection : nil
        appendOutcomeDetails(queuedCount: queuedCount, failedCount: failedIds.count, purgedCount: purgeUnrecognizedIfFinished())
        offerCompletion(for: addedItems)
    }

    /// Propose de renseigner tout de suite prix d'achat et état des disques ajoutés (voir
    /// `BatchCompletionSheet`) : la question est ajoutée au bilan, dont l'alerte porte alors deux
    /// boutons. Rien n'est proposé si aucun des deux champs n'est configuré.
    private func offerCompletion(for added: [CollectionItem]) {
        guard !added.isEmpty, let username = DiscogsAuthManager.shared.username else { return }
        let question: String
        switch BatchCompletion.configuredFields(for: username) {
        case []: return
        case [.purchasePrice]: question = String(localized: "Renseigner le prix d'achat maintenant ?")
        case [.mediaCondition]: question = String(localized: "Renseigner l'état du média maintenant ?")
        default: question = String(localized: "Renseigner prix et état maintenant ?")
        }
        completionOffer = BatchCompletionRequest(items: added, username: username)
        message = ([message].compactMap { $0 } + [question]).joined(separator: "\n\n")
    }

    /// Prend la proposition en cours (acceptée ou refusée : elle ne se représente pas).
    func takeCompletionOffer() -> BatchCompletionRequest? {
        defer { completionOffer = nil }
        return completionOffer
    }

    func addSelectedToWantlist() async {
        if DemoMode.isActive {
            message = AppMessages.demoAddBlocked
            return
        }
        let targets = selectedFoundItems
        guard !targets.isEmpty else { return }
        isAdding = true
        var count = 0
        var queuedCount = 0
        var failedIds: Set<BatchScanItem.ID> = []
        for target in targets {
            guard case let .found(result) = target.status else { continue }
            count += 1
            addProgressText = String(localized: "Ajout en wantlist (\(count)/\(targets.count))…")
            let actions = ReleaseActions()
            let release = try? await DiscogsAPIClient.shared.release(id: result.id, credentials: DiscogsAuthManager.shared.credentials)
            await actions.addToWantlist(releaseId: result.id, release: release)
            switch Self.addOutcome(forActionMessage: actions.message, isOffline: !NetworkMonitor.shared.isConnected) {
            case .added: break
            case .queued: queuedCount += 1
            case .failed: failedIds.insert(target.id)
            }
        }
        // Les codes dont l'ajout a échoué restent dans la liste, pour pouvoir réessayer.
        let targetIds = Set(targets.map(\.id)).subtracting(failedIds)
        items.removeAll { targetIds.contains($0.id) }
        addProgressText = nil
        isAdding = false
        let addedCount = count - failedIds.count
        message = String(localized: "\(addedCount) albums ajoutés à la wantlist.")
        destinationAfterAdd = addedCount > 0 ? .wantlist : nil
        appendOutcomeDetails(queuedCount: queuedCount, failedCount: failedIds.count, purgedCount: purgeUnrecognizedIfFinished())
    }

    // MARK: - Bilan des ajouts groupés

    /// Issue d'un ajout, déduite du message laissé par `ReleaseActions` (`nil` = réussi). Le bilan
    /// annonçait auparavant « N disques ajoutés » même quand des ajouts avaient échoué ou
    /// attendaient le retour du réseau, et retirait de la liste les codes en échec.
    enum AddOutcome: Equatable {
        case added
        case queued
        case failed
    }

    /// `isOffline` : hors ligne, un ajout accepté (sans message) est mis en file, pas encore fait.
    nonisolated static func addOutcome(forActionMessage message: String?, isOffline: Bool) -> AddOutcome {
        guard let message else { return isOffline ? .queued : .added }
        if message == AppMessages.discogsUnavailableQueued {
            return .queued
        }
        return .failed
    }

    /// Onglet à ouvrir à la fermeture du bilan : seulement si le lot est terminé (plus aucun code à
    /// traiter ; les codes non reconnus ne comptent pas), sinon l'utilisateur reste sur la revue
    /// pour réessayer ou continuer.
    func takeDestinationAfterAdd() -> AppTab? {
        defer { destinationAfterAdd = nil }
        return pendingItems.isEmpty ? destinationAfterAdd : nil
    }

    /// Lot terminé (plus aucun code reconnu ou en recherche) : les codes non reconnus sont retirés
    /// de la liste, le bilan l'annonce. Tant qu'il reste des codes à traiter, ils sont conservés.
    private func purgeUnrecognizedIfFinished() -> Int {
        guard pendingItems.isEmpty else { return 0 }
        let purgedCount = unrecognizedItems.count
        items.removeAll { $0.status == .notFound }
        return purgedCount
    }

    private func appendOutcomeDetails(queuedCount: Int, failedCount: Int, purgedCount: Int) {
        var details: [String] = []
        if queuedCount > 0 {
            details.append(String(localized: "\(queuedCount) albums en attente de synchronisation avec Discogs."))
        }
        if failedCount > 0 {
            details.append(String(localized: "\(failedCount) albums n'ont pas pu être ajoutés et restent dans la liste."))
        }
        if purgedCount > 0 {
            details.append(String(localized: "\(purgedCount) codes non reconnus retirés de la liste."))
        }
        guard !details.isEmpty else { return }
        message = ([message].compactMap { $0 } + details).joined(separator: "\n")
    }
}
