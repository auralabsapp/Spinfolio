import UIKit

@Observable
@MainActor
final class MasterDetailViewModel {
    private(set) var master: MasterRelease?
    private(set) var versions: [MasterVersion] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var averageColor: UIColor?

    /// Chargement à l'apparition de la vue. Au retour d'un écran poussé depuis celui-ci, les données
    /// sont déjà affichées : on ne repasse PAS par l'état « chargement », qui remplacerait le
    /// contenu défilant par le squelette et ferait perdre la position de lecture (même règle que
    /// `ReleaseDetailViewModel.loadIfNeeded`).
    func loadIfNeeded(masterId: Int) async {
        guard master?.id != masterId || errorMessage != nil else { return }
        await load(masterId: masterId)
    }

    func load(masterId: Int) async {
        isLoading = true
        errorMessage = nil
        do {
            let credentials = DiscogsAuthManager.shared.credentials
            let fetchedMaster = try await DiscogsAPIClient.shared.masterRelease(id: masterId, credentials: credentials)
            master = fetchedMaster

            if let coverURL = fetchedMaster.primaryImageURL,
               let cachedColor = ReleaseColorCache.shared.color(forURL: coverURL) {
                averageColor = cachedColor
            }

            versions = try await DiscogsAPIClient.shared.masterVersions(masterId: masterId, credentials: credentials).versions
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
