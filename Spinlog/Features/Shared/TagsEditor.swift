import SwiftUI

/// Éditeur de tags personnels pour une release : pastilles avec suppression, plus un champ
/// pour en ajouter un nouveau. Persisté par `TagStore`, jamais envoyé à Discogs.
struct TagsEditor: View {
    let releaseId: Int
    @State private var store = TagStore.shared
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let tags = store.tags(for: releaseId)
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        TagPill(tag: tag) {
                            store.removeTag(tag, from: releaseId)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Ajouter un tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(addTag)
                Button("Ajouter", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addTag() {
        store.addTag(newTag, to: releaseId)
        newTag = ""
    }
}

/// Petite pastille de tag avec bouton de suppression, façon "Uncategorized" des apps Discogs.
struct TagPill: View {
    let tag: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: Capsule())
    }
}

/// Enchaîne des vues en les faisant passer à la ligne quand la largeur disponible est dépassée
/// (contrairement à un `HStack`, qui déborderait, ou un `ScrollView` horizontal, qui rebondirait
/// inutilement pour une poignée de tags courts).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        currentY += lineHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : currentX, height: currentY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
