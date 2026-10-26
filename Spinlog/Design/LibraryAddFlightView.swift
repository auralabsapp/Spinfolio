import SwiftUI

/// Une pochette qui « part » vers l'onglet où le disque vient d'être ajouté (voir
/// `LibraryMembershipStore.activeFlight`).
struct LibraryAddFlight: Identifiable, Equatable {
    nonisolated enum Destination: Equatable {
        case collection, wantlist
    }

    let id = UUID()
    let coverURL: String?
    let destination: Destination
}

/// Géométrie du vol, calculée à part pour être testée : SwiftUI ne donne pas la position des
/// icônes d'une `TabView` système, on vise donc un point déduit de la largeur de l'écran (la barre
/// flottante d'iOS 26 : une capsule de quatre onglets, et la recherche isolée à droite).
nonisolated enum LibraryAddFlightGeometry {
    private static let barHorizontalInset: CGFloat = 21
    /// Place prise à droite par l'onglet de recherche, séparé des autres.
    private static let searchTabReservedWidth: CGFloat = 70
    private static let regularTabCount: CGFloat = 4
    /// Marge intérieure de la capsule : les icônes ne touchent pas son bord, la première est donc
    /// plus à droite que le simple quart de sa largeur.
    private static let barInnerPadding: CGFloat = 16
    private static let barHeight: CGFloat = 62
    /// La capsule flotte : son bord bas dépasse un peu dans la zone du bandeau d'accueil sur un
    /// iPhone à bandeau (34 pt), et reste à quelques points du bord sur un iPhone sans bandeau.
    private static let minimumBottomMargin: CGFloat = 8
    private static let bottomMarginInsideSafeArea: CGFloat = 8

    /// Point d'arrivée, au centre de l'icône de l'onglet.
    static func landingPoint(for destination: LibraryAddFlight.Destination, screen: CGSize, bottomInset: CGFloat) -> CGPoint {
        let itemWidth = (screen.width - 2 * barHorizontalInset - searchTabReservedWidth) / regularTabCount
        let index: CGFloat = destination == .collection ? 0.5 : 1.5
        return CGPoint(
            x: barHorizontalInset + barInnerPadding + itemWidth * index,
            y: screen.height - barBottomMargin(bottomInset: bottomInset) - barHeight / 2
        )
    }

    /// Distance entre le bord bas de l'écran et le bord bas de la capsule des onglets.
    static func barBottomMargin(bottomInset: CGFloat) -> CGFloat {
        max(bottomInset - bottomMarginInsideSafeArea, minimumBottomMargin)
    }

    /// Point de départ, au milieu de l'écran, à peu près là où se trouvait la pochette de la fiche.
    static func startPoint(screen: CGSize) -> CGPoint {
        CGPoint(x: screen.width / 2, y: screen.height * 0.42)
    }
}

/// Vol de la pochette vers la barre d'onglets, puis halo à l'arrivée. Décoratif : la bulle de
/// confirmation et le haptique de l'ajout restent le retour principal. Absent avec « Réduire les
/// animations ».
struct LibraryAddFlightOverlay: View {
    let flight: LibraryAddFlight?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Le `GeometryReader` respecte la zone sûre (sinon ses marges seraient nulles) : on y lit ses
        // marges réelles, puis le contenu, lui, s'étend à l'écran entier.
        GeometryReader { proxy in
            if let flight, !reduceMotion {
                let insets = proxy.safeAreaInsets
                LibraryAddFlightContent(
                    flight: flight,
                    screen: CGSize(width: proxy.size.width, height: proxy.size.height + insets.top + insets.bottom),
                    bottomInset: insets.bottom
                )
                .id(flight.id)
                .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Choix du bouton d'onglet visé parmi les boutons réellement visibles, calculé à part pour être
/// testé. Relevé sur iPhone 17 (iOS 27) :
/// - barre déployée : 5 boutons de 81 à 94 pt de large (Collection, Wantlist, Stats, Réglages,
///   Recherche), tous dans la même capsule ;
/// - barre réduite : 2 pastilles de 48 pt seulement, l'onglet actif à gauche et la recherche à
///   droite. Les autres onglets n'existent plus : le « bouton n° 1 » y est la loupe.
nonisolated enum TabBarIconSelection {
    /// En deçà, un bouton est une pastille de barre réduite.
    static let reducedButtonMaxWidth: CGFloat = 56

    static func isReduced(_ frames: [CGRect]) -> Bool {
        frames.contains { $0.width <= reducedButtonMaxWidth }
    }

    /// Retire les cadres en double : la barre déployée contient deux jeux identiques des mêmes
    /// cinq boutons (contenu normal et contenu sélectionné). Sans cela, « le bouton n° 1 » serait
    /// un doublon de la Collection.
    static func uniqueFrames(_ frames: [CGRect]) -> [CGRect] {
        var seen = Set<[Int]>()
        return frames.filter { frame in
            seen.insert([frame.minX, frame.minY, frame.width, frame.height].map { Int(($0 * 2).rounded()) }).inserted
        }
    }

    static func landingFrame(for destination: LibraryAddFlight.Destination, among frames: [CGRect]) -> CGRect? {
        let sorted = uniqueFrames(frames).sorted { $0.minX < $1.minX }
        if isReduced(sorted) {
            // L'onglet visé n'est pas forcément affiché : on vise la pastille de gauche, celle que
            // l'utilisateur voit à la place de la barre. Les boutons larges qui resteraient dans la
            // hiérarchie sans être visibles sont ignorés.
            return sorted.first { $0.width <= reducedButtonMaxWidth }
        }
        let index = destination == .collection ? 0 : 1
        return sorted.indices.contains(index) ? sorted[index] : nil
    }
}

/// Position réelle de l'icône d'onglet, lue dans la hiérarchie UIKit quand elle est repérable
/// (la barre d'onglets système n'expose rien à SwiftUI) ; `nil` : on retombe sur le calcul de
/// `LibraryAddFlightGeometry`, valable sur tous les iPhone mais approximatif.
@MainActor
private enum TabBarIconLocator {
    static func landingPoint(for destination: LibraryAddFlight.Destination) -> CGPoint? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow),
            let tabBar = firstSubview(of: UITabBar.self, in: window),
            !tabBar.isHidden, tabBar.alpha > 0.01
        else { return nil }
        let barFrame = tabBar.convert(tabBar.bounds, to: window)
        // Une barre repérable doit être en bas de l'écran.
        guard barFrame.height > 30, barFrame.maxY > window.bounds.height - 4 else { return nil }
        // Boutons d'onglet (classe privée reconnue par son nom, sans l'appeler) réellement
        // visibles : un bouton masqué, transparent ou hors écran ne compte pas (barre réduite).
        var buttons: [UIView] = []
        collect(in: tabBar, into: &buttons)
        let frames = buttons
            .filter(isEffectivelyVisible)
            .map { $0.convert($0.bounds, to: window) }
            .filter { $0.width > 20 && $0.height > 20 && window.bounds.insetBy(dx: -1, dy: -1).contains($0) }
        guard let frame = TabBarIconSelection.landingFrame(for: destination, among: frames) else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Ni lui ni aucun de ses parents n'est masqué ou (presque) transparent.
    private static func isEffectivelyVisible(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate.isHidden || candidate.alpha < 0.05 { return false }
            current = candidate.superview
        }
        return true
    }

    private static func firstSubview<T: UIView>(of type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstSubview(of: type, in: subview) { return match }
        }
        return nil
    }

    /// Bouton d'onglet : classe privée reconnue par son nom (`_UITabButton` sous iOS 27,
    /// `UITabBarButton` avant), ou à défaut tout élément d'accessibilité de type bouton de la barre.
    private static func isTabButton(_ view: UIView) -> Bool {
        let name = String(describing: type(of: view))
        if name.contains("TabButton") || name.contains("TabBarButton") { return true }
        return view.isAccessibilityElement && view.accessibilityTraits.contains(.button)
    }

    private static func collect(in view: UIView, into buttons: inout [UIView]) {
        for subview in view.subviews {
            if isTabButton(subview) {
                buttons.append(subview)
            } else {
                collect(in: subview, into: &buttons)
            }
        }
    }
}

private struct LibraryAddFlightContent: View {
    let flight: LibraryAddFlight
    let screen: CGSize
    let bottomInset: CGFloat

    @State private var hasLanded = false
    /// Le halo n'existe qu'à partir de l'arrivée de la pochette : présent dès le départ, il
    /// s'affichait en petit cercle sur l'icône avant même que la pochette ne parte.
    @State private var isHaloShown = false
    /// Point d'arrivée, figé au lancement du vol : la barre ne doit pas le déplacer en cours de route.
    @State private var end: CGPoint

    init(flight: LibraryAddFlight, screen: CGSize, bottomInset: CGFloat) {
        self.flight = flight
        self.screen = screen
        self.bottomInset = bottomInset
        _end = State(initialValue: TabBarIconLocator.landingPoint(for: flight.destination)
            ?? LibraryAddFlightGeometry.landingPoint(for: flight.destination, screen: screen, bottomInset: bottomInset))
    }

    private static let coverSize: CGFloat = 76
    private static let flightDuration = 0.6

    var body: some View {
        let start = LibraryAddFlightGeometry.startPoint(screen: screen)

        ZStack {
            if isHaloShown {
                LibraryAddFlightHalo()
                    .position(end)
            }

            AsyncCoverImage(url: flight.coverURL, cornerRadius: AppLayout.coverCornerRadius, targetSize: Self.coverSize)
                .frame(width: Self.coverSize, height: Self.coverSize)
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
                .scaleEffect(hasLanded ? 0.28 : 1)
                .opacity(hasLanded ? 0 : 1)
                .animation(.easeIn(duration: Self.flightDuration), value: hasLanded)
                // Deux courbes pour deux axes : l'horizontale part vite, la verticale accélère, d'où une
                // trajectoire courbe plutôt qu'une droite.
                .offset(x: hasLanded ? end.x - start.x : 0)
                .animation(.easeOut(duration: Self.flightDuration), value: hasLanded)
                .offset(y: hasLanded ? end.y - start.y : 0)
                .animation(.easeIn(duration: Self.flightDuration), value: hasLanded)
                .position(start)
        }
        .task {
            withAnimation { hasLanded = true }
            try? await Task.sleep(for: .seconds(Self.flightDuration - 0.1))
            isHaloShown = true
        }
    }
}

/// Halo à l'arrivée : naît petit et opaque sur l'icône, puis grandit en s'effaçant. Il s'anime à
/// sa propre apparition, donc il est invisible tant que la pochette n'est pas arrivée.
private struct LibraryAddFlightHalo: View {
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .strokeBorder(Color.spinlogPink, lineWidth: 3)
            .frame(width: 44, height: 44)
            .scaleEffect(isExpanded ? 1.5 : 0.4)
            .opacity(isExpanded ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { isExpanded = true }
            }
    }
}
