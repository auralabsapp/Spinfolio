import SwiftUI

/// Affiche les tags actuels d'un exemplaire avec un bouton "Ajouter" ouvrant une bottom sheet
/// de gestion et d'attribution des tags. Persisté par `TagStore`, jamais envoyé à Discogs.
struct TagsEditor: View {
    let instanceId: Int
    var releaseId: Int? = nil

    @State private var store = TagStore.shared
    @State private var showingManagementSheet = false

    init(instanceId: Int, releaseId: Int? = nil) {
        self.instanceId = instanceId
        self.releaseId = releaseId
    }

    init(releaseId: Int) {
        self.instanceId = releaseId
        self.releaseId = releaseId
    }

    var body: some View {
        let tags = store.tags(for: instanceId, releaseId: releaseId)
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagPill(tag: tag) {
                    // Sans `withAnimation`, les pochettes restantes (et le bouton "Ajouter") se
                    // replacent d'un bloc dans ce `FlowLayout` dès que celle-ci disparaît — très
                    // visible dès qu'il y a assez de tags pour occuper plusieurs lignes, puisque
                    // retirer un tag peut alors faire remonter toute une ligne d'un coup.
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        store.removeTag(tag, from: instanceId, releaseId: releaseId)
                    }
                }
            }

            Button {
                showingManagementSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.bold))
                    Text(tags.isEmpty ? "Ajouter un tag" : "Ajouter")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .foregroundStyle(Color.appSecondaryText)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingManagementSheet) {
            ReleaseTagSheet(instanceId: instanceId, releaseId: releaseId)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Bottom sheet de gestion et d'attribution des tags pour un exemplaire
struct ReleaseTagSheet: View {
    let instanceId: Int
    var releaseId: Int? = nil

    init(instanceId: Int, releaseId: Int? = nil) {
        self.instanceId = instanceId
        self.releaseId = releaseId
    }

    init(releaseId: Int) {
        self.instanceId = releaseId
        self.releaseId = releaseId
    }

    @Environment(\.dismiss) private var dismiss
    @State private var store = TagStore.shared
    @State private var searchText = ""
    /// Barre de recherche maison (voir `searchBar`) plutôt que `.searchable()` : ce dernier
    /// réduit/masque le titre de la barre de navigation et déplace la croix de fermeture dès que
    /// le champ prend le focus (comportement système lié à `UISearchController`), en plus
    /// d'absorber le premier tap sur la croix pendant que la recherche est active — aucune des
    /// deux ne doit se produire ici : la structure de la fenêtre doit rester identique, focus ou
    /// non. Un simple `TextField` (même principe que `SearchView.searchBar`) n'a aucune de ces
    /// intégrations spéciales à la barre de navigation.
    @FocusState private var isSearchFieldFocused: Bool
    @State private var renameItem: TagRenameItem? = nil
    @State private var tagToDelete: String? = nil
    @State private var duplicateTagError: String? = nil
    @State private var showingMaxLengthAlert = false
    @State private var showingMaxTagsAlert = false

    private var appliedTags: Set<String> {
        Set(store.tags(for: instanceId, releaseId: releaseId))
    }

    private var hasReachedMaxTags: Bool {
        appliedTags.count >= TagConstants.maxTagsPerInstance
    }

    /// Tente d'attribuer `tag` à l'exemplaire, ou affiche une alerte si la limite est déjà atteinte.
    private func attemptAddTag(_ tag: String) {
        guard !hasReachedMaxTags else {
            showingMaxTagsAlert = true
            return
        }
        store.addTag(tag, to: instanceId, releaseId: releaseId)
    }

    /// Barre de recherche maison, même principe que `SearchView.searchBar` : un `TextField` nu
    /// plutôt que `.searchable()`, pour que le focus n'affecte jamais le titre ni la position de
    /// la croix de fermeture dans la barre de navigation (voir le commentaire sur
    /// `isSearchFieldFocused`).
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appSecondaryText)

            TextField("Rechercher ou créer un tag", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if exactMatchExists {
                        duplicateTagError = trimmed
                    } else {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        attemptAddTag(trimmed)
                        searchText = ""
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appSecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var filteredTags: [String] {
        let all = store.allTags
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var exactMatchExists: Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.allTags.contains { $0.caseInsensitiveCompare(query) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

                    searchBar

                    // Bouton de création directe et fluide via la recherche
                    if !trimmed.isEmpty && !exactMatchExists {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            attemptAddTag(trimmed)
                            searchText = ""
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.spinlogPink)

                                Text("Créer et ajouter « \(trimmed) »")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.spinlogPink)

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .appleMusicGroupedCard()
                    } else if !trimmed.isEmpty && exactMatchExists {
                        // Indication sobre que le tag existe déjà
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)

                            Text("Tag déjà existant")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .appleMusicGroupedCard()
                    }

                    if store.allTags.isEmpty && trimmed.isEmpty {
                        VStack(alignment: .center, spacing: 14) {
                            Image(systemName: "tag")
                                .font(.system(size: 44))
                                .foregroundStyle(Color.spinlogPink.opacity(0.8))

                            Text("Aucun tag créé")
                                .font(.headline)

                            Text("Tape un nom dans la barre de recherche ci-dessus pour créer et attribuer ton premier tag.")
                                .font(.subheadline)
                                .foregroundStyle(Color.appSecondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .padding(.horizontal, 20)
                    } else {
                        // Filtré une seule fois : relu dans chaque ligne, le filtre était refait
                        // pour chaque tag à chaque frappe.
                        let tags = filteredTags
                        VStack(alignment: .leading, spacing: 10) {
                            SectionEyebrow(title: "Tags disponibles (\(tags.count))", icon: "tag.fill")

                            VStack(spacing: 0) {
                                ForEach(Array(tags.enumerated()), id: \.element) { index, tag in
                                    tagRow(tag)
                                    if index < tags.count - 1 {
                                        Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 14)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .appleMusicGroupedCard()

                            (SwipeActionsSupport.isAvailable ? Text("Touche un tag pour l'attribuer. Glisse vers la gauche pour le modifier ou le supprimer.") : Text("Touche un tag pour l'attribuer. Maintiens le doigt dessus pour le modifier ou le supprimer."))
                                .font(.footnote)
                                .foregroundStyle(Color.appSecondaryText)

                            Text("\(appliedTags.count)/\(TagConstants.maxTagsPerInstance) tags attribués à cet exemplaire")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(hasReachedMaxTags ? .orange : Color.appSecondaryText)
                        }
                    }
                }
                .padding()
            }
            // `.simultaneousGesture` plutôt qu'un `.onTapGesture` exclusif : il se déclenche EN
            // PLUS du tap d'une ligne ou d'un bouton (cocher/décocher un tag, "Créer et ajouter"…)
            // au lieu de le remplacer, pour que fermer le clavier ne demande jamais un premier tap
            // "perdu" avant que l'action elle-même ne soit prise en compte.
            .simultaneousGesture(
                TapGesture().onEnded {
                    isSearchFieldFocused = false
                }
            )
            .swipeActionsContainerIfAvailable()
            .navigationTitle("Gestion des tags")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: searchText) { _, newValue in
                if newValue.count > TagConstants.maxNameLength {
                    searchText = String(newValue.prefix(TagConstants.maxNameLength))
                    showingMaxLengthAlert = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
            .sheet(item: $renameItem) { item in
                TagRenameSheet(tag: item.tag)
            }
            .confirmationDialog(
                "Supprimer le tag",
                isPresented: Binding(
                    get: { tagToDelete != nil },
                    set: { if !$0 { tagToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    if let tag = tagToDelete {
                        store.deleteTag(tag)
                    }
                    tagToDelete = nil
                }
                Button("Annuler", role: .cancel) {
                    tagToDelete = nil
                }
            } message: {
                if let tag = tagToDelete {
                    let count = store.releaseCount(for: tag)
                    Text("Veux-tu vraiment supprimer « \(tag) » ? Ce tag sera retiré de \(count) disques.")
                }
            }
            .alert("Tag déjà existant", isPresented: Binding(
                get: { duplicateTagError != nil },
                set: { if !$0 { duplicateTagError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    duplicateTagError = nil
                }
            } message: {
                if let name = duplicateTagError {
                    Text("Le tag « \(name) » existe déjà dans ta bibliothèque.")
                }
            }
            .alert("Nom trop long", isPresented: $showingMaxLengthAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Le nom d'un tag est limité à \(TagConstants.maxNameLength) caractères.")
            }
            .alert("Limite de tags atteinte", isPresented: $showingMaxTagsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Un exemplaire ne peut pas avoir plus de \(TagConstants.maxTagsPerInstance) tags. Retires-en un pour en attribuer un autre.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func tagRow(_ tag: String) -> some View {
        let isApplied = appliedTags.contains(tag)
        return HStack(spacing: 12) {
            Text(tag)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.tagBackground, in: Capsule())
                .foregroundStyle(Color.tagForeground)

            Spacer()

            let count = store.instanceCount(for: tag)
            Text("\(count) ex.")
                .font(.footnote)
                .foregroundStyle(Color.appSecondaryText)

            Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isApplied ? Color.spinlogPink : Color.secondary.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(!isApplied && hasReachedMaxTags ? 0.4 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Cette feuille n'affiche pas elle-même les pochettes de l'exemplaire (voir
            // `TagsEditor.body`), mais la bascule doit tout de même être animée : sans ça, la
            // ligne de pochettes réapparaît déjà dans son état final, non animée, dès que cette
            // feuille se ferme.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                if isApplied {
                    store.removeTag(tag, from: instanceId, releaseId: releaseId)
                } else {
                    attemptAddTag(tag)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                tagToDelete = tag
            } label: {
                Label("Supprimer", systemImage: "trash.fill")
            }
            .tint(.red)
            .labelStyle(.iconOnly)
            .accessibilityLabel("Supprimer ce tag")

            Button {
                renameItem = TagRenameItem(tag: tag)
            } label: {
                Label("Modifier", systemImage: "pencil")
            }
            .tint(.orange)
            .labelStyle(.iconOnly)
            .accessibilityLabel("Modifier ce tag")
        }
        .contextMenu {
            Button {
                renameItem = TagRenameItem(tag: tag)
            } label: {
                Label("Renommer", systemImage: "pencil")
            }

            Button(role: .destructive) {
                tagToDelete = tag
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }
}

/// Petite pastille de tag avec bouton de suppression, façon "Uncategorized" des apps Discogs.
struct TagPill: View {
    let tag: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.footnote.weight(.medium))
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.inlineIcon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retirer le tag \(tag)")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.tagBackground, in: Capsule())
        .foregroundStyle(Color.tagForeground)
    }
}

/// Layout fluide (wrap) pour disposer les pastilles de tags sur plusieurs lignes si besoin.
/// `nonisolated` : calcul purement géométrique, que SwiftUI peut mener hors du fil principal
/// (voir `AutoScrollTextWidthKey`).
nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
