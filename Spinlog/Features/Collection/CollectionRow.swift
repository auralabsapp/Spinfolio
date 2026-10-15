import SwiftUI

struct CollectionRow: View {
    /// Référencée par `SkeletonLibraryRow` (via `LibraryListView`) pour que son gabarit de
    /// chargement reste de la même taille que la vraie pochette, sans retaper la valeur.
    static let coverSize: CGFloat = 80

    let item: CollectionItem
    var copyBadge: String? = nil
    /// Mode sélection multiple actif pour toute la liste (contrôle l'apparition de la pastille).
    var isSelecting: Bool = false
    /// État coché/décoché de cet exemplaire, pertinent seulement si `isSelecting` est vrai.
    var isSelected: Bool = false

    @State private var tagStore = TagStore.shared

    private var info: BasicInformation { item.basicInformation }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.spinlogPink : Color.appTertiaryText)
                    .transition(.scale.combined(with: .opacity))
            }

            AsyncCoverImage(url: coverURL, cornerRadius: 10, targetSize: Self.coverSize)
                .frame(width: Self.coverSize, height: Self.coverSize)
                // Micro-bordure pour l'épaisseur carton, remplacée par la bordure de sélection
                // quand cet exemplaire est coché.
                .overlay {
                    if isSelecting && isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.spinlogPink, lineWidth: 2.5)
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                }
                .opacity(isSelecting ? (isSelected ? 1.0 : 0.45) : 1.0)
                // Ombre de contact (très proche) puis ombre d'ambiance flottante (large et douce) ;
                // toutes deux atténuées pendant la sélection multiple, comme l'opacité de la pochette.
                .shadow(color: .black.opacity(isSelecting ? (isSelected ? 0.30 : 0.12) : 0.22), radius: 5, x: 0, y: 3)
                .shadow(color: .black.opacity(isSelecting ? (isSelected ? 0.45 : 0.18) : 0.35), radius: 16, x: 0, y: 10)
                .animation(.librarySelectionToggle, value: isSelected)

            VStack(alignment: .leading, spacing: 2) {
                // Bloc 1 : Titre de l'album (mis en évidence) & Artiste
                VStack(alignment: .leading, spacing: 2) {
                    // 1ère ligne : Titre de l'album
                    Text(info.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // 2ème ligne : Artiste
                    Text(info.artistNames)
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }

                // Bloc 2 : Format & Année / Date d'ajout (interligne accru après la ligne 2)
                if (formatLine != nil && !(formatLine?.isEmpty ?? true)) || yearAndDateLine != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        // 3ème ligne : Format
                        if let formatLine, !formatLine.isEmpty {
                            Text(formatLine)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                                .lineLimit(1)
                        }

                        // 4ème ligne : Année - Ajouté le jj/mm/aaaa
                        if let yearAndDateLine {
                            Text(yearAndDateLine)
                                .font(.caption2)
                                .foregroundStyle(Color.appSecondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 1)
                }

                // Bloc 3 : Étiquette exemplaire et badges (interligne accru après la ligne 4)
                if copyBadge != nil || customFieldsCount > 0 || !tags.isEmpty {
                    // 5ème ligne : Étiquette exemplaire, "x champs perso" et "x tags"
                    HStack(spacing: 6) {
                        if let copyBadge {
                            Text(copyBadge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                                .foregroundStyle(Color.appSecondaryText)
                        }

                        if customFieldsCount > 0 {
                            Text(customFieldsLabel)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }

                        if !tags.isEmpty {
                            Text(tagsLabel)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.tagBackground, in: Capsule())
                                .foregroundStyle(Color.tagForeground)
                        }
                    }
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
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
        tagStore.tags(for: item.instanceId, releaseId: item.releaseId)
    }

    /// Nombre de champs personnalisés Discogs renseignés par l'utilisateur
    /// pour cet exemplaire (état du disque, état de la pochette, commentaires, etc.).
    private var customFieldsCount: Int {
        item.notes.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var customFieldsLabel: String {
        String(localized: "\(customFieldsCount) infos perso")
    }

    private var tagsLabel: String {
        String(localized: "\(tags.count) tags")
    }

    /// Réutilisée plutôt que reconstruite à chaque évaluation de `yearAndDateLine` (appelée à
    /// chaque ligne visible pendant le défilement) : `Date.FormatStyle` résout calendrier/locale
    /// à la construction, un coût non négligeable répété pour chaque ligne à chaque frame.
    private static let dateFormatStyle = Date.FormatStyle(date: .numeric, time: .omitted)

    private var yearAndDateLine: String? {
        let year = info.year != nil && info.year! > 0 ? "\(info.year!)" : nil
        let date = item.dateAddedDate?.formatted(Self.dateFormatStyle)
        switch (year, date) {
        case let (.some(y), .some(d)):
            return String(localized: "\(y) · Ajouté le \(d)")
        case let (.some(y), .none):
            return y
        case let (.none, .some(d)):
            return String(localized: "Ajouté le \(d)")
        case (.none, .none):
            return nil
        }
    }

    private var formatLine: String? {
        guard let formats = info.formats, !formats.isEmpty else { return nil }
        return formats
            .map { format in ([format.name] + (format.descriptions ?? [])).joined(separator: ", ") }
            .joined(separator: " / ")
    }
}
