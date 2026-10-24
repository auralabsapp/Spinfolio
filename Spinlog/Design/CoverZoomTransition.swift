import SwiftUI

extension EnvironmentValues {
    /// Espace de noms reliant les pochettes de la Collection/Wantlist (sources) à la fiche qu'elles
    /// ouvrent (destination, voir `View.searchDestinations(coverZoom:)`). `nil` hors de ces écrans :
    /// la navigation reste alors un simple empilement.
    @Entry var coverZoomNamespace: Namespace.ID? = nil
}

private struct CoverZoomSourceModifier: ViewModifier {
    let releaseId: Int
    let cornerRadius: CGFloat
    @Environment(\.coverZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: releaseId, in: namespace) { source in
                // Même arrondi que la pochette : sinon le zoom part d'un rectangle à angles droits.
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

extension View {
    /// Fait de cette pochette le point de départ du zoom vers la fiche de `releaseId`. À poser sur la
    /// pochette seule (avant ombres et superpositions), pas sur toute la ligne. Un même disque en
    /// plusieurs exemplaires partage l'identifiant : le zoom part alors de l'un d'eux.
    func coverZoomSource(releaseId: Int, cornerRadius: CGFloat) -> some View {
        modifier(CoverZoomSourceModifier(releaseId: releaseId, cornerRadius: cornerRadius))
    }

    /// Fiche ouverte en zoom depuis la pochette correspondante ; sans espace de noms, navigation classique.
    @ViewBuilder
    func coverZoomDestination(releaseId: Int, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            navigationTransition(.zoom(sourceID: releaseId, in: namespace))
        } else {
            self
        }
    }
}
