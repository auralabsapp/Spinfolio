import SwiftUI

/// Page « Export » de Réglages : CSV et déclaration PDF de la collection (Premium). L'appel réseau
/// est délégué à `CollectionExportViewModel`, dont les alertes s'affichent ici.
struct ExportSettingsPage: View {
    @State private var authManager = DiscogsAuthManager.shared
    @State private var premiumStore = PremiumStore.shared
    @State private var exportViewModel = CollectionExportViewModel()

    var body: some View {
        SettingsSubPage(title: "Export") {
            exportSection
        }
        .alert(exportViewModel.alertTitle, isPresented: $exportViewModel.showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportViewModel.alertMessage)
        }
    }

    @ViewBuilder
    private var exportSection: some View {
        Section {
            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "tablecells.fill",
                    title: "Export CSV de la collection",
                    message: "Passe premium pour exporter toute ta discothèque avec métadonnées, notes et tags."
                )
            } else {
                Button {
                    Task { await exportViewModel.exportCSV() }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "tablecells", backgroundColor: .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exporter la collection en CSV")
                                .font(.body)
                                .foregroundStyle(authManager.isAuthenticated ? .primary : .secondary)
                            Text(csvExportSubtitle)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        if exportViewModel.isExportingCSV {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.appTertiaryText)
                        }
                    }
                }
                .disabled(!authManager.isAuthenticated || exportViewModel.isExportingCSV)

                Button {
                    Task { await exportViewModel.exportPDF() }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "doc.richtext", backgroundColor: .indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Déclaration de collection (PDF)")
                                .font(.body)
                                .foregroundStyle(authManager.isAuthenticated ? .primary : .secondary)
                            Text(pdfExportSubtitle)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                        if exportViewModel.isExportingPDF {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.appTertiaryText)
                        }
                    }
                }
                .disabled(!authManager.isAuthenticated || exportViewModel.isExportingPDF)
            }
        } header: {
            // Badge de démo sur le titre : toute la section (CSV et PDF) est Premium.
            SectionEyebrow(title: "Export", icon: "square.and.arrow.up.fill", isPremiumFeature: true)
        } footer: {
            Text("L'export CSV regroupe tous tes albums (tous dossiers confondus) avec leurs métadonnées, tags et notes pour tes tableurs (Excel, Numbers). La déclaration PDF liste la collection avec état et prix d'achat, à présenter par exemple à un assureur.")
        }
        // L'icône d'export laisse la place à l'indicateur d'avancement en fondu, et inversement.
        .animatesSettingsChanges(value: exportViewModel.isExportingCSV)
        .animatesSettingsChanges(value: exportViewModel.isExportingPDF)
    }

    private var pdfExportSubtitle: String {
        if exportViewModel.isExportingPDF {
            return String(localized: "Génération du document en cours…")
        }
        if authManager.isAuthenticated {
            return String(localized: "Pochettes, état et prix d'achat, tous dossiers confondus")
        } else {
            return String(localized: "Connexion à Discogs requise")
        }
    }

    private var csvExportSubtitle: String {
        if exportViewModel.isExportingCSV {
            return String(localized: "Génération du fichier en cours…")
        }
        if authManager.isAuthenticated {
            return String(localized: "Tous dossiers confondus avec tags et notes")
        } else {
            return String(localized: "Connexion à Discogs requise")
        }
    }
}
