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
    @State private var showingCloseConfirmation = false

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
            // Réseau perdu (fréquent en brocante, en sous-sol de disquaire) : on reste sur l'écran.
            // Les codes déjà scannés sont conservés et les recherches en attente repartent au
            // retour de la connexion — auparavant, l'écran se fermait et tout le lot était perdu.
            .safeAreaInset(edge: .top) {
                if !networkMonitor.isConnected {
                    OfflineBannerView(customMessage: String(localized: "Hors ligne : les codes scannés sont conservés et seront recherchés au retour du réseau."))
                }
            }
        }
        .interactiveDismissDisabled(!viewModel.items.isEmpty)
        .task { await loadFolders() }
        .confirmationDialog(
            "Fermer le scan par lot ?",
            isPresented: $showingCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Fermer et garder les codes") {
                dismiss()
            }
            Button("Supprimer les codes scannés", role: .destructive) {
                viewModel.clearAll()
                dismiss()
            }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("Les \(viewModel.items.count) codes scannés sont conservés : tu les retrouveras à la prochaine ouverture du scan par lot.")
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
                    requestClose()
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
                SheetCloseButton(action: requestClose)
            }
        }
    }

    /// Fermeture directe s'il n'y a rien à perdre, sinon confirmation (garder ou supprimer).
    private func requestClose() {
        if viewModel.items.isEmpty {
            dismiss()
        } else {
            showingCloseConfirmation = true
        }
    }

    // MARK: - Phase 1 : scan continu

    private var scanningView: some View {
        ZStack(alignment: .bottom) {
            CameraScannerGate {
                BarcodeScannerRepresentable(
                    onScan: { code in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.scan(code: code)
                    },
                    onError: { _ in },
                    continuous: true
                )
                .ignoresSafeArea()
            }

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

#Preview {
    BatchScanView()
}
