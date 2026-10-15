import SwiftUI

/// Scan par lot de codes-barres (fonctionnalité premium), pensé pour les brocantes/disquaires :
/// la caméra reste active pour enchaîner les scans sans revenir à la recherche à chaque fois,
/// puis une revue groupée permet d'ajouter en une fois les disques reconnus à la collection
/// ou à la wantlist.
struct BatchScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = BatchScanViewModel()
    @State private var phase: Phase = .scanning
    @State private var availableFolders: [CollectionFolder] = []
    @State private var selectedFolderId: Int?
    @State private var authManager = DiscogsAuthManager.shared
    @State private var networkMonitor = NetworkMonitor.shared

    private enum Phase {
        case scanning
        case review
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .scanning:
                    scanningView
                case .review:
                    reviewView
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(phase == .scanning ? "Scan par lot" : "Revue du scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task { await loadFolders() }
        // Scan comme revue groupée nécessitent tous deux le réseau (lookup code-barres, ajout
        // à la collection) : si la connexion tombe pendant que cet écran est ouvert, on revient
        // à la recherche plutôt que de laisser l'utilisateur continuer dans un état cassé.
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            if !isConnected {
                dismiss()
            }
        }
        .alert("Discogs", isPresented: Binding(
            get: { viewModel.message != nil },
            set: { if !$0 { viewModel.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.message ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(phase == .scanning ? "Annuler" : "Retour au scan") {
                if phase == .scanning {
                    dismiss()
                } else {
                    withAnimation { phase = .scanning }
                }
            }
        }
        if phase == .scanning {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Terminer (\(viewModel.items.count))") {
                    withAnimation { phase = .review }
                }
                .disabled(viewModel.items.isEmpty)
                .bold()
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                SheetCloseButton()
            }
        }
    }

    // MARK: - Phase 1 : scan continu

    private var scanningView: some View {
        ZStack(alignment: .bottom) {
            BarcodeScannerRepresentable(
                onScan: { code in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.scan(code: code)
                },
                onError: { _ in },
                continuous: true
            )
            .ignoresSafeArea()

            scanCounterText
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.bottom, 32)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.items.count)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var scanCounterText: Text {
        let count = viewModel.items.count
        if count == 0 { return Text("Scanne un code-barres") }
        return Text("\(count) codes scannés")
    }

    // MARK: - Phase 2 : revue groupée

    private var reviewView: some View {
        VStack(spacing: 0) {
            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "Aucun code scanné",
                    systemImage: "barcode.viewfinder",
                    description: Text("Retourne au scan pour ajouter des codes-barres.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if !availableFolders.isEmpty {
                    folderPicker
                }

                List {
                    ForEach(viewModel.items) { item in
                        BatchScanRow(
                            item: item,
                            isInCollection: viewModel.isAlreadyInCollection(item),
                            isInWantlist: viewModel.isAlreadyInWantlist(item),
                            onToggle: { viewModel.toggleSelection(item) },
                            onSelectMatch: { result in viewModel.selectMatch(result, for: item) }
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.remove(item)
                            } label: {
                                Label("Retirer", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowSeparatorTint(Color.appSeparator)

                bulkActionsBar
            }
        }
    }

    private var folderPicker: some View {
        HStack(spacing: 10) {
            Text("Dossier")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
            Spacer()
            Picker("Dossier", selection: $selectedFolderId) {
                Text("Toujours demander").tag(Int?.none)
                ForEach(availableFolders) { folder in
                    Text(folder.name).tag(Int?.some(folder.id))
                }
            }
            .pickerStyle(.menu)
            .tint(Color.spinlogPink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var bulkActionsBar: some View {
        VStack(spacing: 10) {
            if viewModel.isAdding, let progress = viewModel.addProgressText {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(progress)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.addSelectedToCollection(folderId: selectedFolderId) }
                } label: {
                    Label("Collection", systemImage: "square.stack.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.spinlogPink)

                Button {
                    Task { await viewModel.addSelectedToWantlist() }
                } label: {
                    Label("Wantlist", systemImage: "heart.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(Color.spinlogPink)
            }
            .disabled(viewModel.selectedFoundItems.isEmpty || viewModel.isAdding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func loadFolders() async {
        guard let username = authManager.username else { return }
        let result = await FolderPickerLoader.loadFolders(
            username: username,
            networkMonitor: NetworkMonitor.shared,
            localStore: LocalDataStore.shared,
            credentials: authManager.credentials
        )
        if case .success(let folders) = result {
            availableFolders = folders
        }
    }
}

private struct BatchScanRow: View {
    let item: BatchScanItem
    let isInCollection: Bool
    let isInWantlist: Bool
    let onToggle: () -> Void
    let onSelectMatch: (SearchResult) -> Void

    @State private var showingPressingChoice = false

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

            if case .found(let selected) = item.status, item.alternatives.count > 1 {
                pressingPicker(selected: selected, alternatives: item.alternatives)
            }
        }
        .padding(.vertical, 4)
        .opacity(item.status == .notFound ? 0.5 : 1)
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
                            AsyncCoverImage(url: alternative.coverImage ?? alternative.thumb, cornerRadius: 8, targetSize: 88)
                                .frame(width: 88, height: 88)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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

#Preview {
    BatchScanView()
}
