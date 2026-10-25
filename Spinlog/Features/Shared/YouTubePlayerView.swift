import SwiftUI
import WebKit

/// Enrobe une `WKWebView` chargeant la page d'embed YouTube (`youtube.com/embed/{id}`) :
/// lecture native dans l'app (y compris le plein écran propre à la vidéo), sans jamais quitter
/// Spinlog vers Safari ou l'app YouTube.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    /// Retient l'ID déjà chargé pour ne recharger la page (et donc redémarrer la vidéo) que
    /// lorsque celui-ci change réellement. Sans ça, `updateUIView` — appelé à chaque re-rendu
    /// SwiftUI, y compris lors d'une simple rotation de l'écran — rechargeait l'iframe et
    /// remettait la lecture à zéro.
    final class Coordinator {
        var loadedVideoID: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Stockage éphémère, jamais celui de `SafariView` : la page est chargée avec l'origine
        // discogs.com et ne doit pas pouvoir lire la session Discogs de l'utilisateur.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Défense en profondeur : l'identifiant est inséré tel quel dans le HTML ci-dessous.
        guard ReleaseVideo.isValidYouTubeID(videoID),
              context.coordinator.loadedVideoID != videoID else { return }
        context.coordinator.loadedVideoID = videoID

        // Certaines vidéos restreignent l'intégration à une liste de domaines autorisés par leur
        // propriétaire. Discogs, qui intègre ces mêmes vidéos sur ses propres fiches release,
        // s'authentifie auprès de YouTube avec `origin=https://www.discogs.com` (visible dans les
        // URLs de son lecteur) : on reprend cette origine plutôt que youtube.com, qui n'est pas
        // reconnue comme un domaine tiers autorisé et déclenchait "Cette vidéo n'est pas disponible".
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
            <style>
                html, body { margin: 0; padding: 0; background-color: black; }
                iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: none; }
            </style>
        </head>
        <body>
            <iframe
                src="https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0&autoplay=1&origin=\(DiscogsConstants.websiteURL.absoluteString)"
                frameborder="0"
                allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture"
                allowfullscreen>
            </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: DiscogsConstants.websiteURL)
    }
}

/// Requête d'ouverture du lecteur vidéo intégré, encapsulée dans un type `Identifiable`
/// pour piloter `.fullScreenCover(item:)`.
struct VideoPlayerRequest: Identifiable {
    let id = UUID()
    let videoID: String
    let title: String
}

/// Feuille plein écran affichant le lecteur YouTube intégré, avec titre et bouton de fermeture.
struct VideoPlayerSheet: View {
    let request: VideoPlayerRequest

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                YouTubePlayerView(videoID: request.videoID)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }
}
