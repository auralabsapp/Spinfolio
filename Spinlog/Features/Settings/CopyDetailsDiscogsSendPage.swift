import SwiftUI

/// Page « Envoyer tout vers Discogs » : renvoie dans les champs associés les prix et états déjà
/// gardés dans l'app. L'analyse montre ce qui serait écrit avant toute écriture ; l'envoi se fait en
/// fond de page, au rythme autorisé par Discogs, et peut être interrompu.
struct CopyDetailsDiscogsSendPage: View {
    @State private var model = CopyDetailsDiscogsSyncViewModel()
    @State private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        SettingsSubPage(title: "Envoyer vers Discogs") {
            if model.isDemo {
                Section {
                    Text(AppMessages.demoModificationBlocked)
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
            } else {
                if !networkMonitor.isConnected {
                    Section { OfflineBannerView(customMessage: String(localized: "L'envoi relit puis écrit ta collection sur Discogs.")) }
                }
                analyzeSection
                if let plan = model.plan {
                    previewSection(plan)
                }
                progressSection
            }
        }
        .messageAlert(message: $model.message)
        // Quitter la page n'interrompt pas un envoi commencé volontairement, mais une analyse
        // inutile est abandonnée.
        .onDisappear { if model.phase == .loading { model.cancel() } }
    }

    private var analyzeSection: some View {
        Section {
            Button {
                model.analyze()
            } label: {
                HStack {
                    Text("Analyser")
                    Spacer()
                    if model.phase == .loading { ProgressView() }
                }
            }
            .tint(Color.spinlogPink)
            .disabled(model.isBusy)
        } footer: {
            Text("Compare les prix et états de l'app aux champs Discogs associés. Rien n'est écrit avant ta confirmation, et une valeur absente de l'app n'efface jamais rien sur Discogs.")
        }
    }

    @ViewBuilder
    private func previewSection(_ plan: CopyDetailsDiscogsSync.Plan) -> some View {
        Section {
            row("À envoyer", plan.operations.count)
            row("Déjà identiques", plan.upToDate)
            row("Ignorées (valeur Discogs illisible)", plan.skippedUnreadable)
            Button {
                model.send()
            } label: {
                Text("Envoyer \(plan.operations.count) valeurs")
            }
            .tint(Color.spinlogPink)
            .disabled(plan.operations.isEmpty || model.isBusy)
        } header: {
            SectionEyebrow(title: "Aperçu", icon: "arrow.up.circle")
        } footer: {
            Text("Les valeurs illisibles sur Discogs sont laissées telles quelles, pour ne pas écraser une information que l'app ne comprend pas.")
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if case .sending(let done, let total) = model.phase {
            Section {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(Color.spinlogPink)
                Text("\(done) sur \(total)")
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondaryText)
                Button("Interrompre", role: .destructive) { model.cancel() }
            } header: {
                SectionEyebrow(title: "Envoi en cours", icon: "arrow.up.circle.fill")
            } footer: {
                Text("Discogs limite le rythme des écritures : l'envoi de nombreuses valeurs peut prendre plusieurs minutes. Garde l'app ouverte.")
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(count, format: .number).foregroundStyle(Color.appSecondaryText)
        }
    }
}
