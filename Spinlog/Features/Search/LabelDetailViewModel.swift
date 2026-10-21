import Foundation

@Observable
@MainActor
final class LabelDetailViewModel {
    private(set) var label: DiscogsLabel?
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    /// Chargement à l'apparition de la vue. Au retour d'un écran poussé depuis celui-ci, les données
    /// sont déjà affichées : on ne repasse PAS par l'état « chargement », qui remplacerait le
    /// contenu défilant par le squelette et ferait perdre la position de lecture (même règle que
    /// `ReleaseDetailViewModel.loadIfNeeded`).
    func loadIfNeeded(labelId: Int) async {
        guard label?.id != labelId || errorMessage != nil else { return }
        await load(labelId: labelId)
    }

    func load(labelId: Int) async {
        isLoading = true
        errorMessage = nil
        do {
            label = try await DiscogsAPIClient.shared.label(id: labelId, credentials: DiscogsAuthManager.shared.credentials)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
