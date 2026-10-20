import SwiftUI

/// Mini étiquette dorée « ✨ PREMIUM », partagée par `PremiumLockedCard` et `DemoPremiumBadge`.
struct PremiumPill: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "sparkles")
                .font(.inlineIcon)
            Text("PREMIUM")
                .font(.emphasisLabel)
        }
        .foregroundStyle(Color.goldText)
        .lineLimit(1)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.goldBadgeBg, in: Capsule())
        .fixedSize(horizontal: true, vertical: true)
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
