import SwiftUI

/// Création, renommage, suppression des dossiers Discogs et choix du dossier d'ajout par défaut.
/// Lit les dossiers depuis `CollectionViewModel.shared` (source unique) et le rafraîchit après
/// chaque modification, pour que l'onglet Collection reflète immédiatement le changement.
@Observable
@MainActor
final class FolderManagementViewModel {
    private(set) var defaultFolderId: Int = CollectionPreferencesStore.alwaysAskFolderId
    private(set) var isWorking = false
    private(set) var progressMessage: String?
    var errorMessage: String?

    private let authManager = DiscogsAuthManager.shared
    private let collection = CollectionViewModel.shared

    /// Dossiers système d'abord (All, Uncategorized), puis les autres par ordre alphabétique.
    var folders: [CollectionFolder] {
        let all = collection.folders
        let system = all.filter { Self.isSystem($0.id) }.sorted { $0.id < $1.id }
        let custom = all.filter { !Self.isSystem($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return system + custom
    }

    static func isSystem(_ folderId: Int) -> Bool {
        folderId == DiscogsConstants.allFolderId || folderId == DiscogsConstants.uncategorizedFolderId
    }

    func nameExists(_ name: String, excluding folderId: Int? = nil) -> Bool {
        collection.folders.contains {
            $0.id != folderId && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    func load() async {
        if let username = authManager.username {
            defaultFolderId = CollectionPreferencesStore.defaultAddFolderId(for: username)
        }
        if collection.folders.isEmpty {
            await collection.refresh()
        }
    }

    func setDefault(_ folderId: Int) {
        guard let username = authManager.username, folderId != DiscogsConstants.allFolderId else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        defaultFolderId = folderId
        CollectionPreferencesStore.setDefaultAddFolderId(folderId, for: username)
    }

    func create(name: String) async {
        await perform { username, credentials in
            try await DiscogsAPIClient.shared.createCollectionFolder(username: username, name: name, credentials: credentials)
        }
    }

    func rename(_ folder: CollectionFolder, to name: String) async {
        guard !Self.isSystem(folder.id) else { return }
        await perform { username, credentials in
            try await DiscogsAPIClient.shared.renameCollectionFolder(
                username: username, folderId: folder.id, name: name, credentials: credentials
            )
        }
    }

    /// Discogs refuse de supprimer un dossier non vide : chaque exemplaire est d'abord déplacé
    /// vers Uncategorized, puis le dossier vide est supprimé.
    func delete(_ folder: CollectionFolder) async {
        guard !Self.isSystem(folder.id) else { return }
        await perform { username, credentials in
            let api = DiscogsAPIClient.shared
            let items = try await api.fetchAllCollectionItems(
                username: username, folderId: folder.id, credentials: credentials
            )
            for (index, item) in items.enumerated() {
                self.progressMessage = String(localized: "Déplacement vers Uncategorized : \(index + 1)/\(items.count)")
                try await api.moveCollectionInstance(
                    username: username,
                    folderId: folder.id,
                    releaseId: item.releaseId,
                    instanceId: item.instanceId,
                    toFolderId: DiscogsConstants.uncategorizedFolderId,
                    credentials: credentials
                )
            }
            self.progressMessage = String(localized: "Suppression du dossier…")
            try await api.deleteCollectionFolder(username: username, folderId: folder.id, credentials: credentials)
            OfflineSyncQueue.shared.retargetActions(fromFolderId: folder.id, toFolderId: DiscogsConstants.uncategorizedFolderId)

            if self.defaultFolderId == folder.id {
                CollectionPreferencesStore.setDefaultAddFolderId(CollectionPreferencesStore.alwaysAskFolderId, for: username)
                self.defaultFolderId = CollectionPreferencesStore.alwaysAskFolderId
            }
        }
    }

    private func perform(_ work: (String, DiscogsCredentials) async throws -> Void) async {
        guard let (username, credentials) = authManager.session else {
            errorMessage = String(localized: "Connecte-toi à Discogs pour gérer tes dossiers.")
            return
        }
        if DemoMode.isActive {
            errorMessage = AppMessages.demoModificationBlocked
            return
        }
        guard NetworkMonitor.shared.isConnected else {
            errorMessage = String(localized: "La gestion des dossiers nécessite une connexion réseau.")
            return
        }
        isWorking = true
        do {
            try await work(username, credentials)
        } catch {
            errorMessage = String(localized: "Discogs a refusé l'opération : \(error.localizedDescription)")
        }
        // Rafraîchi même après un échec partiel (ex: suppression interrompue après quelques
        // déplacements), pour afficher l'état réel côté Discogs.
        await collection.refresh()
        progressMessage = nil
        isWorking = false
    }
}

/// Cible de la sheet de saisie d'un nom : création (`folder == nil`) ou renommage.
struct FolderNameRequest: Identifiable {
    let id = UUID()
    let folder: CollectionFolder?
}

struct FolderManagementView: View {
    @State private var viewModel = FolderManagementViewModel()
    @State private var nameRequest: FolderNameRequest?
    @State private var folderToDelete: CollectionFolder?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    nameRequest = FolderNameRequest(folder: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.title3)
                            .foregroundStyle(Color.spinlogPink)
                        Text("Créer un dossier")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.spinlogPink)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .appleMusicGroupedCard()
                .disabled(viewModel.isWorking)

                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(title: "Dossier d'ajout par défaut", icon: "tray.and.arrow.down.fill")
                    alwaysAskRow
                        .appleMusicGroupedCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(title: "Dossiers (\(viewModel.folders.count))", icon: "folder.fill")
                    GroupedListCard(items: viewModel.folders, id: \.id) { folder in
                        folderRow(folder)
                    }
                    (SwipeActionsSupport.isAvailable ? Text("Touche un dossier pour en faire le dossier d'ajout par défaut. Glisse vers la gauche pour le renommer ou le supprimer.") : Text("Touche un dossier pour en faire le dossier d'ajout par défaut. Maintiens le doigt dessus pour le renommer ou le supprimer."))
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }

                explanationCard
            }
            .padding()
        }
        .swipeActionsContainerIfAvailable()
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Gestion des dossiers")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isWorking {
                workingOverlay
            }
        }
        .task { await viewModel.load() }
        .refreshable { await CollectionViewModel.shared.refresh() }
        .sheet(item: $nameRequest) { request in
            FolderNameSheet(folder: request.folder, viewModel: viewModel)
        }
        .confirmationDialog(
            "Supprimer le dossier",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: folderToDelete
        ) { folder in
            Button("Supprimer", role: .destructive) {
                Task { await viewModel.delete(folder) }
            }
            Button("Annuler", role: .cancel) {}
        } message: { folder in
            Text("Supprimer « \(folder.name) » ? Ses \(folder.count) exemplaires seront déplacés vers Uncategorized.")
        }
        .errorAlert(message: $viewModel.errorMessage)
    }

    private var alwaysAskRow: some View {
        Button {
            viewModel.setDefault(CollectionPreferencesStore.alwaysAskFolderId)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.folder")
                    .foregroundStyle(Color.appSecondaryText)
                Text("Toujours demander")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if viewModel.defaultFolderId == CollectionPreferencesStore.alwaysAskFolderId {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.spinlogPink)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func folderRow(_ folder: CollectionFolder) -> some View {
        let isSystem = FolderManagementViewModel.isSystem(folder.id)
        let canBeDefault = folder.id != DiscogsConstants.allFolderId
        HStack(spacing: 12) {
            Image(systemName: isSystem ? "folder" : "folder.fill")
                .foregroundStyle(isSystem ? Color.appSecondaryText : Color.spinlogPink)
            Text(folder.name)
                .font(.subheadline.weight(.medium))
            if isSystem {
                Label("Système", systemImage: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appSecondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Spacer()
            Text("\(folder.count) ex.")
                .font(.footnote)
                .foregroundStyle(Color.appSecondaryText)
            if viewModel.defaultFolderId == folder.id {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spinlogPink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if canBeDefault { viewModel.setDefault(folder.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(canBeDefault ? .isButton : [])
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSystem {
                Button(role: .destructive) {
                    folderToDelete = folder
                } label: {
                    Label("Supprimer", systemImage: "trash.fill")
                }
                .tint(.red)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Supprimer ce dossier")

                Button {
                    nameRequest = FolderNameRequest(folder: folder)
                } label: {
                    Label("Renommer", systemImage: "pencil")
                }
                .tint(.orange)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Renommer ce dossier")
            }
        }
        .contextMenu {
            if canBeDefault {
                Button {
                    viewModel.setDefault(folder.id)
                } label: {
                    Label("Dossier par défaut", systemImage: "checkmark.circle")
                }
            }
            if !isSystem {
                Button {
                    nameRequest = FolderNameRequest(folder: folder)
                } label: {
                    Label("Renommer", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    folderToDelete = folder
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            }
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Supprimer un dossier déplace automatiquement tous les exemplaires qu'il contient vers le dossier Uncategorized.")
            } icon: {
                Image(systemName: "arrow.uturn.down.circle.fill")
                    .foregroundStyle(Color.appWarning)
            }
            Label {
                Text("Les dossiers All et Uncategorized sont des dossiers système de Discogs : ils ne peuvent être ni renommés, ni supprimés.")
            } icon: {
                Image(systemName: "lock.circle.fill")
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.appSecondaryText)
        .padding(14)
        .appleMusicGroupedCard()
    }

    private var workingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let message = viewModel.progressMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Saisie du nom d'un dossier, pour une création (`folder == nil`) ou un renommage.
struct FolderNameSheet: View {
    let folder: CollectionFolder?
    let viewModel: FolderManagementViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var isFieldFocused: Bool

    init(folder: CollectionFolder?, viewModel: FolderManagementViewModel) {
        self.folder = folder
        self.viewModel = viewModel
        self._name = State(initialValue: folder?.name ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        !trimmedName.isEmpty && viewModel.nameExists(trimmedName, excluding: folder?.id)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isDuplicate && trimmedName != folder?.name
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nom du dossier")
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondaryText)

                TextField("Nom du dossier", text: $name)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .appleMusicGroupedCard()
                    .focused($isFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(save)

                if isDuplicate {
                    Label("Un dossier porte déjà ce nom.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.appWarning)
                }
                Spacer()
            }
            .padding()
            .background(Color.appBackground)
            .navigationTitle(folder == nil ? "Nouveau dossier" : "Renommer le dossier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // `Text` dans chaque branche : un ternaire de littéraux deviendrait une `String`
                    // non traduite.
                    Button(action: save) {
                        folder == nil ? Text("Créer") : Text("OK")
                    }
                        .accessibilityLabel(folder == nil ? Text("Créer le dossier") : Text("Enregistrer le nom du dossier"))
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                        .tint(Color.spinlogPink)
                }
            }
            .onAppear { isFieldFocused = true }
        }
        .presentationDetents([.height(220), .medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard canSave else { return }
        let newName = trimmedName
        let target = folder
        dismiss()
        Task {
            if let target {
                await viewModel.rename(target, to: newName)
            } else {
                await viewModel.create(name: newName)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FolderManagementView()
    }
}
