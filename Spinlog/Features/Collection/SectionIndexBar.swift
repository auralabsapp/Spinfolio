import SwiftUI

/// Barre de navigation rapide sur le bord droit (comme Contacts) : lettres pour un tri
/// alphabétique, années sur 2 chiffres pour un tri par date d'ajout. Glisser le doigt le
/// long de la barre fait défiler la liste jusqu'à la section correspondante.
struct SectionIndexBar: View {
    let entries: [(token: String, sectionKey: String)]
    /// Jeton de la section actuellement épinglée en haut de la liste (voir
    /// `SectionScrollTracking`) : entoure la lettre correspondante d'une bulle, pour se repérer
    /// dans le défilement sans avoir à toucher la barre.
    var currentToken: String? = nil
    let onSelect: (String) -> Void

    @State private var activeToken: String?
    /// Cran haptique à chaque changement de lettre pendant le glissé, comme `HorizontalSectionIndexBar`.
    @State private var selectionFeedback = UISelectionFeedbackGenerator()
    /// Hauteur disponible figée à la première mesure. Sous un grand titre de navigation, la zone
    /// disponible sous la barre s'agrandit progressivement pendant le défilement (le grand titre
    /// se réduit) : sans ce gel, la barre se redessinait à chaque image sur cette zone changeante
    /// et semblait s'étirer/remonter au défilement au lieu de rester fixe. Le point d'appel ancre
    /// la barre en bas (`.overlay(alignment: .bottomTrailing)`), seul bord qui reste stable au
    /// défilement ; `centeringOffset` la repositionne ensuite à partir de cette valeur figée
    /// (et de `regionBottomFromScreenTop`), sans jamais dépendre de la zone de sécurité dynamique.
    @State private var measuredHeight: CGFloat?
    /// Distance figée, depuis le haut de l'écran, jusqu'au bas de la zone disponible — pour
    /// centrer la barre par rapport à la hauteur de l'écran entière (voir `centeringOffset`),
    /// pas seulement par rapport à cette zone (qui exclut la barre d'onglets, par exemple).
    @State private var regionBottomFromScreenTop: CGFloat?
    /// Position verticale du doigt pendant le glissé, pour aligner l'aperçu en grand dessus
    /// (voir le point d'appel plus bas) plutôt que de le laisser fixe au centre de la barre.
    @State private var touchY: CGFloat = 0

    /// Hauteur maximale par jeton : au-delà, un tri à peu de valeurs distinctes (Note, Support…)
    /// étalait ses quelques jetons sur toute la hauteur disponible, avec de grands vides entre eux.
    /// La barre se condense plutôt, sans dépasser l'espace disponible (`measuredHeight`).
    private static let maxRowHeight: CGFloat = 20

    /// Hauteur réellement occupée par la barre une fois l'espace disponible connu.
    private var barHeight: CGFloat? {
        guard let measuredHeight else { return nil }
        return min(measuredHeight, CGFloat(entries.count) * Self.maxRowHeight)
    }

    /// Décalage qui centre verticalement la barre condensée par rapport à la hauteur de l'écran
    /// entière, tout en gardant l'ancrage en bas du point d'appel
    /// (`.overlay(alignment: .bottomTrailing)`) pour la stabilité pendant le défilement (voir
    /// `measuredHeight`) : ne dépend que de valeurs figées, jamais de la zone de sécurité
    /// dynamique sous le grand titre.
    private var centeringOffset: CGFloat {
        // `UIScreen.main` est dépréciée (iOS 26) : la scène connectée est le remplacement
        // recommandé par Apple pour retrouver les dimensions de l'écran.
        guard let regionBottomFromScreenTop, let barHeight,
              let screenHeight = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height
        else { return 0 }
        let currentCenterY = regionBottomFromScreenTop - barHeight / 2
        let desiredCenterY = screenHeight / 2
        return desiredCenterY - currentCenterY
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(entries, id: \.token) { entry in
                    // Pendant un glissé sur la barre, l'aperçu en grand (ci-dessous) fait déjà
                    // office d'indicateur : la pastille de position ne s'affiche qu'au repos.
                    let isCurrent = activeToken == nil && currentToken == entry.token
                    Text(railLabel(for: entry.token))
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        // Pas de réduction (elle descendait à 8,4 pt, sous le plancher de 11 pt) :
                        // les repères font au plus 2 caractères et tiennent dans la largeur.
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(
                            activeToken == entry.token ? Color.spinlogPink : (isCurrent ? .white : .secondary)
                        )
                        .frame(width: 20, height: 20)
                        .background {
                            if isCurrent {
                                Circle().fill(Color.spinlogPurple)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Moteur haptique préchauffé dès le doigt posé : le premier cran n'est pas en retard.
                        if activeToken == nil { selectionFeedback.prepare() }
                        touchY = value.location.y
                        select(at: value.location.y, in: geometry.size.height)
                    }
                    .onEnded { _ in
                        activeToken = nil
                    }
            )
            .onAppear {
                if measuredHeight == nil {
                    measuredHeight = geometry.size.height
                    regionBottomFromScreenTop = geometry.frame(in: .global).maxY
                }
            }
        }
        .frame(width: 22, height: barHeight)
        .overlay(alignment: .top) {
            if let activeToken {
                // Centrée sur la position du doigt plutôt que fixe au milieu de la barre, en
                // restant entièrement dans ses limites (bulle de 60pt de diamètre).
                let bubbleCenterY = min(max(touchY, 30), max((barHeight ?? 0) - 30, 30))
                Text(activeToken)
                    .font(.system(size: activeToken.count > 2 ? 22 : 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.buttonPinkTop, Color.buttonPinkBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .shadow(color: Color.buttonPinkBottom.opacity(0.35), radius: 8, y: 2)
                    )
                    .offset(x: -46, y: bubbleCenterY - 30)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .sectionIndexAccessibility(entries: entries, currentToken: currentToken, onSelect: onSelect)
        .animation(.easeOut(duration: 0.15), value: activeToken)
        // Anime aussi la position de l'aperçu en grand : sans ça, son déplacement suivait le
        // doigt au repère près (même fréquence que le glissé), ce qui donnait un mouvement saccadé
        // plutôt que fluide d'une lettre à l'autre.
        .animation(.easeOut(duration: 0.12), value: touchY)
        // Appliqué en dernier : la barre ET l'aperçu en grand (qui s'aligne sur elle ci-dessus)
        // sont ainsi décalés ensemble d'un seul bloc, sans quoi l'aperçu se positionnait avant ce
        // décalage et ne suivait plus le doigt une fois la barre recentrée.
        .offset(y: centeringOffset)
    }

    private func railLabel(for token: String) -> String {
        if token.count == 4, let _ = Int(token) {
            return String(token.suffix(2))
        }
        return token
    }

    private func select(at y: CGFloat, in height: CGFloat) {
        guard !entries.isEmpty, height > 0 else { return }
        let clampedY = min(max(y, 0), height - 0.01)
        let index = Int(clampedY / height * CGFloat(entries.count))
        let boundedIndex = min(max(index, 0), entries.count - 1)
        let entry = entries[boundedIndex]
        if entry.token != activeToken {
            activeToken = entry.token
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()
            onSelect(entry.sectionKey)
        }
    }
}

/// Accessibilité des barres de navigation rapide (`SectionIndexBar`, `HorizontalSectionIndexBar`) :
/// leur seul geste, un glissé du doigt, est inutilisable avec VoiceOver. La barre devient un
/// unique élément « ajustable » (comme l'index de Contacts) : VoiceOver annonce la section
/// affichée, et un balayage vertical passe à la section suivante ou précédente.
private struct SectionIndexAccessibility: ViewModifier {
    let entries: [(token: String, sectionKey: String)]
    let currentToken: String?
    let onSelect: (String) -> Void

    /// Section choisie via VoiceOver, en attendant que le défilement mette à jour `currentToken`
    /// (sans quoi deux balayages rapides repartiraient de la même section).
    @State private var pendingToken: String?

    private var displayedToken: String? {
        pendingToken ?? currentToken ?? entries.first?.token
    }

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Index des sections"))
            .accessibilityValue(Text(displayedToken ?? ""))
            .accessibilityHint(Text("Balaie vers le haut ou vers le bas pour changer de section."))
            .accessibilityAdjustableAction { direction in
                guard !entries.isEmpty else { return }
                let currentIndex = entries.firstIndex { $0.token == displayedToken } ?? 0
                let newIndex: Int
                switch direction {
                case .increment: newIndex = min(currentIndex + 1, entries.count - 1)
                case .decrement: newIndex = max(currentIndex - 1, 0)
                @unknown default: return
                }
                guard newIndex != currentIndex else { return }
                pendingToken = entries[newIndex].token
                onSelect(entries[newIndex].sectionKey)
            }
            .onChange(of: currentToken) { _, newValue in
                if newValue == pendingToken { pendingToken = nil }
            }
    }
}

extension View {
    func sectionIndexAccessibility(
        entries: [(token: String, sectionKey: String)],
        currentToken: String?,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        modifier(SectionIndexAccessibility(entries: entries, currentToken: currentToken, onSelect: onSelect))
    }
}
