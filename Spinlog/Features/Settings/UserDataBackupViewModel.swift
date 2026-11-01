import SwiftUI

/// État et actions de la sauvegarde JSON des données locales (section cachée de « Export », voir
/// `UserDataBackupSection`) : export vers un fichier, vérification puis restauration d'un fichier.
@Observable
@MainActor
final class UserDataBackupViewModel {
    var showingFileExporter = false
    var showingFileImporter = false
    var showingRestoreConfirmation = false
    /// Message de résultat ou d'erreur, affiché par une alerte (voir `messageAlert`).
    var message: String?
    private(set) var exportDocument: SpinlogBackupDocument?
    private(set) var exportFilename = ""
    private(set) var pendingBackupToRestore: SpinlogUserDataBackup?

    private let authManager = DiscogsAuthManager.shared
    private let tagStore = TagStore.shared
    private let appearance = AppearancePreferencesStore.shared
    private let themeManager = ThemeManager.shared
    private let premiumStore = PremiumStore.shared

    /// La démo n'a pas de vraies données à sauvegarder, et restaurer y écrirait des réglages d'un
    /// autre compte : les deux actions sont fermées.
    var isAvailable: Bool { authManager.isAuthenticated && !authManager.isDemoMode }

    var exportSubtitle: String {
        guard isAvailable else { return "Connexion à Discogs requise" }
        if let user = authManager.username { return "Exporte tes tags pour le compte \(user)" }
        return "Exporte tes tags associés à ton compte"
    }

    var restoreConfirmationMessage: String {
        guard let backup = pendingBackupToRestore else { return "Tes données locales seront remplacées." }
        return UserDataBackupService.confirmationMessage(for: backup)
    }

    func prepareExport() {
        guard isAvailable, let username = authManager.username else {
            message = "Tu dois être connecté à ton compte Discogs pour générer une sauvegarde de tes données."
            return
        }
        exportDocument = SpinlogBackupDocument(
            backup: UserDataBackupService.make(username: username, tagStore: tagStore, appearance: appearance, themeManager: themeManager)
        )
        exportFilename = UserDataBackupService.filename(username: username)
        showingFileExporter = true
    }

    func finishExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            message = "Fichier de sauvegarde exporté avec succès :\n\(url.lastPathComponent)"
        case .failure(let error):
            message = "Échec de l'export : \(error.localizedDescription)"
        }
    }

    func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importFile(at: url)
        case .failure(let error):
            message = "Échec de l'ouverture : \(error.localizedDescription)"
        }
    }

    private func importFile(at url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            message = "Impossible d'accéder au fichier sélectionné."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let invalidFile = "Le fichier sélectionné n'est pas une sauvegarde \(AppInfo.name) valide ou est endommagé."
        guard let data = try? Data(contentsOf: url) else {
            message = invalidFile
            return
        }
        switch UserDataBackupService.check(data: data, currentUsername: authManager.username, isAuthenticated: isAvailable) {
        case .accepted(let backup):
            pendingBackupToRestore = backup
            showingRestoreConfirmation = true
        case .notSignedIn:
            message = "Connecte-toi à ton compte Discogs avant de restaurer une sauvegarde."
        case .wrongAccount(let backupUser, let currentUser):
            message = "Ce fichier de sauvegarde appartient au compte « \(backupUser) », alors que tu es connecté avec le compte « \(currentUser) ».\n\nLa restauration a été refusée pour éviter toute incohérence."
        case .invalidFile:
            message = invalidFile
        }
    }

    func applyPendingBackup() {
        guard let backup = pendingBackupToRestore else { return }
        UserDataBackupService.restore(
            backup, tagStore: tagStore, appearance: appearance, themeManager: themeManager, isPremium: premiumStore.isPremium
        )
        message = UserDataBackupService.successMessage(for: backup)
        pendingBackupToRestore = nil
    }

    func cancelRestore() {
        pendingBackupToRestore = nil
    }
}
