import SwiftUI
import Kingfisher

/// Requête d'ouverture du visualiseur plein écran : encapsule l'index de départ dans un type
/// `Identifiable` pour piloter `.fullScreenCover(item:)`.
struct ImageViewerRequest: Identifiable {
    let id = UUID()
    let startIndex: Int
}

/// Visualiseur d'images plein écran façon Photos : on peut swiper horizontalement pour changer d'image,
/// et fermer avec le bouton croix ou en balayant vers le bas (swipe down to dismiss).
struct ImageViewerView: View {
    let images: [DiscogsImage]
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingDown = false

    init(images: [DiscogsImage], startIndex: Int) {
        self.images = images
        _currentIndex = State(initialValue: startIndex)
    }

    private var backgroundOpacity: Double {
        let progress = min(1.0, max(0.0, Double(dragOffset) / 280.0))
        return max(0.0, 1.0 - progress)
    }

    private var imageScale: CGFloat {
        max(0.85, 1.0 - (dragOffset / 1400.0))
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                if !isDraggingDown {
                    // Vérifie que le mouvement vertical vers le bas domine largement l'horizontal
                    // pour ne pas entrer en conflit avec la pagination du TabView
                    if value.translation.height > 10 && abs(value.translation.height) > abs(value.translation.width) * 1.2 {
                        isDraggingDown = true
                    }
                }
                if isDraggingDown {
                    dragOffset = max(0, value.translation.height)
                }
            }
            .onEnded { value in
                guard isDraggingDown else { return }
                isDraggingDown = false

                let shouldDismiss = dragOffset > 100 || (dragOffset > 30 && value.predictedEndTranslation.height > 200)
                if shouldDismiss {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                }
            }
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(images.indices, id: \.self) { index in
                    FullScreenImage(url: images[index].uri)
                        .tag(index)
                        .accessibilityLabel(imageLabel(for: index))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragOffset)
            .scaleEffect(imageScale)
            .contentShape(Rectangle())
        }
        // `.simultaneousGesture` permet au TabView de conserver sa pagination horizontale
        // tout en interceptant le swipe down vertical vers le bas pour fermer la vue
        .simultaneousGesture(dismissGesture)
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
                .accessibilityLabel("Fermer")

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
            .opacity(max(0.0, 1.0 - Double(dragOffset) / 80.0))
        }
        .statusBarHidden()
    }

    private func imageLabel(for index: Int) -> String {
        let isPrimary = images[index].type == "primary"
        if isPrimary {
            return "Pochette de l'album"
        }
        return "Photo \(index + 1) sur \(images.count) de la release"
    }
}

/// Affiche l'image en plein écran avec Kingfisher (cache disque 6h et injection OAuth automatique).
private struct FullScreenImage: View {
    let url: String

    var body: some View {
        if let imageURL = URL(string: url) {
            KFImage(imageURL)
                .placeholder {
                    ProgressView()
                        .tint(.white)
                }
                .onFailure { _ in }
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
    }
}
