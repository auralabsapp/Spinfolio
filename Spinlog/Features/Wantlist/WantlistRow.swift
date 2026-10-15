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
                    .transition(.scale.combined(with: .opacity))
            }

            AsyncCoverImage(url: info.thumb ?? info.coverImage, cornerRadius: 8, targetSize: Self.coverSize)
                .frame(width: Self.coverSize, height: Self.coverSize)
                // Micro-bordure pour l'épaisseur carton, remplacée par la bordure de sélection
                // quand cet exemplaire est coché.
                .overlay {
                    if isSelecting && isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.spinlogPink, lineWidth: 2.5)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                }
                .opacity(isSelecting ? (isSelected ? 1.0 : 0.45) : 1.0)
                // Ombre de contact (très proche) puis ombre d'ambiance flottante (large et douce) ;
                // toutes deux atténuées pendant la sélection multiple, comme l'opacité de la pochette.
                .shadow(color: .black.opacity(isSelecting ? (isSelected ? 0.30 : 0.12) : 0.22), radius: 5, x: 0, y: 3)
                .shadow(color: .black.opacity(isSelecting ? (isSelected ? 0.45 : 0.18) : 0.35), radius: 16, x: 0, y: 10)
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
                    onAlertTap()
                } label: {
                    Image(systemName: isTriggered ? "bell.badge.fill" : (hasActiveAlert ? "bell.fill" : "bell"))
                        .font(.system(size: 16))
                        .foregroundStyle(isTriggered ? Color.green : (hasActiveAlert ? Color.spinlogPink : Color.appTertiaryText))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
