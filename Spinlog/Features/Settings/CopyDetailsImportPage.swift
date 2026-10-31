import SwiftUI

/// Page « Importer depuis Discogs » : reprend dans l'app les prix d'achat et états du disque déjà
/// saisis dans des champs personnalisés Discogs. L'analyse ne modifie rien ; l'utilisateur voit ce
/// qui serait importé, ce qui est illisible, puis confirme. Les valeurs de l'app ne sont remplacées
/// que sur demande, et le dernier import peut être annulé.
struct CopyDetailsImportPage: View {
    @State private var model = CopyDetailsImportViewModel()
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var showingReplaceConfirmation = false

    var body: some View {
        SettingsSubPage(title: "Importer depuis Discogs") {
            if model.isDemo {
                Section {
                    Text(AppMessages.demoModificationBlocked)
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
            } else {
                if !networkMonitor.isConnected {
                    Section { OfflineBannerView(customMessage: String(localized: "L'import relit ta collection sur Discogs.")) }
                }
                fieldsSection
                if model.phase == .loading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Lecture de ta collection…")
                        }
                    }
                }
                if let plan = model.plan {
                    previewSections(plan)
                }
                undoSection
            }
        }
        .messageAlert(message: $model.message)
        .task { await model.loadFields() }
        .onDisappear { model.cancelAnalysis() }
        .confirmationDialog(
            "Remplacer les valeurs de l'app ?",
            isPresented: $showingReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Importer et remplacer", role: .destructive) { model.applyImport() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les prix et états déjà saisis dans l'app seront remplacés par ceux de Discogs. Tu pourras annuler cet import.")
        }
    }

    // MARK: - Choix des champs

    private var fieldsSection: some View {
        Section {
            fieldPicker(title: "Champ du prix d'achat", icon: "tag.fill", color: .green, selection: $model.priceFieldId)
            fieldPicker(title: "Champ de l'état du disque", icon: "opticaldisc.fill", color: .purple, selection: $model.conditionFieldId)
            Picker(selection: $model.unspecifiedCurrency) {
                ForEach(PurchasePriceParser.supportedCurrencies, id: \.self) { Text($0).tag($0) }
            } label: {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "eurosign.circle.fill", backgroundColor: .blue)
                    Text("Compter en…")
                }
            }
            .pickerStyle(.menu)
            .tint(Color.spinlogPink)
            .onChange(of: model.unspecifiedCurrency) { model.recomputePlan() }

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
            .disabled(!model.hasFieldChosen || model.phase == .loading || model.phase == .applying)
        } header: {
            SectionEyebrow(title: "Champs à importer", icon: "square.and.arrow.down")
        } footer: {
            Text("Rien n'est modifié avant ta confirmation. « Compter en… » s'applique aux prix écrits sans devise ; un prix en dollars ou en livres garde sa devise.")
        }
    }

    private func fieldPicker(title: LocalizedStringKey, icon: String, color: Color, selection: Binding<Int?>) -> some View {
        Picker(selection: Binding(
            get: { selection.wrappedValue ?? -1 },
            set: { selection.wrappedValue = $0 == -1 ? nil : $0; model.invalidatePreview() }
        )) {
            Text("Aucun").tag(-1)
            ForEach(model.fields) { Text($0.name).tag($0.id) }
        } label: {
            HStack(spacing: 14) {
                SettingsIcon(systemName: icon, backgroundColor: color)
                Text(title)
            }
        }
        .pickerStyle(.menu)
        .tint(Color.spinlogPink)
    }

    // MARK: - Aperçu

    @ViewBuilder
    private func previewSections(_ plan: CopyDetailsImport.Plan) -> some View {
        if model.priceFieldId != nil {
            summarySection(title: "Prix d'achat", icon: "tag.fill", summary: plan.price)
            if !plan.currencies.isEmpty {
                Section {
                    ForEach(plan.currencies.keys.sorted(), id: \.self) { code in
                        HStack {
                            Text(code)
                            Spacer()
                            Text(plan.currencies[code] ?? 0, format: .number)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                    if plan.withoutCurrency > 0 {
                        Text("\(plan.withoutCurrency) prix sans devise comptés en \(model.unspecifiedCurrency).")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                } header: {
                    SectionEyebrow(title: "Devises lues", icon: "eurosign.circle")
                }
            }
        }
        if model.conditionFieldId != nil {
            summarySection(title: "État du disque", icon: "opticaldisc.fill", summary: plan.condition)
        }
        if !plan.samples.isEmpty {
            Section {
                ForEach(Array(plan.samples.enumerated()), id: \.offset) { _, sample in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample.title).lineLimit(1)
                        Text("« \(sample.raw) » → \(sample.interpreted)")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            } header: {
                SectionEyebrow(title: "Exemples lus", icon: "eye")
            } footer: {
                Text("Vérifie que ces valeurs correspondent bien au champ choisi.")
            }
        }
        unreadableSection(plan)
        confirmSection(plan)
    }

    private func summarySection(title: LocalizedStringKey, icon: String, summary: CopyDetailsImport.FieldSummary) -> some View {
        Section {
            countRow("À importer", summary.toImport)
            countRow("Déjà identiques", summary.upToDate)
            countRow("Différents de l'app", summary.conflicts)
            countRow("Illisibles", summary.unreadable.count)
            countRow("Vides sur Discogs", summary.emptyOnDiscogs)
        } header: {
            SectionEyebrow(title: title, icon: icon)
        }
    }

    private func countRow(_ title: LocalizedStringKey, _ count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(count, format: .number).foregroundStyle(Color.appSecondaryText)
        }
    }

    @ViewBuilder
    private func unreadableSection(_ plan: CopyDetailsImport.Plan) -> some View {
        let unreadable = plan.price.unreadable + plan.condition.unreadable
        if !unreadable.isEmpty {
            Section {
                ForEach(unreadable.prefix(30)) { value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.title).lineLimit(1)
                        Text("« \(value.raw) »")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
                if unreadable.count > 30 {
                    Text("Et \(unreadable.count - 30) autres.")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
            } header: {
                SectionEyebrow(title: "Valeurs illisibles", icon: "exclamationmark.triangle")
            } footer: {
                Text("Ces valeurs ne sont pas importées et rien n'est effacé. Ces albums restent dans le filtre « À compléter ».")
            }
        }
    }

    private func confirmSection(_ plan: CopyDetailsImport.Plan) -> some View {
        Section {
            if plan.price.conflicts + plan.condition.conflicts > 0 {
                Toggle("Remplacer les valeurs existantes", isOn: $model.replacesExisting)
                    .tint(Color.spinlogPink)
            }
            Button {
                if model.replacesExisting {
                    showingReplaceConfirmation = true
                } else {
                    model.applyImport()
                }
            } label: {
                Text("Importer \(model.operationCount) exemplaires")
            }
            .tint(Color.spinlogPink)
            .disabled(model.operationCount == 0 || model.phase == .applying)
        } footer: {
            Text("Une valeur vide ou illisible sur Discogs n'efface jamais celle de l'app.")
        }
    }

    // MARK: - Annulation

    @ViewBuilder
    private var undoSection: some View {
        if model.canUndo, let date = model.lastImportDate {
            Section {
                Button("Annuler l'import", role: .destructive) { model.undoImport() }
            } footer: {
                Text("Dernier import le \(date.formatted(date: .abbreviated, time: .shortened)). Les exemplaires modifiés depuis gardent leur saisie.")
            }
        }
    }
}
