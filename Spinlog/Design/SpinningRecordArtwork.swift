import SwiftUI

/// Jaquette posée devant un disque noir qui dépasse à moitié de sa pochette : l'étiquette centrale
/// du disque (le centre de la jaquette, en rond) tourne comme un 33 tours sur une platine, tandis
/// que la pochette reste entière et fixe — aucune troncature de la jaquette, contrairement à un
/// recadrage circulaire. Les sillons et le reflet ne tournent pas (sur un vrai disque, le reflet de
/// la lumière reste fixe), seule l'étiquette matérialise la rotation. Décoratif : masqué à VoiceOver.
struct SpinningRecordArtwork: View {
    let coverURL: String?
    /// Tours par minute : 33⅓ pour un 33 tours.
    var rpm: Double = RecordSpin.rpm33

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    private static let sleeveSize: CGFloat = 190
    private static let discDiameter: CGFloat = 180
    /// Part du disque qui dépasse de la pochette (le reste est caché derrière elle).
    private static let discReveal: CGFloat = 0.65
    private static let labelRatio: CGFloat = 0.38

    /// Abscisse (depuis le bord gauche de la pochette) du bord gauche du disque.
    private static var discOffsetFromSleeveLeading: CGFloat {
        sleeveSize - discDiameter * (1 - discReveal)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            disc
                .offset(x: Self.discOffsetFromSleeveLeading)

            AsyncCoverImage(url: coverURL, cornerRadius: 12, targetSize: Self.sleeveSize)
                .frame(width: Self.sleeveSize, height: Self.sleeveSize)
                .shadow(color: .black.opacity(0.30), radius: 10, x: 4, y: 4)
        }
        .frame(width: Self.discOffsetFromSleeveLeading + Self.discDiameter, height: Self.sleeveSize, alignment: .leading)
        .accessibilityHidden(true)
        .onAppear(perform: startSpinning)
    }

    // MARK: - Disque

    private var disc: some View {
        let labelSize = Self.discDiameter * Self.labelRatio
        return ZStack {
            // Vinyle : noir légèrement dégradé, ombré (statique : l'ombre n'est pas recalculée à
            // chaque image de la rotation).
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.05)], center: .center, startRadius: 0, endRadius: Self.discDiameter / 2))
                .shadow(color: .black.opacity(0.35), radius: 8, x: 2, y: 3)

            // Sillons, fixes.
            ForEach(0..<9, id: \.self) { index in
                let radius = Self.discDiameter / 2 * (0.46 + CGFloat(index) * 0.06)
                Circle()
                    .strokeBorder(Color.white.opacity(index.isMultiple(of: 3) ? 0.09 : 0.05), lineWidth: 0.6)
                    .frame(width: radius * 2, height: radius * 2)
            }

            // Reflet de la lumière, fixe lui aussi.
            Circle()
                .fill(AngularGradient(
                    colors: [.clear, .white.opacity(0.16), .clear, .clear, .white.opacity(0.10), .clear],
                    center: .center
                ))
                .blendMode(.plusLighter)

            // Étiquette : la seule partie qui tourne.
            label(size: labelSize)
                .rotationEffect(.degrees(rotation))

            // Trou central.
            Circle()
                .fill(Color(white: 0.04))
                .frame(width: labelSize * 0.16, height: labelSize * 0.16)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
        }
        .frame(width: Self.discDiameter, height: Self.discDiameter)
    }

    private func label(size: CGFloat) -> some View {
        AsyncCoverImage(url: coverURL, cornerRadius: 0, showsBorder: false, targetSize: size)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Rotation

    /// Animation linéaire répétée, portée par le moteur de rendu : pas de recalcul SwiftUI à chaque
    /// image. Désactivée avec « Réduire les animations » (disque fixe).
    private func startSpinning() {
        guard !reduceMotion, rotation == 0 else { return }
        let period = 60.0 / rpm
        withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

#Preview("Disque qui tourne") {
    SpinningRecordArtwork(coverURL: nil)
        .padding()
        .background(Color.appBackground)
}
