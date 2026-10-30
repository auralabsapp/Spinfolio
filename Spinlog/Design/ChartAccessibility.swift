import SwiftUI

/// Un élément d'un graphique tel que VoiceOver l'annonce.
struct ChartAccessibilityEntry: Identifiable {
    let id: String
    let name: String
    let valueText: String
}

extension View {
    /// À poser sur le calque transparent qui reçoit les touches d'un graphique (`chartOverlay`).
    ///
    /// Ce calque était annoncé comme un bouton « Sélectionner… » sans effet utile pour VoiceOver
    /// (un double-tap touche le centre du graphique). Il devient l'élément qui résume le graphique
    /// (principales valeurs), et chaque entrée est proposée en action VoiceOver pour ouvrir ses
    /// disques, comme le ferait un toucher. Les marques du graphique doivent être masquées
    /// (`.accessibilityHidden(true)`) pour ne pas être lues en double.
    func chartSelectionAccessibility(
        label: Text,
        entries: [ChartAccessibilityEntry],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Text(entries.prefix(5).map { "\($0.name), \($0.valueText)" }.joined(separator: " ; ")))
            .accessibilityHint(Text("Ouvre le menu des actions pour afficher les albums d'un élément."))
            .accessibilityActions {
                ForEach(entries) { entry in
                    Button(entry.name) { onSelect(entry.id) }
                }
            }
    }
}
