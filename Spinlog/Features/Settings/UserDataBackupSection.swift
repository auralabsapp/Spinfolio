import SwiftUI
import UniformTypeIdentifiers

/// Section cachée de la page « Export » : sauvegarde et restauration JSON des données locales
/// (tags, écoutes, préférences, années des masters). N'apparaît qu'après les 7 touchers sur la
/// version de « À propos », comme les diagnostics (hors App Store : voir
/// `SubscriptionManager.showsDiagnostic`). Textes volontairement non traduits (`verbatim`),
/// réservés aux tests.
struct UserDataBackupSection: View {
    let viewModel: UserDataBackupViewModel
    @State private var subscriptionManager = SubscriptionManager.shared

    var body: some View {
        if subscriptionManager.showsDiagnostic {
            Section {
                row(
                    title: "Exporter une sauvegarde JSON",
                    subtitle: viewModel.exportSubtitle,
                    systemImage: "square.and.arrow.up",
                    color: .blue,
                    isEnabled: viewModel.isAvailable,
                    action: viewModel.prepareExport
                )
                row(
                    title: "Restaurer une sauvegarde JSON",
                    subtitle: "Restaure tags, réglages et métadonnées locales",
                    systemImage: "square.and.arrow.down",
                    color: .teal,
                    isEnabled: viewModel.isAvailable
                ) { viewModel.showingFileImporter = true }
            } header: {
                Text(verbatim: "Sauvegarde interne (JSON)")
            } footer: {
                Text(verbatim: "Exporte et importe l'ensemble des métadonnées locales : tags, sessions d'écoute, préférences et correspondance des années. Section masquée : 7 touchers sur la version, dans « À propos ».")
            }
        }
    }

    private func row(
        title: String, subtitle: String, systemImage: String, color: Color, isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SettingsIcon(systemName: systemImage, backgroundColor: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.body)
                        .foregroundStyle(isEnabled ? .primary : .secondary)
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                }
                Spacer()
            }
        }
        .disabled(!isEnabled)
    }
}

/// Feuilles et alertes de la sauvegarde JSON : posées à part de la liste (en arrière-plan de la
/// page), pour ne pas entrer en conflit avec les alertes de l'export CSV/PDF.
private struct UserDataBackupPresentation: ViewModifier {
    @Bindable var viewModel: UserDataBackupViewModel

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: $viewModel.showingFileExporter,
                document: viewModel.exportDocument,
                contentType: .json,
                defaultFilename: viewModel.exportFilename
            ) { viewModel.finishExport($0) }
            .fileImporter(isPresented: $viewModel.showingFileImporter, allowedContentTypes: [.json]) {
                viewModel.handleImport($0)
            }
            .confirmationDialog(
                Text(verbatim: "Restaurer la sauvegarde ?"),
                isPresented: $viewModel.showingRestoreConfirmation,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    viewModel.applyPendingBackup()
                } label: { Text(verbatim: "Remplacer les données locales") }
                Button("Annuler", role: .cancel) {
                    viewModel.cancelRestore()
                }
            } message: {
                Text(verbatim: viewModel.restoreConfirmationMessage)
            }
            .messageAlert(message: $viewModel.message)
    }
}

extension View {
    /// Présentations de la sauvegarde JSON (voir `UserDataBackupPresentation`).
    func userDataBackupPresentation(_ viewModel: UserDataBackupViewModel) -> some View {
        modifier(UserDataBackupPresentation(viewModel: viewModel))
    }
}
