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
            if let match = response.results.first(where: \.isRelease) {
                items[index].status = .found(match)
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
            addProgressText = "Ajout en collection (\(count)/\(targets.count))\u{2026}"
            let actions = ReleaseActions()
            await actions.addToCollection(releaseId: result.id, targetFolderId: folderId)
            try? await Task.sleep(for: .milliseconds(600))
        }
        let targetIds = Set(targets.map(\.id))
        items.removeAll { targetIds.contains($0.id) }
        addProgressText = nil
        isAdding = false
        message = count == 1 ? "1 disque ajouté à la collection." : "\(count) disques ajoutés à la collection."
    }

    func addSelectedToWantlist() async {
        let targets = selectedFoundItems
        guard !targets.isEmpty else { return }
        isAdding = true
        var count = 0
        for target in targets {
            guard case let .found(result) = target.status else { continue }
            count += 1
            addProgressText = "Ajout en wantlist (\(count)/\(targets.count))\u{2026}"
            let actions = ReleaseActions()
            await actions.addToWantlist(releaseId: result.id)
            try? await Task.sleep(for: .milliseconds(600))
        }
        let targetIds = Set(targets.map(\.id))
        items.removeAll { targetIds.contains($0.id) }
        addProgressText = nil
        isAdding = false
        message = count == 1 ? "1 disque ajouté à la wantlist." : "\(count) disques ajoutés à la wantlist."
    }
}
