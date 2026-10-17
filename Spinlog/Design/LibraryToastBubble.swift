import SwiftUI

/// Bulle de confirmation façon Apple Music (« Ajouté à la bibliothèque ») : capsule
/// légèrement transparente (`.ultraThinMaterial`) avec une icône bicolore (cercle dans la
/// teinte du thème actif, glyphe blanc), plutôt que le noir/blanc fixe de la référence.
struct LibraryToastBubble: View {
    let kind: LibraryToastKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 20))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.spinlogPink)

            Text(kind.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Capsule().fill(.thinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
