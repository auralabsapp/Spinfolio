import SafariServices
import SwiftUI

/// Page web de notre propre site (assistance...) dans un `SFSafariViewController`, la vue Safari du
/// système. Réservé aux pages qui n'ont rien à voir avec Discogs : `SafariView` (WKWebView isolée)
/// refuse toute page hors discogs.com et l'ouvre dans Safari (voir `DiscogsWebPolicy`), ce qui
/// laisserait ici une feuille vide. Les cookies partagés avec Safari sont sans conséquence pour une
/// page statique qui ne connaît aucun compte.
/// À présenter avec `fullScreenCover(item:)` : la vue a sa propre barre et son bouton « OK ».
struct SystemSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
