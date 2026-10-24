import SwiftUI

/// Maquettes des sections « Collection et Wantlist » et « Fiche d'un disque » (voir
/// `GuideVisualView`). Les textes d'exemple saisis par l'utilisateur dans l'app (tags, dossiers,
/// prix) sont affichés en `verbatim` : ce sont des données, pas des libellés à traduire.

/// Pochette stylisée : un carré arrondi neutre, au rayon des vraies pochettes.
struct CoverPlaceholder: View {
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius / 2, style: .continuous)
            .fill(Color.primary.opacity(0.15))
            .frame(width: size, height: size)
    }
}

/// Trait gris qui tient la place d'un texte.
struct TextLine: View {
    let width: CGFloat

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.15))
            .frame(width: width, height: 7)
    }
}

// MARK: - Affichages

struct DisplayModesMock: View {
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            mode(systemImage: LibraryDisplayMode.list.systemImage) { listLayout }
            mode(systemImage: LibraryDisplayMode.grid.systemImage) { gridLayout }
            mode(systemImage: LibraryDisplayMode.carousel.systemImage) { carouselLayout }
        }
    }

    private func mode<Layout: View>(systemImage: String, @ViewBuilder layout: () -> Layout) -> some View {
        VStack(spacing: 8) {
            layout()
                .frame(width: 72, height: 66)
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.appSecondaryText)
        }
    }

    private var listLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 6) {
                    CoverPlaceholder(size: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        TextLine(width: 34)
                        TextLine(width: 22)
                    }
                }
            }
        }
    }

    private var gridLayout: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
                GridRow {
                    ForEach(0..<3, id: \.self) { _ in
                        CoverPlaceholder(size: 20)
                    }
                }
            }
        }
    }

    private var carouselLayout: some View {
        // Largeur cumulée (20 + 44 + 20 − 2 × 4) ≤ celle du cadre : sans cela le carrousel
        // débordait sur la mosaïque voisine.
        HStack(spacing: -4) {
            CoverPlaceholder(size: 20).opacity(0.5)
            CoverPlaceholder(size: 44)
                .zIndex(1)
            CoverPlaceholder(size: 20).opacity(0.5)
        }
    }
}

// MARK: - Tri et barre d'index

struct SortAndIndexMock: View {
    private static let letters = ["A", "B", "C", "D", "E"]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header("A")
                row
                header("B")
                row
                row
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 3) {
                ForEach(Self.letters, id: \.self) { letter in
                    Text(verbatim: letter)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(letter == "B" ? Color.spinlogPink : Color.appSecondaryText)
                }
            }
        }
    }

    private func header(_ letter: String) -> some View {
        Text(verbatim: letter)
            .font(.footnote.weight(.bold))
            .foregroundStyle(Color.spinlogPink)
    }

    private var row: some View {
        HStack(spacing: 8) {
            CoverPlaceholder()
            VStack(alignment: .leading, spacing: 4) {
                TextLine(width: 90)
                TextLine(width: 56)
            }
        }
    }
}

// MARK: - Recherche et filtres

struct FiltersMock: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.appSecondaryText)
                Text("Rechercher dans ta collection")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Même puce que `LibraryActiveFiltersBar`.
            HStack(spacing: 8) {
                chip("Jazz", systemImage: "tag.fill")
                chip("Vinyl", systemImage: "square.stack.3d.up")
                Spacer(minLength: 0)
            }
        }
    }

    private func chip(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
            Image(systemName: "xmark")
                .font(.caption2.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.spinlogPinkBadge, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.spinlogPink.opacity(0.35), lineWidth: 0.8))
        .foregroundStyle(Color.spinlogPink)
    }
}

// MARK: - Actions sur une ligne

struct RowActionsMock: View {
    var body: some View {
        HStack(spacing: 8) {
            action("J'écoute", systemImage: "opticaldisc.fill", color: Color.spinlogPink)
            action("Ranger", systemImage: "books.vertical.fill", color: .indigo)
            action("Modifier", systemImage: "pencil", color: .orange)
            action("Supprimer", systemImage: "trash.fill", color: .red)
        }
    }

    private func action(_ title: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color))
    }
}

// MARK: - Liste de titres

struct TracklistMock: View {
    private static let rows: [(number: String, width: CGFloat, duration: String)] = [
        ("1", 120, "3:42"), ("2", 90, "4:15"), ("3", 140, "2:58"), ("4", 104, "5:03")
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Self.rows, id: \.number) { row in
                HStack(spacing: 10) {
                    Text(verbatim: row.number)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                        .frame(width: 16)
                    TextLine(width: row.width)
                    Spacer(minLength: 0)
                    if row.number == "2" {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(Color.spinlogPink)
                    }
                    Text(verbatim: row.duration)
                        .font(.caption)
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
        }
    }
}

// MARK: - Exemplaires

struct CopiesMock: View {
    var body: some View {
        VStack(spacing: 8) {
            copy(folder: "Uncategorized")
            copy(folder: "Jazz")

            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("Ajouter un autre exemplaire")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Color.spinlogPink)
            .padding(.top, 2)
        }
    }

    private func copy(folder: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "opticaldisc.fill")
                .foregroundStyle(Color.spinlogPink)
            Text(verbatim: "• \(folder)")
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
            Image(systemName: "pencil")
                .font(.footnote)
                .foregroundStyle(Color.appSecondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Tags et note

struct TagsAndRatingMock: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                tag("Jazz")
                tag("Live")
                Spacer(minLength: 0)
            }

            // Mêmes étoiles que `ReleaseRatingCard`.
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { value in
                    Image(systemName: value <= 4 ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(value <= 4 ? Color.orange : Color.secondary.opacity(0.3))
                }
                Spacer(minLength: 0)
                Text(verbatim: "4/5")
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
    }

    private func tag(_ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.caption2)
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.spinlogPinkBadge, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.spinlogPink.opacity(0.35), lineWidth: 0.8))
        .foregroundStyle(Color.spinlogPink)
    }
}

// MARK: - Prix d'achat et cote

struct PriceMock: View {
    var body: some View {
        VStack(spacing: 8) {
            line("Prix d'achat", value: "25 €")
            line("Cote actuelle", value: "40 €")
        }
    }

    private func line(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
            Spacer(minLength: 0)
            Text(verbatim: value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            GuideVisualView(visual: .displayModes)
            GuideVisualView(visual: .sortAndIndex)
            GuideVisualView(visual: .filters)
            GuideVisualView(visual: .rowActions)
            GuideVisualView(visual: .tracklist)
            GuideVisualView(visual: .copies)
            GuideVisualView(visual: .tagsAndRating)
            GuideVisualView(visual: .price)
        }
        .padding()
    }
}
