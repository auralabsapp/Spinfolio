import Foundation

/// Pilote l'import des prix d'achat et états du disque depuis des champs personnalisés Discogs
/// (« Importer depuis Discogs », page Suivi de plus-value) : relecture de la collection, analyse
/// sans écriture (`CopyDetailsImport.plan`), puis écriture ou annulation. La règle de lecture et de
/// conflit vit dans `CopyDetailsImport` ; ici seulement l'enchaînement, le réseau et les gardes.
@Observable
@MainActor
final class CopyDetailsImportViewModel {
    enum Phase {
        case idle
        case loading
        case ready
        case applying
    }

    private(set) var phase = Phase.idle
    private(set) var plan: CopyDetailsImport.Plan?
    /// Message d'un résultat ou d'un refus ; affiché par `messageAlert`.
    var message: String?
    private(set) var fields: [CollectionField] = []

    var priceFieldId: Int?
    var conditionFieldId: Int?
    var unspecifiedCurrency: String
    var replacesExisting = false

    private let authManager = DiscogsAuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let store = CopyDetailsStore.shared
    /// Exemplaires lus pour l'analyse en cours, gardés pour recalculer l'aperçu quand la devise change.
    private var items: [CollectionItem] = []
    /// Compte pour lequel l'aperçu a été calculé : un import n'est jamais écrit sur un autre.
    private var planUsername: String?
    private var analysisTask: Task<Void, Never>?

    var isDemo: Bool { DemoMode.isActive }
    var hasFieldChosen: Bool { priceFieldId != nil || conditionFieldId != nil }
    var canUndo: Bool { store.lastImport != nil }
    var lastImportDate: Date? { store.lastImport?.date }

    init() {
        let username = DiscogsAuthManager.shared.username
        unspecifiedCurrency = username.map { CollectionPreferencesStore.defaultCurrency(for: $0) } ?? "EUR"
        if let username {
            priceFieldId = CollectionPreferencesStore.purchasePriceFieldId(for: username)
            conditionFieldId = CollectionPreferencesStore.mediaConditionFieldId(for: username)
        }
    }

    func loadFields() async {
        guard let username = authManager.username, networkMonitor.isConnected else { return }
        let loaded = await CollectionFieldsService.fields(username: username, credentials: authManager.credentials)
        guard authManager.username == username, !loaded.isEmpty else { return }
        fields = loaded
    }

    /// Les champs ou la devise changent : l'aperçu affiché ne correspond plus.
    func invalidatePreview() {
        analysisTask?.cancel()
        plan = nil
        replacesExisting = false
        if phase != .applying { phase = .idle }
    }

    /// Devise changée après l'analyse : seul le plan est recalculé, sans relire la collection.
    func recomputePlan() {
        guard phase == .ready, let username = authManager.username else { return }
        plan = makePlan(username: username)
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
    }

    // MARK: - Analyse

    func analyze() {
        guard !isDemo else {
            message = AppMessages.demoModificationBlocked
            return
        }
        guard hasFieldChosen, let username = authManager.username, authManager.isAuthenticated else { return }
        analysisTask?.cancel()
        phase = .loading
        plan = nil
        replacesExisting = false
        analysisTask = Task { [weak self] in
            await self?.runAnalysis(username: username)
        }
    }

    private func runAnalysis(username: String) async {
        let fetched = await FreshCollectionLoader.loadAll(username: username)
        // Compte changé, écran quitté ou analyse relancée pendant la lecture : rien n'est appliqué.
        guard !Task.isCancelled, authManager.username == username else {
            if authManager.username != username { phase = .idle }
            return
        }
        guard let fetched else {
            phase = .idle
            message = String(localized: "Ta collection n'a pas pu être relue et les données gardées sur l'appareil datent de plus de 6 heures. Reconnecte-toi à Internet puis réessaie.")
            return
        }
        // Un champ disparu de Discogs pendant ce temps : on ne devine pas, on s'arrête.
        if !fields.isEmpty {
            let known = Set(fields.map(\.id))
            let chosen = [priceFieldId, conditionFieldId].compactMap { $0 }
            if chosen.contains(where: { !known.contains($0) }) {
                phase = .idle
                message = String(localized: "Un des champs choisis n'existe plus sur Discogs. Choisis-le de nouveau.")
                return
            }
        }
        items = fetched
        planUsername = username
        plan = makePlan(username: username)
        phase = .ready
    }

    private func makePlan(username: String) -> CopyDetailsImport.Plan {
        CopyDetailsImport.plan(
            items: items,
            priceFieldId: priceFieldId,
            conditionFieldId: conditionFieldId,
            unspecifiedCurrency: unspecifiedCurrency,
            existing: { [store] in store.details(for: $0) }
        )
    }

    // MARK: - Écriture

    var operationCount: Int {
        plan?.operations(replacing: replacesExisting).count ?? 0
    }

    func applyImport() {
        guard !isDemo else {
            message = AppMessages.demoModificationBlocked
            return
        }
        guard phase == .ready, let plan, let planUsername, authManager.username == planUsername else {
            invalidatePreview()
            return
        }
        phase = .applying
        let count = store.applyImport(plan.operations(replacing: replacesExisting))
        self.plan = nil
        replacesExisting = false
        phase = .idle
        message = count == 0
            ? String(localized: "Aucune valeur à importer.")
            : String(localized: "\(count) exemplaires mis à jour. Tu peux annuler cet import depuis cette page.")
    }

    func undoImport() {
        let restored = store.undoLastImport()
        message = String(localized: "\(restored) exemplaires remis dans leur état d'avant l'import.")
    }
}
