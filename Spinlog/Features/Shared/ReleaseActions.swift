import SwiftUI

/// Actions "ajouter à la collection / à la wantlist" et état de possession, partagés entre
/// la recherche, le détail d'un master et le résultat de scan. Gère le mode hors ligne
/// avec mise en file d'attente (OfflineSyncQueue) et respect du mode lecture seule si TTL > 6h.
@Observable
@MainActor
final class ReleaseActions {
    var isWorking = false
    var message: String?
    /// Exemplaire déjà présent dans la collection pour cette release, s'il existe — sert à la
    /// fois à masquer le bouton d'ajout et à alimenter la fiche d'édition des champs personnalisés.
    private(set) var collectionInstance: CollectionItem?
    private(set) var collectionFields: [CollectionField] = []

    /// Dossiers proposés lors de l'ajout, et release en attente de confirmation de dossier.
    private(set) var folders: [CollectionFolder] = []
    var isChoosingFolder = false
    private var pendingReleaseId: Int?

    var isInCollection: Bool { collectionInstance != nil }

    private let authManager = DiscogsAuthManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private let localStore = LocalDataStore.shared
    private let syncQueue = OfflineSyncQueue.shared

    /// Vérifie si la release est déjà dans la collection (et charge les champs personnalisés si oui).
    func checkIfInCollection(releaseId: Int) async {
        guard let username = authManager.username else {
            collectionInstance = nil
            return
        }

        if !networkMonitor.isConnected {
            // Recherche dans le cache local SwiftData
            let cached = localStore.getCollectionItems(username: username, folderId: 0)
            collectionInstance = cached.first { $0.releaseId == releaseId }
            return
        }

        guard let credentials = authManager.credentials else {
            collectionInstance = nil
            return
        }

        do {
            let instancesResponse = try await DiscogsAPIClient.shared.collectionInstances(
                username: username, releaseId: releaseId, credentials: credentials
            )
            collectionInstance = instancesResponse.releases.first
            if collectionInstance != nil {
                collectionFields = try await DiscogsAPIClient.shared.collectionFields(
                    username: username, credentials: credentials
                ).fields
            }
        } catch {
            collectionInstance = nil
        }
    }

    /// Reflète localement une note/des champs personnalisés déjà enregistrés par
    /// `CollectionItemEditSheet` (qui gère lui-même les appels réseau).
    func applyEditedValues(rating: Int, notes: [CollectionFieldValue]) {
        collectionInstance?.rating = rating
        collectionInstance?.notes = notes
    }

    /// Lance le choix du dossier de destination : charge la liste des dossiers puis ouvre le
    /// sélecteur. `confirmAddToCollection` termine l'ajout une fois le dossier choisi.
    func beginAddToCollection(releaseId: Int) async {
        guard let username = authManager.username else {
            message = "Connecte-toi à Discogs pour ajouter à ta collection."
            return
        }

        // Si hors ligne et données de plus de 6h (Option B) : blocage des modifications
        if !networkMonitor.isConnected && localStore.isCollectionStale(username: username, folderId: 0) {
            message = "Mode hors ligne (données de plus de 6h) : ajout bloqué."
            return
        }

        if !networkMonitor.isConnected {
            // Lecture des dossiers en cache
            let cachedFolders = localStore.getFolders(username: username).filter { $0.id != 0 }
            folders = cachedFolders.isEmpty ? [CollectionFolder(id: 1, name: "Uncategorized", count: 0)] : cachedFolders
            pendingReleaseId = releaseId
            isChoosingFolder = true
            return
        }

        guard let credentials = authManager.credentials else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await DiscogsAPIClient.shared.collectionFolders(username: username, credentials: credentials)
            folders = response.folders.filter { $0.id != 0 }
            pendingReleaseId = releaseId
            isChoosingFolder = true
        } catch {
            message = error.localizedDescription
        }
    }

    func confirmAddToCollection(folderId: Int) async {
        guard let releaseId = pendingReleaseId, let username = authManager.username else { return }

        // Mode hors ligne
        if !networkMonitor.isConnected {
            let action = PendingAction(type: .addToCollection, releaseId: releaseId, folderId: folderId)
            syncQueue.enqueue(action)
            message = "Ajout enregistré hors ligne (sera synchronisé à la reconnexion)."
            pendingReleaseId = nil
            return
        }

        guard let credentials = authManager.credentials else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await DiscogsAPIClient.shared.addToCollection(
                username: username, folderId: folderId, releaseId: releaseId, credentials: credentials
            )
            message = "Ajouté à la collection."
            await checkIfInCollection(releaseId: releaseId)
        } catch {
            // Repli sur la file de synchronisation si perte réseau en cours de route
            let action = PendingAction(type: .addToCollection, releaseId: releaseId, folderId: folderId)
            syncQueue.enqueue(action)
            message = "Ajout enregistré hors ligne (sera synchronisé à la reconnexion)."
        }
        pendingReleaseId = nil
    }

    func addToWantlist(releaseId: Int) async {
        guard let username = authManager.username else {
            message = "Connecte-toi à Discogs pour ajouter à ta wantlist."
            return
        }

        // Si hors ligne et données de plus de 6h : blocage
        if !networkMonitor.isConnected && localStore.isWantlistStale(username: username) {
            message = "Mode hors ligne (données de plus de 6h) : ajout bloqué."
            return
        }

        if !networkMonitor.isConnected {
            let action = PendingAction(type: .addToWantlist, releaseId: releaseId)
            syncQueue.enqueue(action)
            message = "Ajout enregistré hors ligne (sera synchronisé à la reconnexion)."
            return
        }

        guard let credentials = authManager.credentials else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await DiscogsAPIClient.shared.addToWantlist(username: username, releaseId: releaseId, credentials: credentials)
            message = "Ajouté à la wantlist."
        } catch {
            let action = PendingAction(type: .addToWantlist, releaseId: releaseId)
            syncQueue.enqueue(action)
            message = "Ajout enregistré hors ligne (sera synchronisé à la reconnexion)."
        }
    }
}

/// Menu toolbar réutilisable pour agir sur une release depuis n'importe quel écran de détail.
/// Masqué si la release est déjà dans la collection (inutile de proposer de l'y ajouter à nouveau).
/// `actions` est possédé par l'appelant, qui peut ainsi réutiliser le même état ailleurs
/// (ex: la tuile "Notes" sur la fiche release).
struct ReleaseActionsMenu: View {
    let releaseId: Int
    var actions: ReleaseActions

    var body: some View {
        Menu {
            if !actions.isInCollection {
                Button {
                    Task { await actions.beginAddToCollection(releaseId: releaseId) }
                } label: {
                    Label("Ajouter à la collection", systemImage: "square.stack.fill")
                }
            } else {
                Label("Dans la collection", systemImage: "checkmark.circle.fill")
            }

            Button {
                Task { await actions.addToWantlist(releaseId: releaseId) }
            } label: {
                Label("Ajouter à la wantlist", systemImage: "heart.fill")
            }
        } label: {
            if actions.isWorking {
                ProgressView()
                    .tint(.white)
                    .liquidGlassCircle(size: 38)
            } else {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .liquidGlassCircle(size: 38)
            }
        }
        .buttonStyle(.plain)
        .disabled(actions.isWorking)
        .confirmationDialog(
            "Ajouter dans quel dossier ?",
            isPresented: Binding(get: { actions.isChoosingFolder }, set: { actions.isChoosingFolder = $0 })
        ) {
            ForEach(actions.folders) { folder in
                Button("\(folder.name) (\(folder.count))") {
                    Task { await actions.confirmAddToCollection(folderId: folder.id) }
                }
            }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Discogs", isPresented: Binding(
            get: { actions.message != nil },
            set: { if !$0 { actions.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actions.message ?? "")
        }
    }
}
