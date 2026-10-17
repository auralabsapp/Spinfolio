import SwiftUI

/// Bulle de confirmation façon Apple Music (« Ajouté à la bibliothèque ») : capsule
/// légèrement transparente (`.ultraThinMaterial`) avec une icône bicolore (cercle noir,
/// glyphe blanc) qui reste identique quel que soit le mode clair/sombre, comme la référence.
struct LibraryToastBubble: View {
    let kind: LibraryToastKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 20))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black)

            Text(kind.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
