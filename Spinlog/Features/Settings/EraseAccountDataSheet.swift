import SwiftUI

/// Dernière étape avant d'effacer toutes les données de l'app (locales et iCloud) : une feuille à
/// part qui dit en toutes lettres ce qui sera perdu — chiffres à l'appui — et demande de taper son
/// nom d'utilisateur Discogs, pour qu'un effacement ne puisse pas arriver par un simple toucher
/// de trop. Le journal d'écoute n'existe nulle part ailleurs (Discogs ne le garde pas) : une fois
/// effacé, il est perdu pour de bon.
struct EraseAccountDataSheet: View {
    /// Effacement réel, lancé seulement une fois la confirmation tapée.
    let onErase: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var authManager = DiscogsAuthManager.shared
    @State private var typedName = ""
    @FocusState private var isFieldFocused: Bool
    private static let fieldAnchor = "confirmationField"

    private var username: String { authManager.username ?? "" }
    private var isConfirmed: Bool {
        Self.isConfirmationValid(typed: typedName, expected: username)
    }

    /// Le nom tapé correspond au compte (sans tenir compte de la casse ni des espaces autour) :
    /// règle pure, testée à part. Un nom attendu vide ne se confirme jamais.
    nonisolated static func isConfirmationValid(typed: String, expected: String) -> Bool {
        let expected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else { return false }
        return typed.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(expected) == .orderedSame
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Un toucher hors du champ le quitte et referme le clavier (le champ, lui, garde ses
                        // propres touchers : le geste n'est posé que sur le texte explicatif).
                        VStack(alignment: .leading, spacing: 22) {
                            header
                            lossesCard
                            reassurance
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { isFieldFocused = false }

                        confirmationField
                            .id(Self.fieldAnchor)
                    }
                    .padding()
                }
                .onChange(of: isFieldFocused) { _, focused in
                    guard focused else { return }
                    // Le clavier met un instant à monter : on attend qu'il ait réduit la zone visible pour
                    // centrer le champ dedans.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard isFieldFocused else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(Self.fieldAnchor, anchor: .center)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color.appBackground.ignoresSafeArea())
                .navigationTitle("Effacer mes données")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SheetCloseButton()
                            .accessibilityLabel("Annuler")
                    }
                    // Le clavier n'a pas toujours de touche de validation : « OK » referme le clavier.
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("OK") { isFieldFocused = false }
                            .fontWeight(.semibold)
                    }
                }
                .safeAreaInset(edge: .bottom) { eraseButton }
            }
        }
        // Toujours en grand : texte, quantités, champ et bouton rouge doivent tenir sans défiler.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Contenu

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.red)
                .accessibilityHidden(true)
            Text("Cette action est définitive")
                .font(.title3.bold())
            Text("Ton historique d'écoute, tes tags et tes alertes seront perdus définitivement, y compris sur iCloud. Impossible de les récupérer ensuite.")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Ce qui sera effacé, avec les quantités réelles (une ligne par type de donnée non vide).
    private var lossesCard: some View {
        let listening = ListeningLogStore.shared.sessions.count
        let tagged = TagStore.shared.allTaggedInstanceIds().count
        let alerts = WantlistAlertStore.shared.allAlertReleaseIds().count
        let hasGrades = GradeTrack.allCases.contains { GradeStore.shared.acquiredTiers(for: $0) > 0 }
        return VStack(alignment: .leading, spacing: 0) {
            if listening > 0 {
                lossRow(symbol: "opticaldisc.fill", Text("\(listening) écoutes sur platine"))
            }
            if tagged > 0 {
                lossRow(symbol: "tag.fill", Text("\(tagged) exemplaires avec des tags"))
            }
            if alerts > 0 {
                lossRow(symbol: "bell.fill", Text("\(alerts) alertes de prix"))
            }
            if hasGrades {
                lossRow(symbol: "rosette", Text("Tes grades"))
            }
            lossRow(symbol: "gearshape.fill", Text("Préférences, caches et données hors ligne"))
        }
        .padding(.vertical, 4)
        .appleMusicGroupedCard()
        .accessibilityElement(children: .combine)
    }

    private func lossRow(symbol: String, _ text: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.red)
                .frame(width: 24)
                .accessibilityHidden(true)
            text
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var reassurance: some View {
        Label {
            Text("Tes albums restent sur Discogs : seules les données propres à l'app sont effacées. Tu seras déconnecté.")
                .font(.footnote)
                .foregroundStyle(Color.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Color.gainPositive)
        }
    }

    private var confirmationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pour confirmer, tape ton nom d'utilisateur Discogs :")
                .font(.footnote.weight(.semibold))
            Text(username)
                .font(.footnote.monospaced())
                .foregroundStyle(Color.appSecondaryText)
            TextField("Nom d'utilisateur", text: $typedName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .submitLabel(.done)
                .focused($isFieldFocused)
                .onSubmit { isFieldFocused = false }
                .padding(12)
                .appleMusicGroupedCard(cornerRadius: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isConfirmed ? Color.red.opacity(0.7) : Color.clear, lineWidth: 1.5)
                )
        }
    }

    private var eraseButton: some View {
        Button(role: .destructive) {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            onErase()
            dismiss()
        } label: {
            Text("Effacer définitivement mes données")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.red)
        .disabled(!isConfirmed)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

extension View {
    /// Feuille de confirmation finale de l'effacement des données de l'app (voir `EraseAccountDataSheet`).
    func eraseAccountDataSheet(isPresented: Binding<Bool>, onErase: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            EraseAccountDataSheet(onErase: onErase)
        }
    }
}
