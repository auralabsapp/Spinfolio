import Foundation
import Observation
import OSLog

nonisolated private let gradeLogger = Logger(subsystem: AppInfo.logSubsystem, category: "Grades")

/// Un grade qui vient d'être franchi et qu'il faut fêter (voir `GradeCelebrationView`).
struct GradeCelebration: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Un palier vient d'être franchi.
        case newGrade
        /// Premier grade d'un compte (collection ou écoutes déjà là avant les grades) : on présente
        /// le plus haut, une seule fois.
        case welcome
    }

    let id = UUID()
    let track: GradeTrack
    /// Indice du plus haut palier franchi.
    let tier: Int
    /// Nombre de paliers franchis d'un coup (plus d'un : un seul est fêté, les autres sont mentionnés).
    let tiersGained: Int
    var kind: Kind = .newGrade
}

/// Ce qui est synchronisé par iCloud : les grades et le fait que l'accueil a déjà été fait.
struct SyncedGrades: Codable, Sendable {
    let unlocks: [GradeUnlock]
    let welcomeDecided: Bool
}

/// Grades de l'utilisateur : quels paliers il a franchis, et quand. Un grade acquis ne se perd
/// jamais (on ne retire un disque ni une écoute sans toucher à ce qu'on a gagné) ; seul le nombre
/// courant, mémorisé pour la jauge, peut redescendre.
///
/// Isolé par compte Discogs (`setActiveUsername`, comme `TagStore`) et synchronisé par
/// `CloudSyncEngine` (un enregistrement singleton fusionné, voir `GradeRules.merge`). Jamais
/// évalué ni conservé pour la démo.
@Observable
@MainActor
final class GradeStore {
    static let shared = GradeStore()

    private(set) var unlocks: [GradeUnlock] = []
    /// Dernier nombre fiable connu pour chaque parcours (jauge de Réglages) : propre à l'appareil,
    /// jamais synchronisé.
    private(set) var counts: [GradeTrack: Int] = [:]
    /// L'accueil (carte du plus haut grade de départ) a déjà été décidé pour ce compte : montré, ou
    /// écarté parce que le compte partait de zéro. Synchronisé pour ne pas le refaire sur un autre appareil.
    private(set) var welcomeDecided = false
    private(set) var activeUsername: String?
    /// Grade à fêter à la prochaine occasion (un seul à la fois).
    var pendingCelebration: GradeCelebration?

    private let defaults: UserDefaults
    private static let keyPrefix = "com.spinlog.gradeStore."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Compte actif

    /// Bascule sur les grades du compte indiqué (ou les vide, déconnecté) : appelé par
    /// `DiscogsAuthManager` au lancement, à la connexion et à la déconnexion.
    func setActiveUsername(_ username: String?) {
        let normalized = Self.normalize(username)
        guard normalized != activeUsername else { return }
        activeUsername = normalized
        pendingCelebration = nil
        guard let normalized, normalized != Self.normalize(DemoMode.username) else {
            unlocks = []
            counts = [:]
            welcomeDecided = false
            return
        }
        load(for: normalized)
    }

    func clearAccountData(for username: String) {
        guard let normalized = Self.normalize(username) else { return }
        defaults.removeObject(forKey: Self.key(for: normalized))
        if activeUsername == normalized {
            unlocks = []
            counts = [:]
            welcomeDecided = false
            pendingCelebration = nil
        }
    }

    // MARK: - Lecture

    /// Nombre de grades acquis dans ce parcours (0 = aucun) : le grade courant est l'indice - 1.
    func acquiredTiers(for track: GradeTrack) -> Int {
        (unlocks.filter { $0.track == track }.map(\.tier).max() ?? -1) + 1
    }

    func unlockDate(track: GradeTrack, tier: Int) -> Date? {
        unlocks.first { $0.track == track && $0.tier == tier }?.date
    }

    /// Dernier nombre fiable connu, ou `nil` tant qu'aucun comptage fiable n'a eu lieu (collection
    /// pas encore synchronisée) : mieux vaut ne rien montrer qu'un « 0 » trompeur.
    func knownCount(for track: GradeTrack) -> Int? {
        counts[track]
    }

    // MARK: - Évaluation

    /// Enregistre les nouveaux paliers franchis par ce nombre. `isReliable` : le nombre vient d'une
    /// donnée complète et fraîche (une collection chargée à moitié ou périmée ne doit jamais
    /// décider d'un grade). Les premiers grades d'un compte sont inscrits en silence, ainsi que les
    /// sauts trop grands (voir `GradeRules.shouldCelebrate`).
    /// `eventDates` : dates réelles des événements comptés (ajout de chaque disque distinct, chaque
    /// écoute). Un grade attribué en silence (premier comptage, gros saut) prend alors la vraie date où
    /// son palier a été franchi plutôt que celle d'aujourd'hui ; un grade franchi à l'instant garde la
    /// date du jour.
    func evaluate(track: GradeTrack, count: Int, isReliable: Bool, eventDates: [Date]? = nil) {
        guard isReliable, let activeUsername, activeUsername != Self.normalize(DemoMode.username) else { return }
        let previous = counts[track]
        counts[track] = count

        let now = Date()
        let celebrates = GradeRules.shouldCelebrate(previousCount: previous, newCount: count, track: track)
        let historical = celebrates
            ? [:]
            : GradeRules.historicalDates(eventDates: eventDates ?? [], track: track, now: now)
        let added = GradeRules.newUnlocks(count: count, track: track, existing: unlocks, date: now, historicalDates: historical)
        if !added.isEmpty {
            unlocks = GradeRules.normalized(unlocks + added)
            if celebrates, let top = added.map(\.tier).max() {
                pendingCelebration = GradeCelebration(track: track, tier: top, tiersGained: added.count)
            }
            gradeLogger.log("\(added.count) grade(s) franchi(s), parcours \(track.rawValue, privacy: .public)")
            CloudSyncEngine.shared.markGradesDirty()
        }
        persist()
        decideWelcomeIfNeeded()
    }

    /// Accueil : quand les deux parcours ont été comptés une première fois, le compte qui arrive avec
    /// des grades déjà mérités en voit une seule carte, pour le plus haut (collection si égalité). Un
    /// compte qui part de zéro n'en a pas (il fêtera ses premiers grades un à un). Décidé une seule
    /// fois par compte, et pas tant qu'un premier rapatriement iCloud peut encore apporter les grades
    /// (et l'accueil) déjà faits sur un autre appareil.
    func decideWelcomeIfNeeded() {
        guard !welcomeDecided, pendingCelebration == nil,
              activeUsername != nil,
              counts[.collection] != nil, counts[.listening] != nil,
              !CloudSyncEngine.shared.isAwaitingFirstHydration else { return }
        welcomeDecided = true
        if let top = GradeRules.welcomeTarget(unlocks: unlocks) {
            pendingCelebration = GradeCelebration(track: top.track, tier: top.tier, tiersGained: 1, kind: .welcome)
        }
        persist()
        CloudSyncEngine.shared.markGradesDirty()
    }

    func dismissCelebration() {
        pendingCelebration = nil
    }

    // MARK: - Synchronisation iCloud

    var syncPayload: SyncedGrades { SyncedGrades(unlocks: unlocks, welcomeDecided: welcomeDecided) }

    /// Fusionne les grades reçus d'iCloud avec ceux de l'appareil (jamais de remplacement : un
    /// grade connu d'un seul côté est conservé, la date la plus ancienne l'emporte ; l'accueil
    /// déjà fait quelque part est fait partout). Si l'appareil en sait plus que iCloud, on le renvoie :
    /// appelé pendant la réapplication d'un lot distant, ce renvoi est différé à la fin du lot par
    /// `CloudSyncEngine.markGradesDirty`.
    func applyRemote(_ remote: SyncedGrades) {
        guard activeUsername != nil else { return }
        let result = GradeRules.mergeRemote(
            local: unlocks,
            localWelcomeDecided: welcomeDecided,
            remote: remote.unlocks,
            remoteWelcomeDecided: remote.welcomeDecided
        )
        if result.changesLocal {
            unlocks = result.unlocks
            welcomeDecided = result.welcomeDecided
            persist()
        }
        if result.needsResend {
            CloudSyncEngine.shared.markGradesDirty()
        }
        if result.changesLocal {
            decideWelcomeIfNeeded()
        }
    }

    // MARK: - Persistance

    private struct StoredState: Codable {
        var unlocks: [GradeUnlock]
        var counts: [String: Int]
        var welcomeDecided: Bool?
    }

    private func load(for username: String) {
        guard let data = defaults.data(forKey: Self.key(for: username)),
              let state = try? JSONDecoder().decode(StoredState.self, from: data) else {
            unlocks = []
            counts = [:]
            welcomeDecided = false
            return
        }
        welcomeDecided = state.welcomeDecided ?? false
        unlocks = GradeRules.normalized(state.unlocks)
        counts = Dictionary(uniqueKeysWithValues: state.counts.compactMap { key, value in
            GradeTrack(rawValue: key).map { ($0, value) }
        })
    }

    private func persist() {
        guard let activeUsername else { return }
        let state = StoredState(
            unlocks: unlocks,
            counts: Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }),
            welcomeDecided: welcomeDecided
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.key(for: activeUsername))
        }
    }

    private static func key(for username: String) -> String { keyPrefix + username }

    private static func normalize(_ username: String?) -> String? {
        guard let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
