import Foundation

/// Pilote « Envoyer tout vers Discogs » : relit la collection, calcule ce qui diffère
/// (`CopyDetailsDiscogsSync.plan`), puis écrit valeur par valeur au rythme du limiteur Discogs en
/// priorité de fond. Annulable ; s'arrête dès que Discogs ne répond plus (la valeur en cours est mise
/// en file, les suivantes ne sont pas tentées).
@Observable
@MainActor
final class CopyDetailsDiscogsSyncViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case sending(done: Int, total: Int)
    }

    private(set) var phase = Phase.idle
    private(set) var plan: CopyDetailsDiscogsSync.Plan?
    /// Message d'un résultat ou d'un refus ; affiché par `messageAlert`.
    var message: String?

    private let authManager = DiscogsAuthManager.shared
    private let store = CopyDetailsStore.shared
    private var items: [CollectionItem] = []
    /// Compte pour lequel l'aperçu a été calculé : un envoi n'est jamais fait pour un autre.
    private var planUsername: String?
    private var task: Task<Void, Never>?

    var isDemo: Bool { DemoMode.isActive }
    var isBusy: Bool { phase != .idle && phase != .ready }

    func analyze() {
        guard !isDemo else {
            message = AppMessages.demoModificationBlocked
            return
        }
        guard let username = authManager.username, authManager.isAuthenticated,
              store.mappedPriceFieldId != nil || store.mappedConditionFieldId != nil else { return }
        task?.cancel()
        phase = .loading
        plan = nil
        task = Task { [weak self] in
            await self?.runAnalysis(username: username)
        }
    }

    private func runAnalysis(username: String) async {
        let fetched = await FreshCollectionLoader.loadAll(username: username)
        guard !Task.isCancelled, authManager.username == username else {
            phase = .idle
            return
        }
        guard let fetched else {
            phase = .idle
            message = String(localized: "Ta collection n'a pas pu être relue et les données gardées sur l'appareil datent de plus de 6 heures. Reconnecte-toi à Internet puis réessaie.")
            return
        }
        items = fetched
        planUsername = username
        plan = CopyDetailsDiscogsSync.plan(
            items: fetched,
            details: { [store] in store.details(for: $0) },
            priceFieldId: store.mappedPriceFieldId,
            conditionFieldId: store.mappedConditionFieldId,
            defaultCurrency: CollectionPreferencesStore.defaultCurrency(for: username)
        )
        phase = .ready
    }

    func send() {
        guard !isDemo else {
            message = AppMessages.demoModificationBlocked
            return
        }
        guard phase == .ready, let plan, let username = planUsername, authManager.username == username else {
            phase = .idle
            self.plan = nil
            return
        }
        let operations = plan.operations
        guard !operations.isEmpty else { return }
        let itemsByInstance = Dictionary(items.map { ($0.instanceId, $0) }, uniquingKeysWith: { first, _ in first })
        phase = .sending(done: 0, total: operations.count)
        task = Task { [weak self] in
            await DiscogsRateLimiter.$priority.withValue(.background) {
                await self?.run(operations, itemsByInstance: itemsByInstance, username: username)
            }
        }
    }

    private func run(_ operations: [CopyDetailsDiscogsSync.Operation], itemsByInstance: [Int: CollectionItem], username: String) async {
        var sent = 0
        var refused = 0
        var interrupted = false
        for operation in operations {
            // Compte changé ou annulation : on s'arrête sans rien écrire de plus.
            guard !Task.isCancelled, authManager.username == username, let item = itemsByInstance[operation.instanceId] else {
                interrupted = true
                break
            }
            let outcome = await DiscogsWriteService.updateField(operation.fieldId, value: operation.value, of: item, username: username)
            switch outcome {
            case .done: sent += 1
            case .refused: refused += 1
            case .queuedOffline, .queuedAfterFailure:
                // Discogs ne répond plus : cette valeur repart d'elle-même, les suivantes attendent
                // une nouvelle demande plutôt que d'encombrer la file.
                interrupted = true
            }
            phase = .sending(done: sent + refused, total: operations.count)
            if interrupted { break }
        }
        phase = .idle
        plan = nil
        message = Self.summary(sent: sent, refused: refused, interrupted: interrupted)
    }

    private static func summary(sent: Int, refused: Int, interrupted: Bool) -> String {
        var text = String(localized: "\(sent) valeurs envoyées vers Discogs.")
        if refused > 0 {
            text += " " + String(localized: "\(refused) refusées par Discogs.")
        }
        if interrupted {
            text += " " + String(localized: "L'envoi s'est arrêté avant la fin : relance « Envoyer tout vers Discogs » pour envoyer le reste.")
        }
        return text
    }

    func cancel() {
        task?.cancel()
    }
}
