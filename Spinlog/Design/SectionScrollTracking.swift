import SwiftUI

/// Position de l'en-tête de section le plus proche du haut de sa zone de défilement (Collection/
/// Wantlist, listes et grilles) — sert à savoir laquelle est épinglée en haut en ce moment, pour
/// la pastille de position de `SectionIndexBar`. Clé : la même « section key » que
/// `LibrarySectionHeader`.
///
/// Ne porte qu'un seul candidat (celui au `minY` le plus petit), pas un dictionnaire de toutes
/// les sections visibles : avec 150-200 sections (ex. tri par Artiste sur une grosse collection),
/// l'ancienne version (`[String: CGFloat]` fusionné via `value.merge(...)`) allouait et fusionnait
/// un dictionnaire à chaque frame de défilement, pour chaque en-tête visible. Comparer deux
/// `Candidate` (valeur scalaire) coûte une comparaison, pas une allocation — le `GeometryReader`
/// par en-tête reste nécessaire (SwiftUI doit mesurer sa position), mais ce qu'on en fait pour
/// déterminer « lequel est en haut » ne coûte plus rien de notable.
struct SectionHeaderOffsetKey: PreferenceKey {
    struct Candidate: Equatable {
        let key: String
        let minY: CGFloat
    }

    static var defaultValue: Candidate? = nil

    /// Avec des en-têtes de section collants (`.listStyle(.plain)`, `pinnedViews:
    /// [.sectionHeaders]`), celui de la section active est accroché à 0 tandis que les suivants,
    /// pas encore atteints, restent à un décalage positif — c'est donc le minimum qui l'identifie.
    static func reduce(value: inout Candidate?, nextValue: () -> Candidate?) {
        guard let next = nextValue() else { return }
        guard let current = value else {
            value = next
            return
        }
        if next.minY < current.minY {
            value = next
        }
    }
}

extension View {
    /// À poser sur l'en-tête de chaque section, à l'intérieur d'une zone de défilement nommée via
    /// `.coordinateSpace(name: coordinateSpace)` (sur la `List`/`ScrollView` elle-même) : rapporte
    /// sa position actuelle le long du défilement.
    func reportingSectionOffset(key: String, coordinateSpace: String) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SectionHeaderOffsetKey.self,
                    value: SectionHeaderOffsetKey.Candidate(
                        key: key,
                        minY: geometry.frame(in: .named(coordinateSpace)).minY
                    )
                )
            }
        )
    }
}
