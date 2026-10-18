import SwiftUI
import Observation

/// Gestionnaire réactif du thème de couleur actif dans toute l'application.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private let storageKey = "appColorTheme"
    private let defaults = UserDefaults.standard

    var currentTheme: AppColorTheme {
        didSet {
            defaults.set(currentTheme.rawValue, forKey: storageKey)
            publishAccentForExtensions()
            if !isApplyingRemoteTheme {
                CloudSyncEngine.shared.markAppPreferencesDirty()
            }
        }
    }

    /// Empêche `applyRemoteTheme` de redéclencher un envoi vers CloudKit : cette donnée en vient
    /// déjà (même principe que `ShelfPreferencesStore.isApplyingRemoteShelfPreferences`).
    private var isApplyingRemoteTheme = false

    private init() {
        var initialTheme: AppColorTheme = .signature
        if let raw = defaults.string(forKey: storageKey),
           let theme = AppColorTheme(rawValue: raw) {
            initialTheme = theme
        }
        self.currentTheme = initialTheme
        // `didSet` n'est pas appelé depuis l'init : publication explicite, pour qu'un thème
        // choisi avant cette version atteigne aussi la Live Activity.
        publishAccentForExtensions()

        // Écoute automatique de la perte ou modification du statut premium
        addLibraryObserver(for: .premiumStatusChanged) { [weak self] in
            guard let self else { return }
            let isPremium = UserDefaults(suiteName: AppGroup.id)?.bool(forKey: PremiumConstants.isPremiumDefaultsKey)
                ?? UserDefaults.standard.bool(forKey: PremiumConstants.isPremiumDefaultsKey)
            self.revertToDefaultIfNeeded(isPremium: isPremium)
        }
    }

    /// Change de thème de couleur de manière sécurisée en vérifiant le statut premium si nécessaire.
    @discardableResult
    func selectTheme(_ theme: AppColorTheme, isPremium: Bool) -> Bool {
        if theme.isPremiumOnly && !isPremium {
            return false
        }
        currentTheme = theme
        return true
    }

    /// Si l'utilisateur n'est plus premium et utilise un thème réservé aux membres premium,
    /// on le réinitialise automatiquement sur le thème de base (.signature).
    func revertToDefaultIfNeeded(isPremium: Bool) {
        if currentTheme.isPremiumOnly && !isPremium {
            currentTheme = .signature
        }
    }

    /// Transmet la couleur du thème (variante sombre) à l'extension pour la Live Activity.
    private func publishAccentForExtensions() {
        let darkColor = currentTheme.primaryUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard darkColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        WidgetSnapshotStore.saveThemeAccentOnDark(red: Double(red), green: Double(green), blue: Double(blue))
    }

    /// Applique un thème reçu d'iCloud. N'écrit qu'en local.
    func applyRemoteTheme(_ theme: AppColorTheme) {
        isApplyingRemoteTheme = true
        currentTheme = theme
        isApplyingRemoteTheme = false
    }
}
