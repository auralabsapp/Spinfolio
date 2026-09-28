import SwiftUI

/// État "non connecté", affiché dans Collection et Wantlist tant que l'utilisateur
/// n'a pas terminé le flow OAuth Discogs.
struct LoginPromptView: View {
    let message: String
    @State private var authManager = DiscogsAuthManager.shared

    var body: some View {
        ContentUnavailableView {
            Label("Connecte-toi à Discogs", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: 12) {
                Button {
                    Task { await authManager.login() }
                } label: {
                    if authManager.isAuthenticating {
                        ProgressView()
                    } else {
                        Text("Se connecter")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(authManager.isAuthenticating)

                if let error = authManager.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}
