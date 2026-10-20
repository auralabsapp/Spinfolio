import SwiftUI

// MARK: - Auto-scrolling Marquee Text

// `nonisolated` : sinon, avec l'isolation MainActor par défaut du module, la conformance à
// `PreferenceKey` devient isolée au fil principal alors que SwiftUI lit `defaultValue`/`reduce`
// depuis son fil de rendu asynchrone (`AsyncRenderer`) — l'app s'arrêtait
// (`dispatch_assert_queue_fail`) à l'apparition du mini-lecteur au lancement d'une écoute.
private nonisolated struct AutoScrollTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Affiche un texte sur une seule ligne. Si la largeur du texte dépasse l'espace disponible,
/// déclenche un défilement automatique horizontal élégant (pause initiale, défilement fluide, pause finale et retour).
struct AutoScrollingText: View {
    let text: String
    let font: Font
    var color: Color = .primary

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        // Vue fantôme masquée pour réserver la hauteur exacte de la ligne de texte
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .overlay(
                GeometryReader { geo in
                    let containerWidth = geo.size.width
                    let isOverflowing = textWidth > containerWidth && containerWidth > 0
                    let excess = max(0, textWidth - containerWidth)

                    ZStack(alignment: .leading) {
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .offset(x: isOverflowing ? offset : 0)
                    }
                    .frame(width: containerWidth, height: geo.size.height, alignment: .leading)
                    .clipped()
                    .mask(
                        HStack(spacing: 0) {
                            if isOverflowing && offset < -2 {
                                LinearGradient(
                                    colors: [.clear, .black],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 8)
                            }
                            Rectangle().fill(Color.black)
                            if isOverflowing && offset > -excess + 2 {
                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 8)
                            }
                        }
                    )
                    .task(id: "\(text)|\(Int(containerWidth))|\(Int(textWidth))") {
                        guard textWidth > containerWidth, containerWidth > 0 else {
                            offset = 0
                            return
                        }
                        let excess = textWidth - containerWidth
                        let scrollSpeed: Double = 26.0
                        let scrollDuration = max(1.8, Double(excess / scrollSpeed))

                        while !Task.isCancelled {
                            offset = 0
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            if Task.isCancelled { break }

                            withAnimation(.linear(duration: scrollDuration)) {
                                offset = -excess
                            }
                            try? await Task.sleep(nanoseconds: UInt64((scrollDuration + 1.8) * 1_000_000_000))
                            if Task.isCancelled { break }

                            withAnimation(.easeInOut(duration: 0.7)) {
                                offset = 0
                            }
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                        }
                    }
                }
            )
            .background(
                // Mesure hors écran de la largeur naturelle non contrainte du texte
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .background(
                        GeometryReader { textGeo in
                            Color.clear
                                .preference(key: AutoScrollTextWidthKey.self, value: textGeo.size.width)
                        }
                    )
            )
            .onPreferenceChange(AutoScrollTextWidthKey.self) { newWidth in
                textWidth = newWidth
            }
            .allowsHitTesting(false)
    }
}
