import SwiftUI

/// Animations à ressort réutilisées à l'identique pour le même geste dans plusieurs écrans.
/// Centralisées ici pour éviter la dérive cosmétique de copier-coller (ex: `0.45/0.86` à un
/// endroit, `0.45/0.8` ou `0.58/0.86` à un autre pour le même "défiler jusqu'à cet élément"),
/// qui ne change rien au bug mais désynchronise discrètement des gestes censés se ressentir pareil.
extension Animation {
    /// Bascule de sélection (coche/bordure) sur une pochette ou une ligne — mosaïque, carrousel et
    /// liste de la Collection/Wantlist.
    static let librarySelectionToggle = Animation.spring(response: 0.28, dampingFraction: 0.85)

    /// Défilement animé vers un élément ou une section précise (barre de navigation rapide,
    /// « Disque au hasard ») — Collection (listes, grille, carrousel) et Wantlist (carrousel).
    static let scrollToItem = Animation.spring(response: 0.45, dampingFraction: 0.85)

    /// Apparition/disparition de la mini-lecture en cours (mini-player, Live Activity).
    static let nowPlayingTransition = Animation.spring(response: 0.35, dampingFraction: 0.82)
}
