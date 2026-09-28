import SwiftUI

/// Requête d'ouverture du visualiseur plein écran : encapsule l'index de départ dans un type
/// `Identifiable` pour piloter `.fullScreenCover(item:)`.
struct ImageViewerRequest: Identifiable {
    let id = UUID()
    let startIndex: Int
}

/// Visualiseur d'images plein écran façon Photos : on peut swiper pour passer à l'image
/// suivante/précédente, et fermer avec la croix ou en balayant vers le bas.
struct ImageViewerView: View {
    let images: [DiscogsImage]
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(images: [DiscogsImage], startIndex: Int) {
        self.images = images
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(images.indices, id: \.self) { index in
                    FullScreenImage(url: images[index].uri)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.5), in: Circle())
                }

                Spacer()

                if images.count > 1 {
                    Text("\(currentIndex + 1) / \(images.count)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                }
            }
            .padding()
        }
        .statusBarHidden()
    }
}

private struct FullScreenImage: View {
    let url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
            } else if phase.error != nil {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
