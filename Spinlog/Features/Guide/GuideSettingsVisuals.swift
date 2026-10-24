import SwiftUI

/// Maquettes des sections « Alertes de prix » et « Réglages » (voir `GuideVisualView`). Les prix,
/// noms de tags et de dossiers sont des exemples affichés en `verbatim` : ce sont des données.

// MARK: - Alertes : ligne de wantlist

struct AlertRowMock: View {
    var body: some View {
        HStack(spacing: 12) {
            CoverPlaceholder(size: 44)
            VStack(alignment: .leading, spacing: 6) {
                TextLine(width: 110)
                TextLine(width: 70)
            }
            Spacer(minLength: 0)
            // Même pastille que la ligne de `WantlistView`.
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                Text(verbatim: "≤ 25 €")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.spinlogPink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.spinlogPinkBadge, in: Capsule())
        }
    }
}

// MARK: - Alertes : suggestions de seuil

struct AlertSuggestionsMock: View {
    private static let conditions: [(name: String, price: String)] = [
        ("Mint (M)", "48 €"), ("Near Mint (NM or M-)", "36 €"), ("Very Good Plus (VG+)", "24 €")
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Self.conditions, id: \.name) { entry in
                HStack {
                    Text(verbatim: entry.name)
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Text(verbatim: entry.price)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.spinlogPink)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            }

            HStack(spacing: 8) {
                percent("-10%")
                percent("-20%")
                percent("-30%")
            }
        }
    }

    private func percent(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.spinlogPink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.spinlogPinkBadge, in: Capsule())
    }
}

// MARK: - Alertes : déclenchée

struct AlertTriggeredMock: View {
    var body: some View {
        HStack(spacing: 12) {
            CoverPlaceholder(size: 44)
            VStack(alignment: .leading, spacing: 6) {
                TextLine(width: 110)
                TextLine(width: 70)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "bell.badge.fill")
                    .font(.caption2)
                Text(verbatim: "≤ 25 €")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - Hors ligne

struct OfflineMock: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archive locale")
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: "128")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.teal)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: 0.7)
                .tint(Color.spinlogPink)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - iCloud

struct ICloudMock: View {
    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(systemName: "icloud.fill", backgroundColor: .blue)
            Text("Synchroniser avec iCloud")
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Toggle(isOn: .constant(true)) { EmptyView() }
                .labelsHidden()
                .tint(Color.spinlogPink)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Thèmes

struct ThemesMock: View {
    private static let palettes: [Color] = [.spinlogPink, .blue, .green, .orange, .red, .purple]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(Self.palettes.enumerated()), id: \.offset) { index, color in
                Circle()
                    .fill(color)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(index == 0 ? 0.6 : 0), lineWidth: 2).padding(-4)
                    )
            }
        }
    }
}

// MARK: - Exports

struct ExportsMock: View {
    var body: some View {
        VStack(spacing: 8) {
            row("Exporter la collection en CSV", systemImage: "tablecells", color: .green)
            row("Déclaration de collection (PDF)", systemImage: "doc.richtext", color: .indigo)
        }
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        HStack(spacing: 14) {
            SettingsIcon(systemName: systemImage, backgroundColor: color)
            Text(title)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Image(systemName: "square.and.arrow.up")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.appTertiaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Tags et dossiers

struct TagsAndFoldersMock: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                tag("Jazz", count: "12")
                tag("Live", count: "4")
                tag("Rare", count: "2")
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(verbatim: "Jazz")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }

    private func tag(_ title: String, count: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.caption2)
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
            Text(verbatim: count)
                .font(.caption)
                .foregroundStyle(Color.appSecondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.spinlogPinkBadge, in: Capsule())
        .foregroundStyle(Color.spinlogPink)
    }
}

// MARK: - Compte

struct AccountMock: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.spinlogPink.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "vinyl_fan")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("Connecté à Discogs")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            Text("Se déconnecter")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            GuideVisualView(visual: .alertRow)
            GuideVisualView(visual: .alertSuggestions)
            GuideVisualView(visual: .alertTriggered)
            GuideVisualView(visual: .offline)
            GuideVisualView(visual: .iCloud)
            GuideVisualView(visual: .themes)
            GuideVisualView(visual: .exports)
            GuideVisualView(visual: .tagsAndFolders)
            GuideVisualView(visual: .account)
        }
        .padding()
    }
}
