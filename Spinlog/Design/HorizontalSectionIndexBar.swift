import SwiftUI

/// Barre de navigation rapide horizontale (Scrubber alphabétique / chronologique)
/// positionnée en bas du mode Carrousel pour naviguer instantanément entre les sections.
struct HorizontalSectionIndexBar: View {
    let entries: [(token: String, sectionKey: String)]
    /// Jeton de la section actuellement affichée au centre du carrousel : entoure le jeton
    /// correspondant d'une bulle, pour se repérer dans le défilement sans avoir à toucher la
    /// barre — même principe que `SectionIndexBar` (barre verticale, listes et mosaïques).
    var currentToken: String? = nil
    let onSelect: (String) -> Void

    @State private var dragToken: String?
    @State private var touchX: CGFloat = 0
    @State private var isDragging: Bool = false

    private var activeToken: String? {
        dragToken ?? currentToken
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Largeur fixe (20pt) tant qu'elle tient dans la largeur disponible ; sinon
            // compressée pour que la barre entière reste toujours contenue dans l'écran — sans
            // ça, un tri avec beaucoup de jetons distincts (A-Z complet) dépassait la largeur de
            // l'écran, chaque jeton gardant son minimum de 20pt quel que soit leur nombre.
            let itemWidth = entries.isEmpty ? 20 : min(20, width / CGFloat(entries.count))
            // Quand les jetons tiennent à 20 pt chacun, la rangée est plus étroite que la barre et se
            // centre : le doigt doit être mesuré dans CETTE rangée (décalage `rowInset`), pas dans la
            // largeur entière de la barre — sinon la lettre choisie dérivait de plus en plus par
            // rapport au doigt en s'éloignant du centre.
            let rowWidth = itemWidth * CGFloat(entries.count)
            let rowInset = max((width - rowWidth) / 2, 0)

            HStack(spacing: 0) {
                ForEach(entries, id: \.token) { entry in
                    let isSelected = activeToken == entry.token
                    // Pendant un glissé, la grosse bulle flottante (ci-dessous) fait déjà office
                    // d'indicateur : la bulle de position au repos ne s'affiche pas en même temps.
                    let isCurrent = !isDragging && currentToken == entry.token
                    Text(railLabel(for: entry.token))
                        // Taille fixe à 11pt (plancher de lisibilité) : `.minimumScaleFactor(0.5)`
                        // juste en dessous gère déjà la compression en cas de dépassement réel,
                        // rendant inutile — et contre-productif pour la lisibilité — un palier
                        // supplémentaire qui retombait à 9pt dès que la liste avait beaucoup de
                        // lettres, c'est-à-dire précisément quand ce repère compte le plus.
                        .font(.system(size: 11, weight: isSelected ? .black : .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(isCurrent ? .white : (isSelected ? Color.spinlogPink : Color.secondary))
                        .frame(width: itemWidth, height: 20)
                        .background {
                            if isCurrent {
                                Circle().fill(Color.spinlogPurple)
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        touchX = value.location.x
                        select(at: value.location.x - rowInset, in: rowWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragToken = nil
                    }
            )
            .overlay(alignment: .top) {
                if isDragging, let displayToken = dragToken {
                    let bubbleX = min(max(touchX - width / 2, -width / 2 + 28), width / 2 - 28)
                    Text(displayToken)
                        .font(.system(size: displayToken.count > 2 ? 18 : 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.buttonPinkTop, Color.buttonPinkBottom],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.buttonPinkBottom.opacity(0.40), radius: 8, y: 3)
                        )
                        .offset(x: bubbleX, y: -56)
                        .motionTransition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragToken)
            // Anime aussi la position de la bulle : sans ça, son déplacement suivait le doigt au
            // repère près (même fréquence que le glissé), ce qui donnait un mouvement saccadé
            // plutôt que fluide d'un jeton à l'autre.
            .animation(.easeOut(duration: 0.12), value: touchX)
        }
        .frame(height: 28)
        .padding(.horizontal, 10)
        .sectionIndexAccessibility(entries: entries, currentToken: currentToken, onSelect: onSelect)
    }

    private func railLabel(for token: String) -> String {
        if token.count == 4, let _ = Int(token) {
            return String(token.suffix(2))
        }
        return token
    }

    private func select(at x: CGFloat, in width: CGFloat) {
        guard !entries.isEmpty, width > 0 else { return }
        let clampedX = min(max(x, 0), width - 0.01)
        let index = Int(clampedX / width * CGFloat(entries.count))
        let boundedIndex = min(max(index, 0), entries.count - 1)
        let entry = entries[boundedIndex]
        if entry.token != dragToken {
            dragToken = entry.token
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
            onSelect(entry.sectionKey)
        }
    }
}
