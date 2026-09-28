import Foundation

@Observable
@MainActor
final class LabelDetailViewModel {
    private(set) var label: DiscogsLabel?
    private(set) var isLoading = true
    private(set) var errorMessage: String?

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
