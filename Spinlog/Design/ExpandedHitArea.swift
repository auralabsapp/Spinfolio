import SwiftUI

extension View {
    /// Agrandit la zone qui réagit au toucher d'un petit bouton jusqu'à `minimumSide` points
    /// (44 pt recommandés par Apple), sans changer ni son dessin ni la mise en page : le
    /// rembourrage ajouté autour de la forme de toucher est aussitôt retiré.
    /// - Parameter visibleSide: côté actuel du bouton (le plus petit si rectangulaire).
    func expandedHitArea(visibleSide: CGFloat, minimumSide: CGFloat = 44) -> some View {
        let inset = max(0, (minimumSide - visibleSide) / 2)
        return padding(inset)
            .contentShape(Rectangle())
            .padding(-inset)
    }
}
