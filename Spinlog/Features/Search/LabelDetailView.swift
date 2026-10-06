import SwiftUI

struct LabelDetailView: View {
    let labelId: Int

    @State private var viewModel = LabelDetailViewModel()

    var body: some View {
        content
            .navigationTitle(viewModel.label?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .disablesContentPopGesture()
            .task { await viewModel.load(labelId: labelId) }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView(
                "Impossible de charger ce label",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if let label = viewModel.label {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AsyncCoverImage(url: label.primaryImageURL)
                        .frame(width: 200, height: 200)
                        .frame(maxWidth: .infinity)

                    Text(label.name).font(.title2.bold())

                    if let profile = label.profile, !profile.isEmpty {
                        Text(profile).font(.body)
                    }

                    if let url = label.discogsWebURL {
                        DiscogsAttributionLink(url: url)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding()
            }
        }
    }
}
