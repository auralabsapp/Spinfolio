import SwiftUI

/// Barre de navigation rapide horizontale (Scrubber alphabétique / chronologique)
/// positionnée en bas du mode Carrousel pour naviguer instantanément entre les sections.
struct HorizontalSectionIndexBar: View {
    let entries: [(token: String, sectionKey: String)]
    var currentToken: String? = nil
    let onSelect: (String) -> Void

    @State private var dragToken: String?
    @State private var touchX: CGFloat = 0
    @State private var isDragging: Bool = false

    private var activeToken: String? {
        dragToken ?? currentToken
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            HStack(spacing: 0) {
                ForEach(entries, id: \.token) { entry in
                    let isSelected = activeToken == entry.token
                    Text(railLabel(for: entry.token))
                        .font(.system(size: entries.count > 18 ? 9 : 11, weight: isSelected ? .black : .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(isSelected ? Color.spinlogPink : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        touchX = value.location.x
                        select(at: value.location.x, in: width)
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragToken = nil
                    }
            )
            .overlay(alignment: .top) {
                if isDragging, let displayToken = dragToken {
                    let bubbleX = min(max(touchX - width / 2, -width / 2 + 28), width / 2 - 28)
                    Text(displayToken)
                        .font(.system(size: displayToken.count > 2 ? 18 : 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.buttonPinkTop, Color.buttonPinkBottom],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.buttonPinkBottom.opacity(0.40), radius: 8, y: 3)
                        )
                        .offset(x: bubbleX, y: -56)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragToken)
        }
        .frame(height: 28)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
        )
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func railLabel(for token: String) -> String {
        if token.count == 4, let _ = Int(token) {
            return String(token.suffix(2))
        }
        return token
    }

    private func select(at x: CGFloat, in width: CGFloat) {
        guard !entries.isEmpty, width > 0 else { return }
        let clampedX = min(max(x, 0), width - 0.01)
        let index = Int(clampedX / width * CGFloat(entries.count))
        let boundedIndex = min(max(index, 0), entries.count - 1)
        let entry = entries[boundedIndex]
        if entry.token != dragToken {
            dragToken = entry.token
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
            onSelect(entry.sectionKey)
        }
    }
}
