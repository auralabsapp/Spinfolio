import Foundation

/// Instantané de l'état de la synchro iCloud, pour la section de diagnostic des tests
/// (`CloudSyncDiagnosticSection`, visible seulement hors App Store). Lecture seule : aucun de ces
/// champs ne pilote le moteur.
nonisolated struct CloudSyncDiagnostic: Sendable {
    /// Le moteur `CKSyncEngine` existe (Premium actif et interrupteur allumé au démarrage).
    let engineRunning: Bool
    let isUserEnabled: Bool
    let hasPremiumAccess: Bool
    /// Compte Discogs dont la zone iCloud est synchronisée ; `nil` tant que personne n'est connecté.
    let activeUsername: String?
    /// Fusion initiale avec iCloud faite pour ce compte sur cet appareil.
    let hydrated: Bool
    /// Poussée initiale des données locales faite pour ce compte sur cet appareil.
    let initialPushDone: Bool
    /// Changements en attente d'envoi, tous comptes confondus puis pour le compte actif.
    let pendingChanges: Int
    let pendingChangesForActiveAccount: Int
    /// Dernier bilan d'envoi (« 5 enregistrements sauvés, 0 échec ») et son horaire.
    let lastSendSummary: String?
    let lastSendDate: Date?
    /// Dernier échec d'envoi ou de récupération, avec l'horaire.
    let lastFailure: String?
    let lastFailureDate: Date?
}
