import Foundation
import Observation

/// Compteurs d'actions faites dans l'app (albums ajoutés, écoutes sur platine arrêtées) et état de
/// la demande d'avis (voir `ReviewPromptRules`). Les compteurs sont propres à chaque compte Discogs,
/// locaux (jamais synchronisés par iCloud : un appareil qui reçoit un compte repart de zéro, sans
/// gravité) ; la date de la dernière demande est propre à l'appareil, puisque la limite d'Apple l'est aussi.
///
/// Rien n'est compté en démo, ni sans compte connecté.
@Observable
@MainActor
final class ReviewPromptStore {
    static let shared = ReviewPromptStore()

    private enum Keys {
        static let albumsAdded = "com.spinlog.reviewPrompt.albumsAdded"
        static let listensStopped = "com.spinlog.reviewPrompt.listensStopped"
        static let all = [albumsAdded, listensStopped]
        static let lastRequestDate = "com.spinlog.reviewPrompt.lastRequestDate"
        static let lastRequestVersion = "com.spinlog.reviewPrompt.lastRequestVersion"

        static func key(_ base: String, for username: String) -> String { "\(base)_\(username)" }
    }

    private let defaults: UserDefaults
    private let appVersion: String
    private let isDemo: () -> Bool
    private(set) var activeUsername: String?

    /// Identifiant de la demande à présenter : change à chaque palier franchi, `nil` sinon. Lu par
    /// `ReviewPromptPresenter`, qui attend un moment calme avant d'appeler le système.
    private(set) var pendingRequestID: UUID?

    init(
        defaults: UserDefaults = .standard,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        isDemo: @escaping () -> Bool = { DemoMode.isActive }
    ) {
        self.defaults = defaults
        self.appVersion = appVersion
        self.isDemo = isDemo
    }

    func setActiveUsername(_ username: String?) {
        activeUsername = Self.normalize(username)
        pendingRequestID = nil
    }

    /// Supprime les compteurs d'un compte (« Supprimer mes données »).
    func clearAccountData(for username: String) {
        guard let user = Self.normalize(username) else { return }
        for base in Keys.all { defaults.removeObject(forKey: Keys.key(base, for: user)) }
        if activeUsername == user { pendingRequestID = nil }
    }

    // MARK: - Actions comptées

    /// Un album vient d'être ajouté à la collection depuis l'app (envoyé à Discogs, ou mis en file
    /// hors ligne : l'utilisateur l'a bien fait).
    func recordCollectionAdd(now: Date = Date()) {
        increment(Keys.albumsAdded, milestones: ReviewPromptRules.albumMilestones, now: now)
    }

    /// Une écoute sur platine vient d'être arrêtée par l'utilisateur (jamais par l'arrêt automatique).
    func recordListeningStopped(duration: TimeInterval, now: Date = Date()) {
        guard ReviewPromptRules.countsAsListening(duration: duration) else { return }
        increment(Keys.listensStopped, milestones: ReviewPromptRules.listeningMilestones, now: now)
    }

    private func count(for base: String) -> Int {
        guard let activeUsername else { return 0 }
        return defaults.integer(forKey: Keys.key(base, for: activeUsername))
    }

    var albumsAddedCount: Int { count(for: Keys.albumsAdded) }
    var listensStoppedCount: Int { count(for: Keys.listensStopped) }

    private func increment(_ base: String, milestones: [Int], now: Date) {
        guard !isDemo(), let activeUsername else { return }
        let key = Keys.key(base, for: activeUsername)
        let previous = defaults.integer(forKey: key)
        let new = previous + 1
        defaults.set(new, forKey: key)
        guard ReviewPromptRules.crossedMilestone(previous: previous, new: new, milestones: milestones),
              canRequest(now: now) else { return }
        pendingRequestID = UUID()
    }

    // MARK: - Demande

    private var lastRequestDate: Date? {
        let seconds = defaults.double(forKey: Keys.lastRequestDate)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    private func canRequest(now: Date) -> Bool {
        ReviewPromptRules.canRequest(
            now: now,
            lastRequestDate: lastRequestDate,
            lastRequestVersion: defaults.string(forKey: Keys.lastRequestVersion),
            currentVersion: appVersion
        )
    }

    /// Appelé juste avant d'appeler le système : revérifie les règles (une demande a pu être faite
    /// entre-temps) et consigne la date. Vrai si l'appel peut avoir lieu. La date est enregistrée
    /// même si le système n'affiche rien (on ne peut pas le savoir) : au pire, le prochain essai est
    /// repoussé de `minimumDaysBetweenRequests` jours.
    func consumePendingRequest(now: Date = Date()) -> Bool {
        guard pendingRequestID != nil, !isDemo(), canRequest(now: now) else {
            pendingRequestID = nil
            return false
        }
        pendingRequestID = nil
        defaults.set(now.timeIntervalSince1970, forKey: Keys.lastRequestDate)
        defaults.set(appVersion, forKey: Keys.lastRequestVersion)
        return true
    }

    /// Abandonne la demande en attente sans consigner de date (l'app n'a pas trouvé de moment
    /// calme) : le prochain palier pourra en redéclencher une.
    func discardPendingRequest() {
        pendingRequestID = nil
    }

    private static func normalize(_ username: String?) -> String? {
        guard let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
