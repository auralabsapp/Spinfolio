import SwiftUI

struct CollectionRow: View {
    let item: CollectionItem

    @State private var tagStore = TagStore.shared

    private var info: BasicInformation { item.basicInformation }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AsyncCoverImage(url: coverURL, cornerRadius: 8)
                .frame(width: 80, height: 80)
                .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 2.5)

            VStack(alignment: .leading, spacing: 3) {
                Text(info.artistNames)
                    .font(.headline)
                    .lineLimit(1)

                Text(info.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let formatLine {
                    Text(formatLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let year = info.year {
                        Text(String(year))
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    if hasNotes {
                        Text("Notes")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    ForEach(tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.tagBackground, in: Capsule())
                            .foregroundStyle(Color.tagForeground)
                    }
                    if tags.count > 2 {
                        Text("+\(tags.count - 2)")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.tagForeground)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var coverURL: String? {
        if let cover = info.coverImage, !cover.isEmpty {
            return cover
        }
        if let thumb = info.thumb, !thumb.isEmpty {
            return thumb
        }
        return nil
    }

    private var tags: [String] {
        tagStore.tags(for: item.releaseId)
    }

    /// Le tag "Notes" signale qu'au moins un champ personnalisé Discogs a été renseigné
    /// pour cet exemplaire (état de la pochette, remarques libres, etc.).
    private var hasNotes: Bool {
        item.notes.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var formatLine: String? {
        guard let formats = info.formats, !formats.isEmpty else { return nil }
        return formats
            .map { format in ([format.name] + (format.descriptions ?? [])).joined(separator: ", ") }
            .joined(separator: " / ")
    }
}
