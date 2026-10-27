import SwiftUI

/// Bandeau des filtres actifs (tag / support), partagé par Collection et Wantlist.
struct LibraryActiveFiltersBar: View {
    var selectedTags: Binding<Set<String>>? = nil
    var selectedTag: Binding<String?>? = nil
    /// Champs à compléter (Collection seulement : la wantlist n'a pas de champs personnalisés).
    var selectedMissingFields: Binding<Set<LibraryMissingField>>? = nil
    @Binding var selectedFormat: String?
    let onClearAll: () -> Void

    init(
        selectedTags: Binding<Set<String>>,
        selectedFormat: Binding<String?>,
        selectedMissingFields: Binding<Set<LibraryMissingField>>? = nil,
        onClearAll: @escaping () -> Void
    ) {
        self.selectedTags = selectedTags
        self.selectedMissingFields = selectedMissingFields
        self.selectedTag = nil
        self._selectedFormat = selectedFormat
        self.onClearAll = onClearAll
    }

    init(
        selectedTag: Binding<String?>,
        selectedFormat: Binding<String?>,
        onClearAll: @escaping () -> Void
    ) {
        self.selectedTags = nil
        self.selectedTag = selectedTag
        self._selectedFormat = selectedFormat
        self.onClearAll = onClearAll
    }

    init(
        selectedFormat: Binding<String?>,
        onClearAll: @escaping () -> Void
    ) {
        self.selectedTags = nil
        self.selectedTag = nil
        self._selectedFormat = selectedFormat
        self.onClearAll = onClearAll
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let selectedTags {
                    ForEach(selectedTags.wrappedValue.sorted(), id: \.self) { tag in
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                            Text(tag)
                                .font(.caption.weight(.semibold))
                            Button {
                                selectedTags.wrappedValue.remove(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                            }
                            .accessibilityLabel("Effacer le filtre de tag \(tag)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.spinlogPinkBadge, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.spinlogPink.opacity(0.35), lineWidth: 0.8))
                        .foregroundStyle(Color.spinlogPink)
                    }
                } else if let selectedTag, let tag = selectedTag.wrappedValue {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                        Text(tag)
                            .font(.caption.weight(.semibold))
                        Button {
                            selectedTag.wrappedValue = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.bold())
                        }
                        .accessibilityLabel("Effacer le filtre de tag \(tag)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.spinlogPinkBadge, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.spinlogPink.opacity(0.35), lineWidth: 0.8))
                    .foregroundStyle(Color.spinlogPink)
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
                        .accessibilityLabel("Effacer le filtre de format")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.spinlogPinkBadge, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.spinlogPink.opacity(0.35), lineWidth: 0.8))
                    .foregroundStyle(Color.spinlogPink)
                }

                if let selectedMissingFields {
                    ForEach(LibraryMissingField.allCases.filter { selectedMissingFields.wrappedValue.contains($0) }, id: \.self) { field in
                        HStack(spacing: 4) {
                            Image(systemName: field.systemImage)
                                .font(.caption2)
                            Text(field.title)
                                .font(.caption.weight(.semibold))
                            Button {
                                selectedMissingFields.wrappedValue.remove(field)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                            }
                            .accessibilityLabel("Effacer le filtre « \(String(localized: field.title)) »")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.spinlogPinkBadge, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.spinlogPink.opacity(0.35), lineWidth: 0.8))
                        .foregroundStyle(Color.spinlogPink)
                    }
                }

                Button("Tout effacer", action: onClearAll)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}
