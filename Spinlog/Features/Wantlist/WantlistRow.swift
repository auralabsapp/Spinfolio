import SwiftUI

struct WantlistRow: View {
    /// Référencée par `SkeletonLibraryRow` (via `LibraryListView`) pour que son gabarit de
    /// chargement reste de la même taille que la vraie pochette, sans retaper la valeur — voir
    /// le même principe sur `CollectionRow.coverSize`.
    static let coverSize: CGFloat = 56

    let item: WantlistItem
    var onAlertTap: (() -> Void)? = nil
    var isSelecting: Bool = false
    var isSelected: Bool = false

    private var info: BasicInformation { item.basicInformation }
    private var alertStore = WantlistAlertStore.shared
    /// Compteur qui déclenche le rebond de la cloche au toucher.
    @State private var bellBounce = 0

    private var alert: WantlistAlert? {
        alertStore.alert(for: item.id)
    }

    private var hasActiveAlert: Bool {
        alert != nil
    }

    private var isTriggered: Bool {
        alert?.isTriggered == true
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.spinlogPink : Color.appTertiaryText)
                    .motionTransition(.scale.combined(with: .opacity))
            }

            AsyncCoverImage(url: info.thumb ?? info.coverImage, cornerRadius: AppLayout.coverCornerRadius, targetSize: Self.coverSize)
                .frame(width: Self.coverSize, height: Self.coverSize)
                .coverZoomSource(releaseId: item.id, cornerRadius: AppLayout.coverCornerRadius)
                // Micro-bordure pour l'épaisseur carton, remplacée par la bordure de sélection
                // quand cet exemplaire est coché.
                .overlay {
                    if isSelecting && isSelected {
                        RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                            .strokeBorder(Color.spinlogPink, lineWidth: 2.5)
                    } else {
                        RoundedRectangle(cornerRadius: AppLayout.coverCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                }
                .opacity(isSelecting ? (isSelected ? 1.0 : 0.45) : 1.0)
                // Ombres physiques adaptées automatiquement aux modes clair et sombre
                .vinylCoverShadow(isSelecting: isSelecting, isSelected: isSelected)
                .animation(.librarySelectionToggle, value: isSelected)

            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(info.artistNames)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let onAlertTap, !isSelecting {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    bellBounce += 1
                    onAlertTap()
                } label: {
                    Image(systemName: isTriggered ? "bell.badge.fill" : (hasActiveAlert ? "bell.fill" : "bell"))
                        .symbolEffect(.bounce, options: .nonRepeating, value: bellBounce)
                        .font(.system(size: 16))
                        .foregroundStyle(isTriggered ? Color.gainPositive : (hasActiveAlert ? Color.spinlogPink : Color.appTertiaryText))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AlertBellButtonStyle())
                .accessibilityLabel(
                    isTriggered
                        ? "Alerte de prix déclenchée : offre trouvée pour \(info.title)"
                        : (hasActiveAlert ? "Alerte active pour \(info.title)" : "Créer une alerte pour \(info.title)")
                )
            }
        }
        .padding(.vertical, 2)
    }
}
