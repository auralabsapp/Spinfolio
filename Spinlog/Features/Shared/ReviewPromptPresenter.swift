import SwiftUI
import StoreKit

/// Présente la demande d'avis du système quand `ReviewPromptStore` signale un palier franchi, à un
/// moment calme : app active, aucune feuille ni alerte ouverte, aucune célébration de grade. Vue à
/// part, qui seule lit le store, pour ne pas invalider `RootTabView`.
///
/// Appel retardé, jamais en réponse directe à un geste : le système décide seul d'afficher ou non la
/// demande (plafond annuel, avis déjà donné sur l'appareil), et la documentation déconseille de la
/// lier à une action visible.
struct ReviewPromptPresenter: View {
    @Environment(\.requestReview) private var requestReview
    private let store = ReviewPromptStore.shared

    /// Pause entre deux vérifications : laisse finir la fermeture de la feuille d'écoute (1,5 s).
    private static let checkInterval: Duration = .seconds(2)
    /// Au-delà (30 s sans moment calme), la demande est abandonnée.
    private static let maxChecks = 15

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: store.pendingRequestID) { await presentWhenQuiet() }
    }

    private func presentWhenQuiet() async {
        guard store.pendingRequestID != nil else { return }
        for _ in 0..<Self.maxChecks {
            try? await Task.sleep(for: Self.checkInterval)
            // Annulée (nouvelle demande, déconnexion) : la suivante prend le relais.
            guard !Task.isCancelled else { return }
            guard Self.isQuiet else { continue }
            if store.consumePendingRequest() { requestReview() }
            return
        }
        store.discardPendingRequest()
    }

    private static var isQuiet: Bool {
        UIApplication.shared.applicationState == .active
            && GradeStore.shared.pendingCelebration == nil
            && !isPresentingModal
    }

    /// Une feuille, un plein écran ou une alerte est ouvert (le paywall, l'écoute sur platine, le
    /// scan par lot… passent tous par une présentation UIKit).
    private static var isPresentingModal: Bool {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else { return false }
        return root.presentedViewController != nil
    }
}
