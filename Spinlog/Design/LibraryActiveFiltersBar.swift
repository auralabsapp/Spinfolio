import SwiftUI

/// Bandeau des filtres actifs (tag / support), partagé par Collection et Wantlist.
struct LibraryActiveFiltersBar: View {
    @Binding var selectedTag: String?
    @Binding var selectedFormat: String?
    let onClearAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let tag = selectedTag {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                        Text(tag)
                            .font(.caption.weight(.semibold))
                        Button {
                            selectedTag = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.bold())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                }

                if let format = selectedFormat {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.caption2)
                        Text(format)
                            .font(.caption.weight(.semibold))
                        Button {
                            selectedFormat = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.bold())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.primary)
                }

                Button("Tout effacer", action: onClearAll)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
