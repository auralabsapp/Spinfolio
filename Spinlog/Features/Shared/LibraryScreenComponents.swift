import SwiftUI

/// Pièces partagées entre `CollectionView` et `WantlistView`, qui reproduisaient chacun à
/// l'identique (ou presque) la sélection multiple, les menus de tri/affichage, la barre de
/// navigation rapide en overlay et la barre d'actions en lot. Reste dans `Features/Shared/`
/// plutôt que `Design/` : `LibrarySortMenu` référence `CollectionSortOption`, un type propre aux
/// écrans de bibliothèque plutôt qu'un composant d'interface générique.

/// Bascule la sélection d'un élément dans l'ensemble des identifiants sélectionnés, avec le
/// retour haptique léger commun aux deux écrans.
func toggleLibrarySelection<Item: Identifiable>(_ item: Item, selectedItemIds: inout Set<Int>) where Item.ID == Int {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    if selectedItemIds.contains(item.id) {
        selectedItemIds.remove(item.id)
    } else {
        selectedItemIds.insert(item.id)
    }
}

/// Éléments actuellement sélectionnés, dans leur ordre d'apparition (pas celui, non garanti, de
/// `Set`) — surtout utile pour un message de confirmation stable.
func selectedLibraryItems<Item: Identifiable>(
    sections: [(key: String, items: [Item])],
    selectedItemIds: Set<Int>
) -> [Item] where Item.ID == Int {
    sections.flatMap(\.items).filter { selectedItemIds.contains($0.id) }
}

/// Menu "Mode d'affichage" (Liste/Mosaïque/Carrousel), identique sur les deux écrans.
struct LibraryDisplayModeMenu: View {
    @Binding var displayMode: LibraryDisplayMode

    var body: some View {
        Menu {
            Picker("Mode d'affichage", selection: $displayMode) {
                ForEach(LibraryDisplayMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
        } label: {
            Label("Affichage : \(displayMode.title)", systemImage: displayMode.systemImage)
        }
    }
}

/// Menu "Trier par" + sens de tri. `availableOptions` permet à la Wantlist d'exclure `.shelf`
/// (rangement), qui n'a de sens que pour la Collection.
struct LibrarySortMenu: View {
    @Binding var sortOption: CollectionSortOption
    @Binding var sortAscending: Bool
    var availableOptions: [CollectionSortOption] = CollectionSortOption.allCases

    var body: some View {
        Menu {
            Picker("Trier par", selection: $sortOption) {
                ForEach(availableOptions) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }

            Picker("Sens", selection: $sortAscending) {
                Label("Croissant", systemImage: "arrow.up").tag(true)
                Label("Décroissant", systemImage: "arrow.down").tag(false)
            }
        } label: {
            Label("Tri : \(sortOption.title)", systemImage: sortOption.systemImage)
        }
    }
}

/// Section épinglée en haut de la liste, pour la pastille de position de la barre d'index. Vit
/// dans un objet à part, que l'écran ne lit jamais dans son `body` : seul `LibraryIndexBarOverlay`
/// l'observe, si bien qu'un changement de section pendant le défilement ne réévalue plus tout
/// l'écran (sections, badges, tags), seulement la barre.
@Observable @MainActor
final class LibraryCurrentSectionTracker {
    var key: String?

    /// N'écrit que si la valeur change, pour ne rien invalider à chaque image du défilement.
    func update(to newKey: String?) {
        if newKey != key { key = newKey }
    }
}

/// Barre de navigation rapide (A-Z/Années) en overlay sur la vue qui défile effectivement (liste
/// ou grille) — identique entre les deux écrans, paramétrée par les sections de l'un ou l'autre.
struct LibraryIndexBarOverlay<Item>: View {
    let indexEntries: [(token: String, sectionKey: String)]
    let sectionTracker: LibraryCurrentSectionTracker
    let sections: [(key: String, items: [Item])]
    let indexToken: ((key: String, items: [Item])) -> String
    let proxy: ScrollViewProxy

    /// Jeton de la section courante (plusieurs sections — un artiste par section — peuvent
    /// partager le même jeton, leur première lettre commune).
    private var currentIndexToken: String? {
        guard let currentSectionKey = sectionTracker.key,
              let section = sections.first(where: { $0.key == currentSectionKey }) else { return nil }
        return indexToken(section)
    }

    var body: some View {
        if indexEntries.count > 1 {
            SectionIndexBar(entries: indexEntries, currentToken: currentIndexToken) { sectionKey in
                proxy.scrollTo(sectionKey, anchor: .top)
            }
            .padding(.trailing, 4)
            .transition(.opacity)
        }
    }
}

/// Bouton de fin de sélection (coche), seul élément de la barre d'outils pendant la sélection
/// multiple — identique sur les deux écrans.
@ToolbarContentBuilder
func finishLibrarySelectionToolbarItem(isSelecting: Binding<Bool>, selectedItemIds: Binding<Set<Int>>) -> some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
        Button {
            withAnimation {
                isSelecting.wrappedValue = false
                selectedItemIds.wrappedValue.removeAll()
            }
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel("Terminer la sélection")
    }
}

/// Barre d'actions en lot façon app Fichiers : pile flottante en vrai Liquid Glass
/// (`glassEffect`) qui remplace la barre d'onglets pendant la sélection, icônes grisées tant
/// qu'aucun élément n'est sélectionné plutôt que la barre entière qui disparaîtrait. Seul le
/// contenu (nombre et nature des boutons) diffère entre Collection et Wantlist.
struct LibraryBulkActionsBar<Content: View>: View {
    let isSelecting: Bool
    let isEmpty: Bool
    let isProcessing: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if isSelecting {
            GlassEffectContainer {
                content
                    .tint(.primary)
                    .disabled(isEmpty || isProcessing)
                    .opacity(isEmpty ? 0.4 : 1)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .glassEffect(.regular.interactive())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
        }
    }
}

extension View {
    /// Calque de (dé)sélection des vues Liste/Mosaïque/Carrousel en mode sélection : sans ça, ce
    /// calque transparent n'existait pas pour VoiceOver, qui lisait le lien vers la fiche (inactif
    /// pendant la sélection) et ne permettait de cocher aucun disque.
    func librarySelectionAccessibility(info: BasicInformation, isSelected: Bool, onToggle: @escaping () -> Void) -> some View {
        accessibilityElement()
            .accessibilityLabel(Text("\(info.title), \(info.artistNames)"))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(Text(isSelected ? "Touche deux fois pour désélectionner." : "Touche deux fois pour sélectionner."))
            .accessibilityAction { onToggle() }
    }
}
