import Foundation
import Security
import OSLog

private nonisolated let keychainLogger = Logger(subsystem: "com.auralabs.Spinlog", category: "KeychainStore")

/// Wrapper minimal autour du Keychain pour stocker les tokens OAuth Discogs.
nonisolated struct KeychainStore {
    private let service = "com.spinlog.discogs"

    /// Lisible après le premier déverrouillage suivant un redémarrage, même appareil verrouillé :
    /// la tâche `BGAppRefresh` et les notifications silencieuses CloudKit s'exécutent souvent
    /// écran verrouillé, et l'accessibilité par défaut (`WhenUnlocked`) y rendait les tokens
    /// illisibles. Sans `ThisDeviceOnly`, pour conserver la restauration depuis une sauvegarde.
    private static var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlock }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    /// Écrit (ou remplace) la valeur. Met à jour l'élément existant plutôt que de le supprimer puis
    /// le recréer : avec l'ancien enchaînement, un échec de l'ajout après la suppression perdait
    /// la valeur précédente.
    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        let query = baseQuery(forKey: key)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: Self.accessibility
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            keychainLogger.error("Échec d'écriture Keychain pour \(key, privacy: .public) : OSStatus \(status, privacy: .public)")
            return false
        }
        return true
    }

    func get(_ key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                keychainLogger.error("Échec de lecture Keychain pour \(key, privacy: .public) : OSStatus \(status, privacy: .public)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func remove(_ key: String) {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            keychainLogger.error("Échec de suppression Keychain pour \(key, privacy: .public) : OSStatus \(status, privacy: .public)")
        }
    }

    /// Migre les éléments écrits par une version antérieure (accessibilité par défaut,
    /// `WhenUnlocked`) vers `accessibility`. Idempotent et peu coûteux : à appeler au lancement.
    /// Échoue sans conséquence si l'appareil est verrouillé (lancement en arrière-plan), et sera
    /// simplement retenté au lancement suivant.
    func migrateAccessibilityIfNeeded() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let attributes: [String: Any] = [kSecAttrAccessible as String: Self.accessibility]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            keychainLogger.error("Échec de migration de l'accessibilité Keychain : OSStatus \(status, privacy: .public)")
        }
    }
}
