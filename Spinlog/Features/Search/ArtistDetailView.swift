import SwiftUI

struct ArtistDetailView: View {
    let artistId: Int

    @State private var viewModel = ArtistDetailViewModel()

    var body: some View {
        content
            .navigationTitle(viewModel.artist?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .disablesContentPopGesture()
            .task { await viewModel.load(artistId: artistId) }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "Impossible de charger cet artiste",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if let artist = viewModel.artist {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AsyncCoverImage(url: artist.primaryImageURL)
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity)

                    Text(artist.name)
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .center)

                    if let profile = artist.profile, !profile.isEmpty {
                        Text(profile).font(.body)
                    }

                    if let members = artist.members, !members.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Membres").font(.headline)
                            ForEach(members) { member in
                                NavigationLink(value: SearchDestination.artist(member.id)) {
                                    Text(member.name)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}
