import Foundation

/// Gère la persistance et la synchronisation iCloud de l'apparence (clair/sombre/système) et de la
/// durée maximale d'affichage de la Live Activity d'écoute — avec le thème de couleur
/// (`ThemeManager`), ce sont les seuls réglages globaux à suivre désormais le compte Discogs d'un
/// appareil à l'autre, au même titre que les préférences de collection/rangement. Remplace les
/// `@AppStorage` bruts auparavant dupliqués entre `SettingsView` et `RootTabView`, qui n'offraient
/// aucun point d'accroche pour signaler un changement à `CloudSyncEngine`.
@MainActor
@Observable
final class AppearancePreferencesStore {
    static let shared = AppearancePreferencesStore()

    private let appearanceKey = "appTheme"
    private let maxListeningDurationKey = NowPlayingActivityManager.maxListeningDurationKey

    var appearance: AppTheme {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: appearanceKey)
            if !isApplyingRemotePreferences {
                CloudSyncEngine.shared.markAppPreferencesDirty()
            }
        }
    }

    var maxListeningDuration: TimeInterval {
        didSet {
            UserDefaults.standard.set(maxListeningDuration, forKey: maxListeningDurationKey)
            if !isApplyingRemotePreferences {
                CloudSyncEngine.shared.markAppPreferencesDirty()
            }
        }
    }

    /// Empêche `applyRemotePreferences` de redéclencher un envoi vers CloudKit : cette donnée en
    /// vient déjà (même principe que `ShelfPreferencesStore.isApplyingRemoteShelfPreferences`).
    private var isApplyingRemotePreferences = false

    private init() {
        if let raw = UserDefaults.standard.string(forKey: appearanceKey), let theme = AppTheme(rawValue: raw) {
            appearance = theme
        } else {
            appearance = .system
        }
        let storedDuration = UserDefaults.standard.double(forKey: maxListeningDurationKey)
        maxListeningDuration = storedDuration > 0 ? storedDuration : NowPlayingActivityManager.defaultDuration
    }

    /// Applique un état reçu d'iCloud. N'écrit qu'en local.
    func applyRemotePreferences(appearance: AppTheme, maxListeningDuration: TimeInterval) {
        isApplyingRemotePreferences = true
        self.appearance = appearance
        self.maxListeningDuration = maxListeningDuration
        isApplyingRemotePreferences = false
    }
}
