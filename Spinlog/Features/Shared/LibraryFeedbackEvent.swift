import Foundation

/// Ce qui vient de changer dans la bibliothèque de l'utilisateur à son initiative (ajout ou retrait
/// d'une release), pour que l'écran concerné réagisse (haptique, rebond) — sans réagir aux
/// changements d'état dus au simple chargement de la fiche.
struct LibraryFeedbackEvent: Equatable {
    enum Kind: Equatable {
        case addedToCollection, removedFromCollection, addedToWantlist, removedFromWantlist

        var isAddition: Bool { self == .addedToCollection || self == .addedToWantlist }
    }

    let kind: Kind
    /// Distingue deux événements identiques successifs (ajout, retrait, nouvel ajout).
    private let token = UUID()

    init(_ kind: Kind) {
        self.kind = kind
    }
}
