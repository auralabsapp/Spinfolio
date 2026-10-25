import SwiftUI
import WidgetKit
import Observation

/// Gestionnaire réactif du thème de couleur actif dans toute l'application.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private let storageKey = "appColorTheme"
    private let defaults = UserDefaults.standard

    var currentTheme: AppColorTheme {
        didSet {
            // Thème Premium masqué ou rétabli (perte puis reprise de l'abonnement) : le choix
            // enregistré et iCloud ne changent pas, seul l'affichage suit.
            if !isMaskingPremiumTheme {
                defaults.set(currentTheme.rawValue, forKey: storageKey)
            }
            publishAccentForExtensions()
            // Le widget n'est redessiné qu'à la demande : sans cela, il gardait l'ancienne couleur
            // jusqu'au tirage du lendemain.
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.randomAlbum)
            if !isApplyingRemoteTheme && !isMaskingPremiumTheme {
                CloudSyncEngine.shared.markAppPreferencesDirty()
            }
        }
    }

    /// Thème choisi par l'utilisateur, tel qu'enregistré et synchronisé. Diffère de `currentTheme`
    /// quand un thème Premium est seulement masqué par la perte de l'abonnement : c'est lui qu'on
    /// envoie sur iCloud, pour ne pas imposer le thème par défaut aux autres appareils.
    var chosenTheme: AppColorTheme {
        defaults.string(forKey: storageKey).flatMap(AppColorTheme.init(rawValue:)) ?? currentTheme
    }

    /// Empêche `applyRemoteTheme` de redéclencher un envoi vers CloudKit : cette donnée en vient
    /// déjà (même principe que `ShelfPreferencesStore.isApplyingRemoteShelfPreferences`).
    private var isApplyingRemoteTheme = false
    /// Voir `revertToDefaultIfNeeded` : auparavant, le retour au thème par défaut était enregistré
    /// puis envoyé sur iCloud avant l'arrêt de la synchro, et le thème choisi était perdu partout.
    private var isMaskingPremiumTheme = false

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
            // Accès effectif (abonnement, aperçu démo, forçage développeur) plutôt que la seule
            // clé d'abonnement de l'App Group, qui ignorait l'aperçu de la démo.
            self.revertToDefaultIfNeeded(isPremium: PremiumStore.shared.isPremium)
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
    /// Le thème choisi reste enregistré : il revient de lui-même si le Premium est retrouvé.
    func revertToDefaultIfNeeded(isPremium: Bool) {
        let target = Self.displayedTheme(chosen: chosenTheme, isPremium: isPremium)
        guard target != currentTheme else { return }
        isMaskingPremiumTheme = true
        currentTheme = target
        isMaskingPremiumTheme = false
    }

    /// Thème à afficher : le thème choisi, sauf un thème Premium sans abonnement (thème par défaut).
    static func displayedTheme(chosen: AppColorTheme, isPremium: Bool) -> AppColorTheme {
        if isPremium { return chosen }
        return chosen.isPremiumOnly ? .signature : chosen
    }

    /// Transmet la couleur du thème à l'extension (Live Activity et widget) : teinte principale
    /// du mode sombre pour les fonds sombres, teinte foncée du mode clair pour les fonds clairs
    /// (pochette claire du widget), assez contrastée pour du texte.
    private func publishAccentForExtensions() {
        func components(_ color: UIColor, style: UIUserInterfaceStyle) -> [Double]? {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
            return [Double(red), Double(green), Double(blue)]
        }
        guard let onDark = components(currentTheme.primaryUIColor, style: .dark),
              let onLight = components(currentTheme.deepUIColor, style: .light) else { return }
        WidgetSnapshotStore.saveThemeAccents(onDark: onDark, onLight: onLight)
    }

    /// Applique un thème reçu d'iCloud. N'écrit qu'en local.
    func applyRemoteTheme(_ theme: AppColorTheme) {
        isApplyingRemoteTheme = true
        currentTheme = theme
        isApplyingRemoteTheme = false
    }
}
