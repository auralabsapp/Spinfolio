import SwiftUI

/// Barre de navigation rapide sur le bord droit (comme Contacts) : lettres pour un tri
/// alphabétique, années sur 2 chiffres pour un tri par date d'ajout. Glisser le doigt le
/// long de la barre fait défiler la liste jusqu'à la section correspondante.
struct SectionIndexBar: View {
    let entries: [(token: String, sectionKey: String)]
    let onSelect: (String) -> Void

    @State private var activeToken: String?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(entries, id: \.token) { entry in
                    Text(railLabel(for: entry.token))
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(activeToken == entry.token ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        select(at: value.location.y, in: geometry.size.height)
                    }
                    .onEnded { _ in
                        activeToken = nil
                    }
            )
        }
        .frame(width: 18)
        .overlay(alignment: .center) {
            if let activeToken {
                Text(activeToken)
                    .font(.system(size: activeToken.count > 2 ? 22 : 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.buttonPinkTop, Color.buttonPinkBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .shadow(color: Color.buttonPinkBottom.opacity(0.35), radius: 8, y: 2)
                    )
                    .offset(x: -46)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeOut(duration: 0.15), value: activeToken)
    }

    private func railLabel(for token: String) -> String {
        if token.count == 4, let _ = Int(token) {
            return String(token.suffix(2))
        }
        return token
    }

    private func select(at y: CGFloat, in height: CGFloat) {
        guard !entries.isEmpty, height > 0 else { return }
        let clampedY = min(max(y, 0), height - 0.01)
        let index = Int(clampedY / height * CGFloat(entries.count))
        let boundedIndex = min(max(index, 0), entries.count - 1)
        let entry = entries[boundedIndex]
        if entry.token != activeToken {
            activeToken = entry.token
            onSelect(entry.sectionKey)
        }
    }
}
