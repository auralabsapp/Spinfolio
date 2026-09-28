import SwiftUI
import WebKit

/// Enrobe une `WKWebView` chargeant la page d'embed YouTube (`youtube.com/embed/{id}`) :
/// lecture native dans l'app (y compris le plein écran propre à la vidéo), sans jamais quitter
/// Spinlog vers Safari ou l'app YouTube.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0") else { return }
        webView.load(URLRequest(url: url))
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
                    Button("Fermer") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.spinlogPink)
                }
            }
        }
    }
}
