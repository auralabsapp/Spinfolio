import SwiftUI

/// Maquettes de la section « Rangement » (voir `GuideVisualView`). Les noms d'artistes sont des
/// exemples affichés en `verbatim` : ce sont des données, pas des libellés à traduire.

// MARK: - Position dans le meuble

struct ShelfPlacementMock: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                neighbor
                CoverPlaceholder(size: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius / 2, style: .continuous)
                            .strokeBorder(Color.spinlogPink, lineWidth: 2)
                    )
                neighbor
            }

            // Même repère que l'en-tête du guide de rangement : numéro et jauge.
            HStack(spacing: 10) {
                Text(verbatim: "N° 42")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(Color.spinlogPink).frame(width: 52)
                }
                .frame(height: 6)
            }
        }
    }

    private var neighbor: some View {
        CoverPlaceholder(size: 44).opacity(0.6)
    }
}

// MARK: - Méthode de classement

struct ShelfMethodMock: View {
    var body: some View {
        VStack(spacing: 6) {
            ForEach(ShelfSortStrategy.allCases) { strategy in
                HStack(spacing: 10) {
                    Image(systemName: strategy == .artistThenMasterYear ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(strategy == .artistThenMasterYear ? Color.spinlogPink : Color.appTertiaryText)
                    Text(strategy.shortTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
        }
    }
}

// MARK: - Noms d'artistes

struct ArtistNamesMock: View {
    var body: some View {
        VStack(spacing: 8) {
            line(from: "The Beatles", to: "Beatles, The")
            line(from: "David Bowie", to: "Bowie, David")
            line(from: "Pink Floyd", to: "Pink Floyd")
        }
    }

    private func line(from original: String, to sortKey: String) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: original)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appTertiaryText)
            Text(verbatim: sortKey)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Supports et dossiers

struct ShelfScopeMock: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                chip(ShelfMediaCategory.vinyl12.displayName, highlighted: true)
                chip(ShelfMediaCategory.cd.displayName)
                chip(ShelfMediaCategory.cassette.displayName)
            }

            // Même badge que le guide de rangement.
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption.weight(.bold))
                Text("Tous les dossiers")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.appSecondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Color.primary.opacity(0.10), in: Capsule())
        }
    }

    private func chip(_ title: String, highlighted: Bool = false) -> some View {
        Text(verbatim: title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .background(highlighted ? AnyShapeStyle(Color.spinlogPink) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Capsule())
    }
}

#Preview {
    VStack(spacing: 16) {
        GuideVisualView(visual: .shelfPlacement)
        GuideVisualView(visual: .shelfMethod)
        GuideVisualView(visual: .artistNames)
        GuideVisualView(visual: .shelfScope)
    }
    .padding()
}
