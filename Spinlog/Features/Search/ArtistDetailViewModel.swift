import Foundation

@Observable
@MainActor
final class ArtistDetailViewModel {
    private(set) var artist: Artist?
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    func load(artistId: Int) async {
        isLoading = true
        errorMessage = nil
        do {
            artist = try await DiscogsAPIClient.shared.artist(id: artistId, credentials: DiscogsAuthManager.shared.credentials)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
