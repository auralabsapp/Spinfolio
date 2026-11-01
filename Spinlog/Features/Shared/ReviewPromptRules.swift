import Foundation

/// Règles pures de la demande d'avis App Store : quand une action de l'utilisateur mérite d'en
/// déclencher une, et quand l'app s'interdit d'en demander. Sans état ni interface, pour être
/// testées seules (voir `ReviewPromptStore` pour les compteurs et `ReviewPromptPresenter` pour l'affichage).
///
/// Les compteurs ne comptent que des actions faites dans l'app : ni l'import d'un compte, ni les
/// ajouts faits sur Discogs, ni la synchro iCloud, ni l'arrêt automatique d'une écoute. Les grades
/// n'y sont pour rien (ils se débloquent aussi à l'import d'un compte important).
nonisolated enum ReviewPromptRules {
    /// Albums ajoutés à la collection depuis l'app (la wantlist ne compte pas).
    static let albumMilestones = [10, 50]
    /// Écoutes sur platine arrêtées par l'utilisateur : la première, puis la dixième.
    static let listeningMilestones = [1, 10]
    /// Une écoute arrêtée avant cette durée (essai, doigt qui glisse) ne compte pas.
    static let minimumListeningDuration: TimeInterval = 60
    /// Délai minimal entre deux demandes. iOS plafonne déjà à trois affichages par an : ce délai
    /// évite en plus de revenir trop vite, et d'enchaîner deux paliers franchis ensemble.
    static let minimumDaysBetweenRequests = 60

    /// Vrai si `milestones` contient un palier franchi en passant de `previous` à `new`.
    static func crossedMilestone(previous: Int, new: Int, milestones: [Int]) -> Bool {
        milestones.contains { previous < $0 && $0 <= new }
    }

    /// Vrai si une écoute de cette durée compte (arrêtée par l'utilisateur, pas par l'arrêt automatique).
    static func countsAsListening(duration: TimeInterval) -> Bool {
        duration >= minimumListeningDuration
    }

    /// Vrai si l'app a le droit de demander un avis maintenant : une seule demande par version de
    /// l'app, et au moins `minimumDaysBetweenRequests` jours depuis la précédente. La date est celle
    /// de l'appel (on ne sait pas si le système a affiché la demande : il en décide seul).
    static func canRequest(now: Date, lastRequestDate: Date?, lastRequestVersion: String?, currentVersion: String) -> Bool {
        if lastRequestVersion == currentVersion { return false }
        guard let lastRequestDate else { return true }
        let minimum = TimeInterval(minimumDaysBetweenRequests) * 24 * 3600
        return now.timeIntervalSince(lastRequestDate) >= minimum
    }
}
