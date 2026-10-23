import SwiftUI

/// Bouton « Supprimer cette alerte » de la feuille d'alerte de prix. Il ne supprime rien lui-même :
/// l'appelant demande confirmation (`confirmationDialog`) avant d'effacer l'alerte.
struct DeleteAlertButton: View {
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            HStack {
                Spacer()
                Label("Supprimer cette alerte", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
        }
        .listRowBackground(Color.clear)
    }
}
