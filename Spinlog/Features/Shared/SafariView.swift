import SwiftUI
import WebKit

/// Affiche une page web externe (fiche Discogs, annonce marketplace, CGU...) dans une `WKWebView`
/// à session persistante mais isolée de Safari, plutôt que dans un `SFSafariViewController`.
///
/// `SFSafariViewController` partage toujours ses cookies avec l'app Safari du système — c'est un
/// choix délibéré d'Apple (aucune API ne permet de l'en isoler) puisque son intérêt est justement
/// de refléter la session Safari de l'utilisateur. Mais l'app gère elle-même plusieurs comptes
/// Discogs via OAuth : si l'utilisateur (ou une session précédente) s'était connecté à discogs.com
/// dans Safari, ces pages restaient connectées à ce compte indéfiniment, même après une
/// déconnexion/reconnexion à un autre compte dans l'app.
///
/// Important : l'app ne détient qu'un jeton API OAuth (pour interroger l'API Discogs), jamais le
/// mot de passe du compte — Discogs n'offre aucun pont entre les deux. Il est donc impossible de
/// connecter automatiquement cette webview au compte actif ; l'utilisateur doit s'y connecter
/// lui-même une fois, comme dans n'importe quel navigateur tiers. Le store `WKWebsiteDataStore`
/// utilisé ici (`.default()`) est persistant (la session reste ouverte d'une fois sur l'autre) et
/// propre à Spinlog (jamais partagé avec Safari) — voir `DiscogsAuthManager.logout()`, qui la vide
/// systématiquement pour qu'elle ne puisse jamais afficher un compte différent de celui actif dans
/// l'app.
/// Enveloppe `Identifiable` pour présenter une `SafariView` via `.sheet(item:)`/`.fullScreenCover(item:)`
/// — préférer `item:` à un `Bool` associé à une propriété séparée, source d'une course d'état déjà
/// rencontrée dans ce projet (voir `UserProfileSheet`). Tout lien vers discogs.com doit passer par
/// `SafariView` (jamais `Link`/`openURL`, qui ouvriraient Safari externe et sa session partagée).
/// Domaines autorisés dans la webview de l'app, qui garde la session discogs.com de l'utilisateur.
/// Une page d'un autre site (lien externe d'une fiche, d'un profil, d'une annonce) s'ouvre dans
/// Safari plutôt que dans cette session.
nonisolated enum DiscogsWebPolicy {
    /// Fournisseurs de connexion proposés par la page de connexion Discogs (« Continuer avec… ») :
    /// sans eux, se connecter à discogs.com dans la webview avec Google, Apple ou Facebook échouerait.
    private static let identityProviderHosts: Set<String> = [
        "accounts.google.com", "appleid.apple.com", "www.facebook.com", "m.facebook.com"
    ]

    /// Domaines dont les données web sont vidées à la déconnexion : Discogs, et les fournisseurs
    /// de connexion (une session Google, Apple ou Facebook restée ouverte reconnectait sinon le
    /// compte suivant au même compte). `displayName` d'un `WKWebsiteDataRecord` = domaine principal.
    private static let sessionDomains: Set<String> = ["discogs.com", "google.com", "apple.com", "facebook.com"]

    static func isSessionRecord(displayName: String) -> Bool {
        let name = displayName.lowercased()
        return sessionDomains.contains { name == $0 || name.hasSuffix(".\($0)") }
    }

    static func isDiscogs(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "discogs.com" || host.hasSuffix(".discogs.com")
    }

    /// Navigation de la page principale autorisée dans la webview ?
    static func allowsInAppNavigation(to url: URL?) -> Bool {
        guard let url else { return false }
        if url.scheme?.lowercased() == "about" { return true }
        if isDiscogs(url) { return true }
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return identityProviderHosts.contains(host)
    }
}

struct SafariViewRequest: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: View {
    /// Vide la session web persistante (cookies, stockage local...) utilisée par toutes les
    /// `SafariView` de l'app. À appeler impérativement à chaque déconnexion Discogs
    /// (`DiscogsAuthManager.logout()`) : sans ça, un compte resterait connecté dans ces webviews
    /// même après connexion à un autre compte dans l'app.
    static func clearPersistedDiscogsSession() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let sessionRecords = records.filter { DiscogsWebPolicy.isSessionRecord(displayName: $0.displayName) }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: sessionRecords) {}
        }
    }

    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                EphemeralWebView(url: url, isLoading: $isLoading)
                if isLoading {
                    ProgressView()
                }
            }
            .navigationTitle(url.host ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetCloseButton {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Ouvrir dans Safari")
                }
            }
        }
    }
}

private struct EphemeralWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    func makeUIView(context: Context) -> WKWebView {
        // `.default()` : store persistant mais propre à Spinlog (jamais partagé avec Safari ni
        // SFSafariViewController). La session Discogs qu'on y ouvre manuellement survit donc d'un
        // affichage à l'autre — voir `SafariView.clearPersistedDiscogsSession()`, appelée à la
        // déconnexion pour qu'elle ne puisse jamais représenter un autre compte que celui actif.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        /// Hors de Discogs, la page principale ne change plus dans la webview : le lien s'ouvre
        /// dans Safari. Les cadres intégrés (vérification anti-robot, lecteurs) restent autorisés.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            let url = navigationAction.request.url
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            guard isMainFrame, !DiscogsWebPolicy.allowsInAppNavigation(to: url) else { return .allow }
            if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                await UIApplication.shared.open(url)
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}
