import Foundation
import OSLog

private nonisolated let freshInstallLogger = Logger(subsystem: AppInfo.logSubsystem, category: "FreshInstall")

/// Le Keychain survit à la désinstallation de l'app, contrairement aux `UserDefaults` : après une
/// réinstallation, l'app retrouvait les jetons Discogs du compte précédent et se croyait connectée
/// (sans tags, réglages ni cache, effacés avec elle). Au premier lancement d'une installation
/// neuve, les identifiants Discogs sont donc effacés.
nonisolated enum FreshInstallKeychainReset {
    static let markerKey = "com.spinlog.installMarker"
    /// Préfixes des réglages écrits par l'app : leur présence sans marqueur signale une mise à
    /// jour depuis une version antérieure au marqueur (à ne surtout pas déconnecter).
    static let appKeyPrefixes = ["com.spinlog.", "appColorTheme", "batchScanDraft_", "discogsCategoryBackfill"]

    /// Installation neuve : ni marqueur, ni réglage d'une version précédente (standard ou App Group).
    static func isFreshInstall(standardKeys: some Sequence<String>, hasAppGroupData: Bool) -> Bool {
        let keys = Array(standardKeys)
        guard !keys.contains(markerKey) else { return false }
        let hasPriorData = keys.contains { key in appKeyPrefixes.contains { key.hasPrefix($0) } }
        return !hasPriorData && !hasAppGroupData
    }

    /// À appeler tout au début du lancement (`MyApp.init`), avant que les stores n'écrivent
    /// leurs propres réglages.
    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        groupDefaults: UserDefaults? = UserDefaults(suiteName: AppGroup.id),
        keychain: KeychainStore = KeychainStore()
    ) {
        let fresh = isFreshInstall(
            standardKeys: defaults.dictionaryRepresentation().keys,
            hasAppGroupData: groupDefaults?.object(forKey: PremiumConstants.isPremiumDefaultsKey) != nil
        )
        if fresh {
            for key in [KeychainKeys.accessToken, KeychainKeys.accessTokenSecret, KeychainKeys.username, KeychainKeys.avatarURL] {
                keychain.remove(key)
            }
            freshInstallLogger.log("Installation neuve : identifiants Discogs d'une installation précédente effacés")
        }
        defaults.set(true, forKey: markerKey)
    }
}
