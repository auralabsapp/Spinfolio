import SwiftUI

/// Statut et actions wantlist d'une release, pour `ReleaseActions` (fiche disque, scan) :
/// mise à jour optimiste du bouton, annulation sur refus définitif, file hors ligne via
/// `DiscogsWriteService`. Les messages et retours haptiques remontent par `report` et
/// `notifyFeedback`, affichés avec ceux de la fiche.
@Observable
@MainActor
final class ReleaseWantlistActions {
    /// Statut wantlist : modifiable instantanément en UI optimiste.
    private(set) var isInWantlist = false

    @ObservationIgnored var report: (String) -> Void = { _ in }
    @ObservationIgnored var notifyFeedback: (LibraryFeedbackEvent.Kind) -> Void = { _ in }

    private let authManager = DiscogsAuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let localStore = LocalDataStore.shared

    /// État immédiat depuis la mémoire et le cache local (0 ms de latence).
    func prepare(releaseId: Int) {
        guard let username = authManager.username else {
            isInWantlist = false
            return
        }
        if LibraryMembershipStore.shared.isInWantlist(releaseId) ||
           localStore.getWantlistItem(username: username, releaseId: releaseId) != nil {
            isInWantlist = true
        }
    }

    /// Vérifie si la release est déjà dans la wantlist : cache local d'abord, puis Discogs.
    func check(releaseId: Int) async {
        guard let username = authManager.username else {
            isInWantlist = false
            return
        }

        // 1. Initialisation immédiate depuis le cache local
        if LibraryMembershipStore.shared.isInWantlist(releaseId) ||
           localStore.getWantlistItem(username: username, releaseId: releaseId) != nil {
            isInWantlist = true
        }

        if !networkMonitor.isConnected {
            return
        }

        guard let credentials = authManager.credentials else { return }

        do {
            _ = try await DiscogsAPIClient.shared.wantlistItem(username: username, releaseId: releaseId, credentials: credentials)
            isInWantlist = true
        } catch {
            // Un 404 est une confirmation explicite et fiable du serveur ("absente de la
            // wantlist") : elle doit l'emporter sur le cache local, qui peut être resté
            // fantôme si sa purge a échoué (voir `LocalDataStore.syncWantlist`). Les autres
            // erreurs (réseau, 5xx...) sont ambiguës : on garde alors l'état local optimiste
            // plutôt que de faire disparaître le bouton à tort sur un simple aléa réseau.
            if case DiscogsAPIClient.APIError.http(404, _) = error {
                isInWantlist = false
            } else if !LibraryMembershipStore.shared.isInWantlist(releaseId) {
                isInWantlist = false
            }
        }
    }

    /// Ajoute ou retire de la wantlist instantanément (grisé/dégrisé) au clic.
    func toggle(releaseId: Int, release: Release? = nil) async {
        if isInWantlist {
            await remove(releaseId: releaseId)
        } else {
            await add(releaseId: releaseId, release: release)
        }
    }

    func add(releaseId: Int, release: Release? = nil) async {
        if DemoMode.isActive {
            report(AppMessages.demoAddBlocked)
            return
        }
        guard let username = authManager.username else {
            report(AppMessages.loginRequiredForWantlist)
            return
        }

        // Optimistic UI : griser instantanément le bouton
        withAnimation(.easeInOut(duration: 0.2)) {
            isInWantlist = true
        }
        notifyFeedback(.addedToWantlist)

        if let release {
            let item = WantlistItem(
                id: releaseId,
                rating: 0,
                notes: nil,
                dateAdded: ISO8601DateFormatter().string(from: Date()),
                basicInformation: release.basicInformation
            )
            await localStore.saveWantlistItems([item], username: username)
            LibraryMembershipStore.shared.notifyWantlistItemAdded(item)
        } else {
            LibraryMembershipStore.shared.markInWantlist(releaseId)
        }

        // Hors ligne avec des données de plus de 6 h : blocage.
        let isBlocked = !networkMonitor.isConnected && localStore.isWantlistStale(username: username)
        let outcome = isBlocked ? nil : await DiscogsWriteService.addToWantlist(releaseId: releaseId, username: username)
        switch outcome {
        case .queuedOffline:
            LibraryMembershipStore.shared.noteQueuedOffline(.wantlistAdded)
        case .queuedAfterFailure:
            report(AppMessages.discogsUnavailableQueued)
        case nil, .refused:
            // Bloqué, ou refus définitif : on annule plutôt que de laisser la file échouer trois fois.
            withAnimation(.easeInOut(duration: 0.2)) {
                isInWantlist = false
            }
            localStore.removeWantlistItem(username: username, releaseId: releaseId)
            LibraryMembershipStore.shared.notifyWantlistItemRemoved(releaseId: releaseId)
            report(isBlocked ? AppMessages.offlineStaleAddBlocked : AppMessages.addFailed)
        case .done:
            break
        }
    }

    func remove(releaseId: Int) async {
        if DemoMode.isActive {
            report(AppMessages.demoRemovalBlocked)
            return
        }
        guard let username = authManager.username else { return }

        // Vérifié AVANT toute modification : auparavant, l'élément était déjà supprimé du cache
        // local quand ce blocage le réaffichait, et disparaissait donc de la wantlist hors ligne.
        if !networkMonitor.isConnected && localStore.isWantlistStale(username: username) {
            report(AppMessages.offlineStaleRemovalBlocked)
            return
        }

        // Conservé pour pouvoir annuler le retrait en cas de refus définitif de Discogs.
        let previousItem = localStore.getWantlistItem(username: username, releaseId: releaseId)

        // Optimistic UI : dégriser instantanément le bouton
        withAnimation(.easeInOut(duration: 0.2)) {
            isInWantlist = false
        }
        notifyFeedback(.removedFromWantlist)
        localStore.removeWantlistItem(username: username, releaseId: releaseId)
        LibraryMembershipStore.shared.notifyWantlistItemRemoved(releaseId: releaseId)

        switch await DiscogsWriteService.removeFromWantlist(releaseId: releaseId, username: username) {
        case .queuedOffline:
            LibraryMembershipStore.shared.noteQueuedOffline(.wantlistRemoved)
        case .queuedAfterFailure:
            report(AppMessages.discogsUnavailableQueued)
        case .refused:
            withAnimation(.easeInOut(duration: 0.2)) {
                isInWantlist = true
            }
            if let previousItem {
                await localStore.saveWantlistItems([previousItem], username: username)
                LibraryMembershipStore.shared.notifyWantlistItemAdded(previousItem)
            } else {
                LibraryMembershipStore.shared.markInWantlist(releaseId)
            }
            report(AppMessages.removalFailed)
        case .done:
            break
        }
    }
}
