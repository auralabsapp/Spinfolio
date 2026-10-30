import ActivityKit
import AppIntents
import Foundation

/// « Démarre une écoute » : enregistre l'écoute sur platine d'un disque de la collection et lance
/// la Live Activity, sans ouvrir l'app (`LiveActivityIntent` autorise la Live Activity depuis
/// l'arrière-plan). Même circuit que le bouton d'écoute des écrans (`startListening`).
struct StartListeningIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Démarrer une écoute"
    static let description = IntentDescription("Enregistre l'écoute sur platine d'un album de ta collection et l'affiche sur l'écran verrouillé.")

    @Parameter(title: "Album", requestValueDialog: "Quel album écoutes-tu ?")
    var record: RecordEntity

    init() {}

    init(record: RecordEntity) {
        self.record = record
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Démarrer l'écoute de \(\.$record)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard DiscogsAuthManager.shared.username != nil else { throw RecordIntentError.notSignedIn }
        guard RecordLibrary.isOwned(releaseId: record.id, in: try await RecordLibrary.records()) else {
            throw RecordIntentError.notInCollection
        }
        NowPlayingActivityManager.shared.startListening(
            releaseId: record.id,
            albumTitle: record.title,
            artistName: record.artist,
            coverURL: record.coverURL
        )
        return .result(dialog: "Écoute de \(record.title) lancée.")
    }
}

/// « Arrête l'écoute » : termine l'écoute sur platine en cours et sa Live Activity.
struct StopListeningIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Arrêter l'écoute"
    static let description = IntentDescription("Termine l'écoute sur platine en cours.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = NowPlayingActivityManager.shared
        // L'état en mémoire est vide si l'app a été relancée par Siri : on regarde aussi les
        // Live Activities encore affichées par le système.
        let wasListening = manager.isAnyPlaying || !Activity<NowPlayingActivityAttributes>.activities.isEmpty
        guard wasListening else {
            return .result(dialog: "Aucune écoute en cours.")
        }
        await manager.endCurrentActivity()
        return .result(dialog: "Écoute arrêtée.")
    }
}

/// « Un disque au hasard » : tire un disque de la collection et ouvre sa fiche.
struct RandomRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "Album au hasard"
    static let description = IntentDescription("Tire un album au hasard dans ta collection et ouvre sa fiche.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let records = try await RecordLibrary.records()
        guard let record = records.randomElement() else { throw RecordIntentError.emptyLibrary }
        TabNavigationCoordinator.shared.openRelease(id: record.id, coverURL: record.coverURL)
        return .result(dialog: "\(record.title), de \(record.artist).")
    }
}

/// Raccourcis proposés automatiquement dans Siri, Spotlight et l'app Raccourcis, sans
/// configuration. Les phrases sont traduites dans `AppShortcuts.xcstrings`.
struct SpinfolioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RandomRecordIntent(),
            phrases: [
                "Un album au hasard avec \(.applicationName)",
                "Tire un album au hasard dans \(.applicationName)",
                "Qu'est-ce que j'écoute avec \(.applicationName)"
            ],
            shortTitle: "Album au hasard",
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: StartListeningIntent(),
            phrases: [
                "Démarre une écoute dans \(.applicationName)",
                "Je mets un album sur la platine avec \(.applicationName)"
            ],
            shortTitle: "Démarrer une écoute",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopListeningIntent(),
            phrases: [
                "Arrête l'écoute dans \(.applicationName)",
                "Arrête l'écoute avec \(.applicationName)"
            ],
            shortTitle: "Arrêter l'écoute",
            systemImageName: "stop.circle"
        )
    }
}
