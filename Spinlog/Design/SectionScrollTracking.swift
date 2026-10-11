import SwiftUI

/// Position de chaque en-tête de section actuellement visible (Collection/Wantlist, listes et
/// grilles), mesurée depuis le haut de sa zone de défilement — sert à savoir laquelle est
/// épinglée en haut en ce moment (voir `SectionScrollTracking.topSectionKey` et la pastille de
/// `SectionIndexBar`). Clé : la même « section key » que `LibrarySectionHeader`.
struct SectionHeaderOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
                    value: [key: geometry.frame(in: .named(coordinateSpace)).minY]
                )
            }
        )
    }
}

enum SectionScrollTracking {
    /// Section actuellement épinglée en haut, parmi les en-têtes actuellement visibles (ou tout
    /// près) : avec des en-têtes de section collants (`.listStyle(.plain)`, `pinnedViews:
    /// [.sectionHeaders]`), celui de la section active est accroché à 0 tandis que les suivants,
    /// pas encore atteints, restent à un décalage positif — c'est donc le minimum.
    static func topSectionKey(from offsets: [String: CGFloat]) -> String? {
        offsets.min(by: { $0.value < $1.value })?.key
    }
}
