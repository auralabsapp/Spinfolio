import SwiftUI

/// Bouton de fermeture universel pour bottom sheets, respectant les standards actuels d'iOS.
/// Propose un style standard (croix épurée, pour barre d'outils) et un style `.prominentOnMedia`
/// à fort contraste pour s'afficher par-dessus une image, une vidéo ou un en-tête graphique.
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var size: CGFloat = 16
    var style: Style = .standard
    var action: (() -> Void)? = nil

    enum Style {
        case standard
        case prominentOnMedia
    }

    var body: some View {
        Button {
            if let action {
                action()
            } else {
                dismiss()
            }
        } label: {
            switch style {
            case .standard:
                Image(systemName: "xmark")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .expandedHitArea(visibleSide: 32)

            case .prominentOnMedia:
                let buttonDimension = max(32, size)
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)

                    Circle()
                        .fill(Color.black.opacity(0.42))

                    Image(systemName: "xmark")
                        .font(.system(size: max(13, buttonDimension * 0.42), weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: buttonDimension, height: buttonDimension)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)
                .expandedHitArea(visibleSide: buttonDimension)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fermer")
    }
}
