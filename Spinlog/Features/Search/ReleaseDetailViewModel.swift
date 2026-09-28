import UIKit

@Observable
@MainActor
final class ReleaseDetailViewModel {
    private(set) var release: Release?
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var averageColor: UIColor?

    /// Charge la release et, en parallèle, l'état "en collection"/"en wantlist" via `actions`
    /// (déjà propriétaire de cette logique — voir `ReleaseActions`), sans attendre la fin du
    /// chargement de la release pour afficher la vue.
    func load(releaseId: Int, actions: ReleaseActions) async {
        actions.prepareInitialStatus(releaseId: releaseId)

        isLoading = true
        errorMessage = nil

        let statusTask = Task {
            async let collectionCheck: Void = actions.checkIfInCollection(releaseId: releaseId)
            async let wantlistCheck: Void = actions.checkIfInWantlist(releaseId: releaseId)
            _ = await (collectionCheck, wantlistCheck)
        }

        do {
            release = try await DiscogsAPIClient.shared.release(
                id: releaseId, credentials: DiscogsAuthManager.shared.credentials
            )
            if let url = release?.primaryImageURL, let cached = ReleaseColorCache.shared.color(forURL: url) {
                averageColor = cached
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        // Dès que la release est obtenue, on affiche la vue.
        // Si elle est déjà en collection locale, "Mes exemplaires" est DÉJÀ là sans pop-in ni délai !
        isLoading = false

        await statusTask.value
    }
}
