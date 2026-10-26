import SwiftUI

/// Bulle de confirmation façon Apple Music (« Ajouté à la bibliothèque ») : capsule
/// légèrement transparente (`.ultraThinMaterial`) avec une icône bicolore (cercle dans la
/// teinte du thème actif, glyphe blanc), plutôt que le noir/blanc fixe de la référence.
struct LibraryToastBubble: View {
    let kind: LibraryToastKind
    var queuedOffline: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 20))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.spinlogPink)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if queuedOffline {
                    Text("Hors ligne : synchronisé au retour du réseau")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Capsule().fill(.thinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .motionTransition(.move(edge: .bottom).combined(with: .opacity))
    }
}
