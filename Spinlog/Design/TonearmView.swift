import SwiftUI

/// Bras de lecture d'une platine, dessiné de profil sur la droite du disque : au repos il pend à côté
/// du vinyle, en lecture il pivote et se pose sur les sillons. Le pivot est en haut de la vue. Purement
/// décoratif (masqué à VoiceOver) ; sans « Réduire les animations », il change de position sans glisser.
struct TonearmView: View {
    /// Vrai : le bras est posé sur le disque (écoute en cours).
    let isDown: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 20
    static let armLength: CGFloat = 92
    /// Hauteur de la vue : contrepoids, pivot, bras et tête de lecture.
    static var height: CGFloat { armLength + 32 }
    /// Distance du pivot au haut de la vue.
    private static let pivotY: CGFloat = 15
    /// Rotation (sens horaire) qui amène la tête au début du disque, sur les premiers sillons près du
    /// bord (à ~77 pt du centre pour un disque de 90 pt de rayon) : un angle plus grand la ferait
    /// glisser vers l'étiquette, comme en fin de face.
    static let playAngle: Double = 15

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Contrepoids, derrière le pivot.
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.16)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 9, height: 13)
                .offset(x: 5.5, y: 0)

            // Tube du bras.
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.62)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 3.5, height: Self.armLength)
                .offset(x: 8.25, y: Self.pivotY)

            // Tête de lecture : coque sombre inclinée et pointe.
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 9, height: 15)
                Circle()
                    .fill(Color(white: 0.85))
                    .frame(width: 2.5, height: 2.5)
            }
            .rotationEffect(.degrees(-14))
            .offset(x: 5.5, y: Self.pivotY + Self.armLength - 5)

            // Pivot : embase métallique et axe.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.92), Color(white: 0.48)], center: .topLeading, startRadius: 0, endRadius: 14))
                .frame(width: 17, height: 17)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.6))
                .overlay(Circle().fill(Color(white: 0.2)).frame(width: 5, height: 5))
                .offset(x: 1.5, y: Self.pivotY - 8.5)
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .rotationEffect(
            .degrees(isDown ? Self.playAngle : 0),
            anchor: UnitPoint(x: 0.5, y: Self.pivotY / Self.height)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, x: 3, y: 4)
        .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.78), value: isDown)
        .accessibilityHidden(true)
    }
}

#Preview("Bras de lecture") {
    HStack(spacing: 40) {
        TonearmView(isDown: false)
        TonearmView(isDown: true)
    }
    .padding(40)
    .background(Color.appBackground)
}
