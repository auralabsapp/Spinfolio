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
            .navigationTitle(phase == .scanning ? "Scan par lot" : "Revue du scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task { await loadFolders() }
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
                Button("Fermer") { dismiss() }
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

            Text(scanCounterText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.bottom, 32)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.items.count)
        }
    }

    private var scanCounterText: String {
        let count = viewModel.items.count
        if count == 0 { return "Scanne un code-barres" }
        return count == 1 ? "1 code scanné" : "\(count) codes scannés"
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
                            onToggle: { viewModel.toggleSelection(item) }
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.remove(item)
                            } label: {
                                Label("Retirer", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)

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
                AsyncCoverImage(url: result.thumb ?? result.coverImage, cornerRadius: 6)
                    .frame(width: 44, height: 44)
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
        }
        .padding(.vertical, 4)
        .opacity(item.status == .notFound ? 0.5 : 1)
    }
}

#Preview {
    BatchScanView()
}
