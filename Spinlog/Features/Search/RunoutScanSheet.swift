import SwiftUI

/// Feuille de capture du numéro de matrice/runout d'un exemplaire (fonctionnalité premium) :
/// photo/scan du texte gravé au centre du vinyle via VisionKit, correction manuelle, puis
/// enregistrement dans le champ personnalisé configuré dans les réglages
/// (`CollectionPreferencesStore.matrixFieldId`). Si la release possède déjà des identifiants
/// "Matrix / Runout" connus de Discogs, ils sont proposés en comparaison pour aider à repérer
/// le bon pressage quand plusieurs exemplaires partagent le même code-barres.
struct RunoutScanSheet: View {
    let instanceId: Int
    let actions: ReleaseActions
    var knownIdentifiers: [ReleaseIdentifier] = []

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var isScannerPresented = false
    @State private var scannerError: String?

    init(instanceId: Int, currentValue: String, actions: ReleaseActions, knownIdentifiers: [ReleaseIdentifier] = []) {
        self.instanceId = instanceId
        self.actions = actions
        self.knownIdentifiers = knownIdentifiers
        _text = State(initialValue: currentValue)
    }

    private var matrixIdentifiers: [ReleaseIdentifier] {
        knownIdentifiers.filter { identifier in
            let normalized = identifier.type.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return normalized.contains("matrix") || normalized.contains("runout")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(title: "Numéro de matrice / runout", icon: "opticaldisc.fill")

                        TextField("Ex: ABC-123-A1", text: $text, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(2...4)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .appleMusicGroupedCard()

                        Button {
                            isScannerPresented = true
                        } label: {
                            Label("Scanner le runout", systemImage: "camera.viewfinder")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.spinlogPink)

                        Text("Vise le texte gravé au centre du disque, puis touche la ligne à retenir. Corrige-la ensuite si besoin : la gravure est souvent difficile à lire automatiquement.")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                    }

                    if !matrixIdentifiers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionEyebrow(title: "Références connues sur Discogs", icon: "checkmark.seal")
                            VStack(spacing: 0) {
                                ForEach(Array(matrixIdentifiers.enumerated()), id: \.offset) { index, identifier in
                                    Button {
                                        text = identifier.value
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(identifier.value)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                if let description = identifier.description, !description.isEmpty {
                                                    Text(description)
                                                        .font(.caption)
                                                        .foregroundStyle(Color.appSecondaryText)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                            if matches(identifier.value, text) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.spinlogPink)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    if index < matrixIdentifiers.count - 1 {
                                        Divider().opacity(0.15).padding(.leading, 14)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .appleMusicGroupedCard()

                            Text("Touche une référence pour la reprendre telle quelle, ou pour comparer visuellement avec ce que tu as scanné.")
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Matrix / Runout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Enregistrer") { save() }
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.spinlogPink)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $isScannerPresented) {
            NavigationStack {
                TextRecognitionScannerRepresentable(
                    onSelect: { transcript in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        text = transcript
                        isScannerPresented = false
                    },
                    onError: { error in
                        scannerError = error.localizedDescription
                        isScannerPresented = false
                    }
                )
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Annuler") { isScannerPresented = false }
                    }
                }
                .overlay(alignment: .bottom) {
                    Text("Touche la ligne gravée correspondant au numéro de matrice")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(.bottom, 32)
                }
            }
        }
        .alert("Scanner indisponible", isPresented: Binding(
            get: { scannerError != nil },
            set: { if !$0 { scannerError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scannerError ?? "")
        }
    }

    /// Comparaison volontairement simple (insensible à la casse/diacritiques, sans tenir compte
    /// des espaces) : sert uniquement d'indice visuel, pas d'une validation stricte — les
    /// numéros de matrice n'ont pas de format standardisé entre pressages.
    private func matches(_ a: String, _ b: String) -> Bool {
        func normalize(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
        }
        let normalizedA = normalize(a)
        let normalizedB = normalize(b)
        guard !normalizedA.isEmpty, !normalizedB.isEmpty else { return false }
        return normalizedA == normalizedB || normalizedA.contains(normalizedB) || normalizedB.contains(normalizedA)
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        Task {
            await actions.updateMatrixValue(trimmed, for: instanceId)
            isSaving = false
            dismiss()
        }
    }
}
