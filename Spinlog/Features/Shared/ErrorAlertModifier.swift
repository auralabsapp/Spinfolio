import SwiftUI

extension View {
    /// Alerte à bouton unique "OK", pilotée par un seul `Binding<String?>` — pas de booléen de
    /// présentation séparé qui pourrait se désynchroniser du message (même principe que
    /// `viewModel.actionMessage` dans `CollectionView`, qui utilise directement le message comme
    /// titre). Avant ce modifier, plusieurs écrans réinventaient chacun leur propre paire
    /// `Bool`/`String?` pour ce même besoin ("afficher une erreur ponctuelle").
    ///
    /// Titre et message de repli en `LocalizedStringKey` : en `String`, ils ne seraient ni extraits
    /// dans le catalogue ni traduits.
    func errorAlert(_ title: LocalizedStringKey = "Erreur", message: Binding<String?>, fallbackMessage: LocalizedStringKey = "") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let text = message.wrappedValue {
                Text(verbatim: text)
            } else {
                Text(fallbackMessage)
            }
        }
    }

    /// Variante où le message lui-même sert de titre, sans corps séparé — même forme que
    /// `viewModel.actionMessage` dans `CollectionView`, le exemple qui avait motivé ce fichier.
    func messageAlert(message: Binding<String?>) -> some View {
        alert(
            message.wrappedValue ?? "",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Variante avec un titre (`Text`, pour rester traduit) au-dessus du message, et une action
    /// facultative au toucher de « OK » (ex. fermer le scan par lot une fois le lot ajouté).
    func messageAlert(_ title: Text, message: Binding<String?>, onDismiss: @escaping () -> Void = {}) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel, action: onDismiss)
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
