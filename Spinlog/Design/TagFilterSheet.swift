import SwiftUI

/// Sélecteur multi-tags pour filtrer Collection/Wantlist (sémantique ET : tous les tags cochés
/// doivent être présents sur l'exemplaire).
///
/// Volontairement une feuille plutôt qu'un `Menu` : un `Menu` se referme après chaque appui sur
/// un bouton, ce qui rend une sélection multiple réelle impossible (l'utilisateur ne peut cocher
/// qu'un tag avant que tout le menu se ferme). Cette feuille reste ouverte le temps de cocher
/// plusieurs tags d'affilée.
struct TagFilterSheet: View {
    let allTags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        NavigationStack {
            List {
                ForEach(allTags, id: \.self) { tag in
                    Button {
                        if selectedTags.contains(tag) {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                    } label: {
                        HStack {
                            Text(tag)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedTags.contains(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.spinlogPink)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle("Filtrer par tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !selectedTags.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Tout désélectionner", role: .destructive) {
                            selectedTags.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
