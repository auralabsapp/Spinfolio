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
@Observable
@MainActor
final class BatchScanViewModel {
    private(set) var items: [BatchScanItem] = []
    private(set) var isAdding = false
    var addProgressText: String?
    var message: String?

    private let membership = LibraryMembershipStore.shared

    func scan(code: String) {
        guard !items.contains(where: { $0.code == code }) else { return }
        items.append(BatchScanItem(code: code, status: .resolving))
        Task { await resolve(code: code) }
    }

    private func resolve(code: String) async {
        do {
            let response = try await DiscogsAPIClient.shared.searchByBarcode(
                code, credentials: DiscogsAuthManager.shared.credentials
            )
            guard let index = items.firstIndex(where: { $0.code == code }) else { return }
            let releases = response.results.filter(\.isRelease)
            if let first = releases.first {
                items[index].status = .found(first)
                items[index].alternatives = releases
            } else {
                items[index].status = .notFound
            }
        } catch {
            guard let index = items.firstIndex(where: { $0.code == code }) else { return }
            items[index].status = .notFound
        }
    }

    func remove(_ item: BatchScanItem) {
        items.removeAll { $0.id == item.id }
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
        let targets = selectedFoundItems
        guard !targets.isEmpty else { return }
        isAdding = true
        var count = 0
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
        }
        let targetIds = Set(targets.map(\.id))
        items.removeAll { targetIds.contains($0.id) }
        addProgressText = nil
        isAdding = false
        message = String(localized: "\(count) disques ajoutés à la collection.")
    }

    func addSelectedToWantlist() async {
        let targets = selectedFoundItems
        guard !targets.isEmpty else { return }
        isAdding = true
        var count = 0
        for target in targets {
            guard case let .found(result) = target.status else { continue }
            count += 1
            addProgressText = String(localized: "Ajout en wantlist (\(count)/\(targets.count))…")
            let actions = ReleaseActions()
            let release = try? await DiscogsAPIClient.shared.release(id: result.id, credentials: DiscogsAuthManager.shared.credentials)
            await actions.addToWantlist(releaseId: result.id, release: release)
        }
        let targetIds = Set(targets.map(\.id))
        items.removeAll { targetIds.contains($0.id) }
        addProgressText = nil
        isAdding = false
        message = String(localized: "\(count) disques ajoutés à la wantlist.")
    }
}
