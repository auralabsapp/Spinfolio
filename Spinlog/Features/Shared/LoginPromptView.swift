import SwiftUI

/// État "non connecté", affiché dans Collection et Wantlist tant que l'utilisateur
/// n'a pas terminé le flow OAuth Discogs.
struct LoginPromptView: View {
    let message: String
    @State private var authManager = DiscogsAuthManager.shared
    @State private var safariRequest: SafariViewRequest?

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

                // Inscription dans la webview Discogs de l'app ; une fois le compte créé (et
                // l'adresse e-mail confirmée), l'utilisateur revient se connecter ci-dessus.
                Button("Pas de compte ? Crée-en un") {
                    safariRequest = SafariViewRequest(url: DiscogsConstants.accountCreationURL)
                }
                .font(.subheadline.weight(.medium))
                .tint(Color.spinlogPink)
                .disabled(authManager.isAuthenticating)
                .accessibilityIdentifier("createDiscogsAccountButton")

                Button("Explorer avec une collection de démo") {
                    authManager.startDemo()
                }
                .buttonStyle(.glass)
                .disabled(authManager.isAuthenticating)

                if let error = authManager.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .sheet(item: $safariRequest) { request in
            SafariView(url: request.url)
        }
    }
}
