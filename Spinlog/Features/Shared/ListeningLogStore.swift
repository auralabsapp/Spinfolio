import Foundation
import Observation

/// Représente une session d'écoute horodatée rattachée à une release Discogs.
public struct ListeningSession: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let releaseId: Int
    public let timestamp: Date

    public init(id: UUID = UUID(), releaseId: Int, timestamp: Date = Date()) {
        self.id = id
        self.releaseId = releaseId
        self.timestamp = timestamp
    }
}

/// Store local persistant gérant le journal d'écoute des albums vinyles.
/// Sauvegarde locale sur l'appareil (UserDefaults codé en JSON), sans serveur distant.
///
/// Les données sont isolées par compte Discogs (`setActiveUsername`) : se déconnecter puis se
/// reconnecter avec un autre compte donne un journal d'écoute totalement séparé, et revenir au
/// premier compte restaure le sien.
@Observable
@MainActor
final class ListeningLogStore {
    static let shared = ListeningLogStore()

    /// Toutes les sessions d'écoute enregistrées, triées de la plus récente à la plus ancienne.
    private(set) var sessions: [ListeningSession] = []

    /// Compte Discogs actuellement actif, ou `nil` si personne n'est connecté.
    /// Piloté exclusivement par `DiscogsAuthManager` via `setActiveUsername`.
    private(set) var activeUsername: String?

    private let storageKeyBase = "com.spinlog.listeningSessions"
    /// Garantit que la migration depuis l'ancien stockage global (avant l'isolation par compte)
    /// ne se produit qu'une seule fois, vers le premier compte activé après cette mise à jour.
    private static let legacyMigrationFlagKey = "com.spinlog.listeningLogStore.migratedToPerAccount"

    private init() {}

    /// Bascule ce journal sur les données propres au compte Discogs indiqué : chaque mutation
    /// persiste déjà immédiatement, donc il suffit de recharger l'état en mémoire depuis le
    /// stockage propre à ce compte. Appelé par `DiscogsAuthManager` au lancement de l'app, à la
    /// connexion et à la déconnexion.
    func setActiveUsername(_ username: String?) {
        let normalized = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nonEmpty
        guard normalized != activeUsername else { return }
        activeUsername = normalized
        guard let normalized else {
            // Déconnecté : on vide l'état en mémoire sans toucher au disque, pour ne pas laisser
            // le journal d'un compte visible tant qu'aucun compte n'est actif.
            sessions = []
            return
        }
        load(for: normalized)
    }

    private func storageKey(for username: String) -> String {
        "\(storageKeyBase)_\(username)"
    }

    private func load(for username: String) {
        if let data = UserDefaults.standard.data(forKey: storageKey(for: username)),
           let decoded = try? JSONDecoder().decode([ListeningSession].self, from: data) {
            sessions = decoded.sorted { $0.timestamp > $1.timestamp }
        } else {
            sessions = []
        }
        migrateLegacyDataIfNeeded()
    }

    /// Reprend, une seule fois au total, le journal créé avant l'isolation par compte (stocké
    /// sous la clé globale non préfixée) pour le premier compte activé.
    private func migrateLegacyDataIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.legacyMigrationFlagKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.legacyMigrationFlagKey)

        guard sessions.isEmpty,
              let data = UserDefaults.standard.data(forKey: storageKeyBase),
              let decoded = try? JSONDecoder().decode([ListeningSession].self, from: data),
              !decoded.isEmpty else { return }

        sessions = decoded.sorted { $0.timestamp > $1.timestamp }
        persist()
    }

    private func persist() {
        guard let activeUsername else { return }
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: storageKey(for: activeUsername))
        }
        NotificationCenter.default.post(name: .listeningLogChanged, object: nil)
    }

    // MARK: - Actions de Log

    /// Enregistre une nouvelle écoute pour la release spécifiée et retourne la session créée (pour annulation éventuelle).
    @discardableResult
    func logListening(for releaseId: Int, date: Date = Date()) -> ListeningSession {
        let session = ListeningSession(releaseId: releaseId, timestamp: date)
        sessions.insert(session, at: 0)
        persist()
        CloudSyncEngine.shared.markSessionDirty(id: session.id)
        return session
    }

    /// Supprime une session d'écoute spécifique (par exemple lors du tap sur "Annuler" dans le toast).
    func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
        CloudSyncEngine.shared.markSessionDeleted(id: id)
    }

    // MARK: - Requêtes d'écoute

    /// Nombre total d'écoutes enregistrées pour une release.
    func playCount(for releaseId: Int) -> Int {
        sessions.filter { $0.releaseId == releaseId }.count
    }

    /// Date de la dernière écoute enregistrée pour une release.
    func lastListeningDate(for releaseId: Int) -> Date? {
        sessions.first(where: { $0.releaseId == releaseId })?.timestamp
    }

    /// Liste de toutes les sessions d'une release, de la plus récente à la plus ancienne.
    func sessions(for releaseId: Int) -> [ListeningSession] {
        sessions.filter { $0.releaseId == releaseId }
    }

    // MARK: - Synchronisation iCloud (compte premium)

    /// Identifiants de toutes les sessions enregistrées, pour la synchronisation initiale (même
    /// besoin que `TagStore.allTaggedInstanceIds()`) : les sessions créées avant l'existence de
    /// `CloudSyncEngine` (ou avant l'activation du compte premium) n'ont jamais déclenché
    /// `markSessionDirty` — il faut donc les repousser explicitement à chaque activation de
    /// compte, pas seulement les futures créations.
    func allSessionIds() -> [UUID] {
        sessions.map(\.id)
    }

    /// Session correspondant à cet identifiant, pour construire le contenu à envoyer vers iCloud.
    func session(id: UUID) -> ListeningSession? {
        sessions.first { $0.id == id }
    }

    /// Applique une session reçue d'iCloud (ajout ou mise à jour). N'écrit qu'en local : ne
    /// redéclenche pas d'envoi vers CloudKit, cette donnée en vient déjà.
    func applyRemoteSession(_ session: ListeningSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.timestamp > $1.timestamp }
        persist()
    }

    /// Applique une suppression de session reçue d'iCloud. N'écrit qu'en local.
    func applyRemoteSessionDeletion(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Sauvegarde & Restauration

    /// Remplace ou fusionne les sessions lors d'une restauration de sauvegarde.
    func restoreSessions(_ importedSessions: [ListeningSession]) {
        var existingSet = Set(sessions.map(\.id))
        var merged = sessions

        for session in importedSessions {
            if !existingSet.contains(session.id) {
                merged.append(session)
                existingSet.insert(session.id)
            }
        }

        self.sessions = merged.sorted { $0.timestamp > $1.timestamp }
        persist()
    }
}

extension Notification.Name {
    static let listeningLogChanged = Notification.Name("com.spinlog.listeningLogChanged")
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
