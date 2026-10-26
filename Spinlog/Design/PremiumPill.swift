import SwiftUI

/// Étiquette dorée « PREMIUM », seule version de l'app (trois styles différents coexistaient) :
/// discrète (`PremiumLockedCard`, `DemoPremiumBadge`, thème Premium) ou pleine (en-tête du paywall).
struct PremiumPill: View {
    enum Style {
        /// Texte doré sur fond doré léger.
        case standard
        /// Fond dégradé or plein, texte contrasté (le blanc ne donnait que 1,6 à 2,8:1 sur l'or).
        case prominent
    }

    var style: Style = .standard

    /// Texte posé sur le dégradé or : calculé une fois (le dégradé ne dépend pas du thème).
    private static let prominentText = Color(uiColor: AccentContrast.text(
        on: UIColor(Color.goldLight), UIColor(Color.goldWarm)
    ))

    var body: some View {
        switch style {
        case .standard:
            label(icon: "sparkles", spacing: 2)
                .foregroundStyle(Color.goldText)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.goldBadgeBg, in: Capsule())
                .fixedSize(horizontal: true, vertical: true)
        case .prominent:
            label(icon: "crown.fill", spacing: 4)
                .foregroundStyle(Self.prominentText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.goldButtonGradient, in: Capsule())
                .shadow(color: Color.goldWarm.opacity(0.35), radius: 4, y: 1)
                .fixedSize(horizontal: true, vertical: true)
        }
    }

    private func label(icon: String, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Image(systemName: icon)
                .font(.inlineIcon)
            Text("PREMIUM")
                .font(.emphasisLabel)
        }
        .lineLimit(1)
    }
}

/// Étiquette posée sur une fonction Premium pendant l'aperçu de la démo : tout y est débloqué,
/// elle montre au visiteur ce qu'il perdrait sans abonnement. Invisible hors démo, et pour un
/// abonné qui essaie la démo (rien ne lui serait retiré).
struct DemoPremiumBadge: View {
    @State private var premiumStore = PremiumStore.shared

    var body: some View {
        if premiumStore.showsDemoPremiumBadges {
            PremiumPill()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Fonction Premium, offerte pendant la démo"))
        }
    }
}
