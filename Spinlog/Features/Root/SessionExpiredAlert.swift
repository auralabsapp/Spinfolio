import SwiftUI

/// Alerte « Ta session Discogs a expiré », montrée une seule fois quand Discogs refuse le jeton du compte
/// (révoqué sur discogs.com ou expiré). « Plus tard » laisse l'app lisible hors Discogs ; les modifications en
/// attente restent en file et repartent après la reconnexion. Dans un modificateur à part : l'ajouter à
/// `RootTabView` rendait son `body` trop long à vérifier pour le compilateur.
struct SessionExpiredAlertModifier: ViewModifier {
    @State private var authManager = DiscogsAuthManager.shared

    func body(content: Content) -> some View {
        content.alert("Ta session Discogs a expiré", isPresented: $authManager.showsSessionExpiredAlert) {
            Button("Se reconnecter") { authManager.reconnectAfterSessionExpired() }
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text("Discogs ne reconnaît plus l'autorisation de l'app (elle a peut-être été révoquée sur discogs.com). Reconnecte-toi pour reprendre la synchronisation : tes tags, écoutes et modifications en attente sont conservés.")
        }
    }
}
