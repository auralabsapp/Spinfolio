import SwiftUI

/// Ligne de champ personnalisé Discogs : libellé à gauche, contrôle adapté au type à droite
/// (texte, case à cocher, menu déroulant), ou en pleine largeur pour les zones de texte longues.
/// Dispose d'un bouton coche dédié pour forcer la validation et l'envoi immédiat à Discogs,
/// et valide automatiquement dès que l'utilisateur clique en dehors du champ (perte de focus).
/// Même carte par ligne que le reste de la feuille (dossier, tags…) : pas de fond supplémentaire
/// propre à chaque contrôle, qui ferait double emploi avec `.appleMusicGroupedCard()` et
/// alourdirait la liste. Un menu déroulant ou une case à cocher se signalent déjà d'eux-mêmes
/// (chevron système, interrupteur) ; un simple champ texte, sans ce genre d'indice visuel natif,
/// reçoit un petit crayon discret tant qu'il est vide et qu'on n'y touche pas — une fois rempli,
/// sa valeur s'affiche dans le rose de l'app, cet indice-là suffit.
struct CollectionFieldControl: View {
    let field: CollectionField
    @Binding var value: String
    let isDirty: Bool
    let isSaving: Bool
    let justSaved: Bool
    let onSave: () -> Void

    @FocusState private var isFocused: Bool

    private var hasValue: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsEditHint: Bool {
        !isFocused && !isDirty && !isSaving && !justSaved && !hasValue
    }

    var body: some View {
        Group {
            if field.isTextArea {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(field.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        editHintIcon
                        trailingStatusView
                    }
                    TextField(field.name, text: $value, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(hasValue ? Color.spinlogPink : .primary)
                        .lineLimit(3...6)
                        .focused($isFocused)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if field.isCheckbox {
                HStack {
                    Toggle(isOn: Binding(
                        get: { value == "1" },
                        set: { value = $0 ? "1" : "0" }
                    )) {
                        Text(field.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .tint(Color.spinlogPink)

                    trailingStatusView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else if field.isDropdown {
                HStack {
                    Text(field.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Picker("", selection: $value) {
                        Text("—").tag("")
                        ForEach(field.options ?? [], id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Color.spinlogPink)

                    trailingStatusView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                HStack {
                    Text(field.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    editHintIcon
                    TextField(field.name, text: $value)
                        .font(.subheadline)
                        .foregroundStyle(hasValue ? Color.spinlogPink : .primary)
                        .multilineTextAlignment(.trailing)
                        .focused($isFocused)
                        .onSubmit {
                            isFocused = false
                            if isDirty && !isSaving {
                                onSave()
                            }
                        }

                    trailingStatusView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .onChange(of: isFocused) { wasFocused, nowFocused in
            if wasFocused && !nowFocused {
                if isDirty && !isSaving {
                    onSave()
                }
            }
        }
        .onChange(of: value) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if (field.isDropdown || field.isCheckbox) && isDirty && !isSaving {
                onSave()
            }
        }
    }

    /// Crayon discret, même symbole que l'action de swipe "Modifier" ailleurs dans l'app : le
    /// seul indice dont un simple champ texte a besoin pour se signaler comme modifiable, sans
    /// repasser dessus un fond ou une bordure qui romprait avec le reste de la feuille.
    @ViewBuilder
    private var editHintIcon: some View {
        if showsEditHint {
            Image(systemName: "pencil")
                .font(.caption2)
                .foregroundStyle(Color.appTertiaryText)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var trailingStatusView: some View {
        if isSaving {
            ProgressView()
                .controlSize(.small)
                .padding(.leading, 6)
        } else if justSaved {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .padding(.leading, 6)
                .transition(.scale.combined(with: .opacity))
        } else if isDirty {
            Button {
                isFocused = false
                onSave()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.spinlogPink)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Valider et enregistrer ce champ sur Discogs")
        }
    }
}
