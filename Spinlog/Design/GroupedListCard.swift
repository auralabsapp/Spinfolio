import SwiftUI

/// Liste de lignes séparées par de fins séparateurs dans une carte groupée façon Apple Music —
/// partagée par la gestion des tags et la gestion des dossiers.
struct GroupedListCard<Element, ID: Hashable, Row: View>: View {
    let items: [Element]
    let id: KeyPath<Element, ID>
    @ViewBuilder let row: (Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items, id: id) { item in
                row(item)
                if item[keyPath: id] != items.last?[keyPath: id] {
                    Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)
                }
            }
        }
        .padding(.vertical, 4)
        .appleMusicGroupedCard()
    }
}
