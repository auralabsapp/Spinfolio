import SwiftUI

/// Cloche d'alerte de prix posée sur la jaquette du carrousel de la Wantlist. Mêmes couleurs que la
/// cloche des lignes de la liste (vert si déclenchée, rose si active, gris tertiaire sinon) ; un
/// disque clair derrière elle la garde lisible sur n'importe quelle pochette.
struct CoverAlertBellButton: View {
    let title: String
    let alert: WantlistAlert?
    let isRegularDisplay: Bool
    let action: () -> Void

    /// Compteur qui déclenche le rebond du symbole au toucher.
    @State private var bounce = 0

    private var isTriggered: Bool { alert?.isTriggered == true }
    private var hasActiveAlert: Bool { alert != nil }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            bounce += 1
            action()
        } label: {
            Image(systemName: isTriggered ? "bell.badge.fill" : "bell.fill")
                .symbolEffect(.bounce, options: .nonRepeating, value: bounce)
                .font(isRegularDisplay ? .title3 : .body)
                .foregroundStyle(isTriggered ? Color.gainPositive : (hasActiveAlert ? Color.spinlogPink : Color.appTertiaryText))
                .frame(width: isRegularDisplay ? 44 : 40, height: isRegularDisplay ? 44 : 40)
                .background(Color.coverBellDisc, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(AlertBellButtonStyle())
        .padding(isRegularDisplay ? 12 : 8)
        .accessibilityLabel(
            isTriggered
                ? "Alerte de prix déclenchée : offre trouvée pour \(title)"
                : (hasActiveAlert ? "Alerte active pour \(title)" : "Créer une alerte pour \(title)")
        )
    }
}
