import SwiftUI

struct BatchScanRow: View {
    let item: BatchScanItem
    let isInCollection: Bool
    let isInWantlist: Bool
    let onToggle: () -> Void
    let onSelectMatch: (SearchResult) -> Void
    let onRetry: () -> Void

    @State private var showingPressingChoice = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            switch item.status {
            case .resolving:
                ProgressView()
                    .frame(width: 44, height: 44)
            case .found(let result):
                Button(action: onToggle) {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.isSelected ? Color.spinlogPink : Color.appTertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isSelected ? "Désélectionner ce disque" : "Sélectionner ce disque")
                AsyncCoverImage(url: result.thumb ?? result.coverImage, cornerRadius: 6, targetSize: 44)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
            case .notFound:
                Image(systemName: "questionmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.appTertiaryText)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                switch item.status {
                case .resolving:
                    Text(item.code)
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                    Text("Recherche en cours\u{2026}")
                        .font(.caption)
                        .foregroundStyle(Color.appTertiaryText)
                case .found(let result):
                    Text(result.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if isInCollection {
                            Label("En collection", systemImage: "checkmark")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.spinlogPink)
                        } else if isInWantlist {
                            Label("En wantlist", systemImage: "heart.fill")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.spinlogPink)
                        } else {
                            Text(item.code)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                case .notFound:
                    Text(item.code)
                        .font(.subheadline)
                    Text("Aucun disque trouvé")
                        .font(.caption)
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
            Spacer(minLength: 0)

            if item.status == .notFound {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundStyle(Color.spinlogPink)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Réessayer")
            }

            if case .found(let selected) = item.status, item.alternatives.count > 1 {
                pressingPicker(selected: selected, alternatives: item.alternatives)
            }
        }
        .padding(.vertical, 4)
        .opacity(item.status == .notFound ? 0.5 : 1)
        // Recherche → trouvé / non reconnu : la pochette et le texte se fondent au lieu de se remplacer d'un coup.
        .animation(reduceMotion ? nil : .batchScanRowChange, value: item.status)
    }

    /// Ce code-barres correspond à plusieurs pressages Discogs (rééditions, éditions
    /// différentes...) : le premier est retenu par défaut, mais l'utilisateur peut ouvrir
    /// cette liste détaillée (pochette, année, pays, format, label) pour choisir le bon
    /// pressage — un simple menu texte ne suffisait pas à les distinguer.
    private func pressingPicker(selected: SearchResult, alternatives: [SearchResult]) -> some View {
        Button {
            showingPressingChoice = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.caption)
                Text("\(alternatives.count)")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.spinlogPink)
            .padding(6)
            .background(Color.spinlogPinkBadge, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choisir le pressage (\(alternatives.count) trouvés)")
        .sheet(isPresented: $showingPressingChoice) {
            PressingChoiceSheet(
                alternatives: alternatives,
                selectedId: selected.id,
                onSelect: { onSelectMatch($0) }
            )
        }
    }
}

/// Liste détaillée des pressages Discogs partageant un même code-barres, pour permettre de
/// choisir le bon en toute confiance (pochette, année, pays, format, label/référence).
private struct ReleasePreviewTarget: Identifiable, Hashable {
    let id: Int
    let coverURL: String?
}

private struct PressingChoiceSheet: View {
    let alternatives: [SearchResult]
    let selectedId: Int
    let onSelect: (SearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var previewTarget: ReleasePreviewTarget?

    var body: some View {
        NavigationStack {
            List(alternatives) { alternative in
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        onSelect(alternative)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            AsyncCoverImage(url: alternative.coverImage ?? alternative.thumb, cornerRadius: AppLayout.coverCornerRadius, targetSize: 88)
                                .frame(width: 88, height: 88)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(alternative.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)

                                if let yearCountry = yearCountryLine(for: alternative) {
                                    Text(yearCountry)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.appSecondaryText)
                                }

                                if let labelCatno = labelCatnoLine(for: alternative) {
                                    Text(labelCatno)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.appSecondaryText)
                                        .lineLimit(1)
                                }

                                if let format = alternative.format, !format.isEmpty {
                                    Text(format.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(Color.appTertiaryText)
                                        .lineLimit(2)
                                }

                                if let styleLine = styleLine(for: alternative) {
                                    Text(styleLine)
                                        .font(.caption)
                                        .foregroundStyle(Color.appTertiaryText)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 0)

                            if alternative.id == selectedId {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.spinlogPink)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        previewTarget = ReleasePreviewTarget(id: alternative.id, coverURL: alternative.coverImage ?? alternative.thumb)
                    } label: {
                        Image(systemName: "chevron.right.circle")
                            .font(.title3)
                            .foregroundStyle(Color.appTertiaryText)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Voir la fiche de cette release")
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .listRowSeparatorTint(Color.appSeparator)
            .navigationTitle("Choisir le pressage")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $previewTarget) { target in
                ReleaseDetailView(releaseId: target.id, initialCoverURL: target.coverURL)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func yearCountryLine(for result: SearchResult) -> String? {
        var parts: [String] = []
        if let year = result.year, !year.isEmpty {
            parts.append(year)
        }
        if let country = result.country, !country.isEmpty {
            parts.append(country)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// La référence catalogue (catno) est souvent l'élément le plus discriminant entre deux
    /// pressages Discogs partageant le même code-barres (ex. une réédition change de catno
    /// même quand le reste des métadonnées se ressemble).
    private func labelCatnoLine(for result: SearchResult) -> String? {
        var parts: [String] = []
        if let label = result.label?.first {
            parts.append(label)
        }
        if let catno = result.catno, !catno.isEmpty {
            parts.append("Cat. \(catno)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func styleLine(for result: SearchResult) -> String? {
        let styles = (result.style ?? []) + (result.genre ?? [])
        return styles.isEmpty ? nil : styles.joined(separator: ", ")
    }
}
