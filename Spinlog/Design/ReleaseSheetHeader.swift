import SwiftUI

/// En-tête commun des feuilles consacrées à un disque (« Mon exemplaire », « Alerte de prix ») :
/// jaquette en grand avec un halo de sa couleur moyenne, titre, artiste et pastilles de contexte
/// (année, format, dossier…).
/// État d'une alerte de prix, tel que la cloche le montre : grise sans alerte, rose si elle est
/// active, verte si elle est déclenchée (comme la cloche des lignes de la Wantlist).
enum AlertBellState {
    case none, active, triggered

    var symbolName: String {
        switch self {
        case .none, .active: "bell.fill"
        case .triggered: "bell.badge.fill"
        }
    }

    var color: Color {
        switch self {
        case .none: Color.appTertiaryText
        case .active: Color.spinlogPink
        case .triggered: Color.gainPositive
        }
    }
}

struct ReleaseSheetHeader: View {
    let coverURL: String?
    let title: String
    let artist: String
    var pills: [String] = []
    /// État de la cloche d'alerte posée sur la jaquette (`nil` : pas de cloche). Mêmes couleurs que
    /// la cloche de la liste Wantlist ; elle balance une fois quelques instants après l'ouverture.
    var alertBell: AlertBellState? = nil
    /// Reçoit la couleur moyenne de la pochette dès qu'elle est chargée (pour teinter le fond de la
    /// feuille, voir `releaseTintedBackground`).
    var onAverageColorLoaded: ((UIColor) -> Void)? = nil

    private static let coverSize: CGFloat = 112

    @State private var bellBounce = 0

    var body: some View {
        VStack(spacing: 12) {
            AsyncCoverImage(
                url: coverURL,
                cornerRadius: 12,
                targetSize: Self.coverSize,
                onAverageColorLoaded: onAverageColorLoaded
            )
            .frame(width: Self.coverSize, height: Self.coverSize)
            .overlay(alignment: .topTrailing) {
                if let alertBell {
                    Image(systemName: alertBell.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(alertBell.color)
                        .symbolEffect(.bounce, options: .nonRepeating, value: bellBounce)
                        .frame(width: 28, height: 28)
                        .background(Color.coverBellDisc, in: Circle())
                        .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2.5))
                        .offset(x: 10, y: -10)
                        .task {
                            try? await Task.sleep(for: .milliseconds(700))
                            bellBounce += 1
                        }
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
            .shadow(color: .black.opacity(0.30), radius: 18, x: 0, y: 10)
            .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            }

            if !pills.isEmpty {
                HStack(spacing: 6) {
                    ForEach(pills, id: \.self) { pill in
                        Text(pill)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.appSecondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Fond de feuille : fond de l'app, avec un dégradé doux de la couleur moyenne de la pochette
    /// en haut (comme les fiches et la page artiste). Sans couleur connue, fond de l'app seul.
    func releaseTintedBackground(_ tint: UIColor?) -> some View {
        background {
            ZStack(alignment: .top) {
                Color.appBackground
                if let tint {
                    LinearGradient(
                        colors: [Color(uiColor: tint).opacity(0.38), .clear],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.45)
                    )
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: tint != nil)
        }
    }
}
