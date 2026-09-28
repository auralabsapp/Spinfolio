import SwiftUI
import SafariServices

/// Enrobe `SFSafariViewController` pour ouvrir un lien externe (ex: page marketplace Discogs)
/// dans une vue Safari intégrée plutôt que de quitter l'app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
