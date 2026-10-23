import SwiftUI

/// Jaquette posée devant un disque noir qui dépasse à moitié de sa pochette : l'étiquette centrale
/// du disque (le centre de la jaquette, en rond) tourne comme un 33 tours sur une platine, tandis
/// que la pochette reste entière et fixe — aucune troncature de la jaquette, contrairement à un
/// recadrage circulaire. Les sillons et le reflet ne tournent pas (sur un vrai disque, le reflet de
/// la lumière reste fixe), seule l'étiquette matérialise la rotation. Décoratif : masqué à VoiceOver.
///
/// Pour un CD, même principe — la pochette entière devant le disque — mais le disque est argenté,
/// sans rien d'imprimé dessus (un CD n'a pas de pochette collée) : c'est son reflet irisé qui tourne.
/// Pour une cassette, c'est la cassette (voir `CassetteView`), teintée de la couleur de la pochette,
/// qui dépasse de derrière la pochette, restée carrée et entière.
struct SpinningRecordArtwork: View {
    let coverURL: String?
    var media: PhysicalMedia = .vinyl
    /// Titre et artiste, écrits sur l'étiquette d'une cassette (ignorés pour les autres supports).
    var title: String? = nil
    var artist: String? = nil
    /// Tours par minute : 33⅓ pour un 33 tours.
    var rpm: Double = RecordSpin.rpm33

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    /// Couleur moyenne de la pochette, qui teinte la coque d'une cassette.
    @State private var coverTint: UIColor?

    private static let sleeveSize: CGFloat = 190
    /// Part du disque qui dépasse de la pochette (le reste est caché derrière elle).
    private static let discReveal: CGFloat = 0.65
    private static let labelRatio: CGFloat = 0.38

    /// Diamètre du disque : un CD est plus petit qu'un 33 tours, à la même échelle que la pochette.
    private var discDiameter: CGFloat {
        switch media {
        case .vinyl: 180
        case .cd: 150
        case .cassette: 170
        }
    }

    /// Largeur occupée par le support derrière la pochette (la cassette est un rectangle : sa largeur
    /// est sa « dimension », comme le diamètre d'un disque).
    private var mediaWidth: CGFloat { discDiameter }

    /// Abscisse (depuis le bord gauche de la pochette) du bord gauche du support.
    private var discOffsetFromSleeveLeading: CGFloat {
        Self.sleeveSize - mediaWidth * (1 - Self.discReveal)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                switch media {
                case .vinyl: disc
                case .cd: compactDisc
                case .cassette: CassetteView(tint: coverTint, width: mediaWidth, title: title, artist: artist)
                }
            }
            .offset(x: discOffsetFromSleeveLeading)

            AsyncCoverImage(
                url: coverURL,
                cornerRadius: 12,
                targetSize: Self.sleeveSize,
                onAverageColorLoaded: { color in
                    withAnimation(.easeInOut(duration: 0.4)) { coverTint = color }
                }
            )
            .frame(width: Self.sleeveSize, height: Self.sleeveSize)
            .shadow(color: .black.opacity(0.30), radius: 10, x: 4, y: 4)
        }
        .frame(width: discOffsetFromSleeveLeading + mediaWidth, height: Self.sleeveSize, alignment: .leading)
        .accessibilityHidden(true)
        .onAppear {
            // Couleur déjà connue (fiche ouverte avant) : la coque est teintée dès la première image.
            if coverTint == nil, let coverURL {
                coverTint = ReleaseColorCache.shared.color(forURL: coverURL)
            }
            startSpinning()
        }
    }

    // MARK: - Disque

    private var disc: some View {
        let labelSize = discDiameter * Self.labelRatio
        return ZStack {
            // Vinyle : noir légèrement dégradé, ombré (statique : l'ombre n'est pas recalculée à
            // chaque image de la rotation).
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.05)], center: .center, startRadius: 0, endRadius: discDiameter / 2))
                .shadow(color: .black.opacity(0.35), radius: 8, x: 2, y: 3)

            // Sillons, fixes.
            ForEach(0..<9, id: \.self) { index in
                let radius = discDiameter / 2 * (0.46 + CGFloat(index) * 0.06)
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
        .frame(width: discDiameter, height: discDiameter)
    }

    // MARK: - CD

    /// Disque argenté : un reflet irisé (dégradé angulaire) qui tourne, une zone de lecture plus
    /// sombre, un moyeu translucide et un trou central réellement transparent. Rien n'est imprimé dessus.
    private var compactDisc: some View {
        let diameter = discDiameter
        return ZStack {
            // Corps : l'irisation tourne, l'ombre et les anneaux restent fixes.
            Circle()
                .fill(AngularGradient(
                    colors: [
                        Color(white: 0.93), Color(red: 0.78, green: 0.90, blue: 0.96),
                        Color(white: 0.80), Color(red: 0.96, green: 0.80, blue: 0.90),
                        Color(white: 0.94), Color(red: 0.98, green: 0.94, blue: 0.76),
                        Color(white: 0.78), Color(red: 0.80, green: 0.96, blue: 0.86),
                        Color(white: 0.93)
                    ],
                    center: .center
                ))
                .rotationEffect(.degrees(rotation))
                .shadow(color: .black.opacity(0.30), radius: 8, x: 2, y: 3)

            // Zone de lecture : fin anneau plus sombre entre le moyeu et le bord.
            Circle()
                .strokeBorder(Color.black.opacity(0.10), lineWidth: diameter * 0.015)
                .frame(width: diameter * 0.86, height: diameter * 0.86)
            Circle()
                .strokeBorder(Color.black.opacity(0.08), lineWidth: diameter * 0.01)
                .frame(width: diameter * 0.40, height: diameter * 0.40)

            // Moyeu translucide.
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: diameter * 0.30, height: diameter * 0.30)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.8))

            // Bord extérieur.
            Circle()
                .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)

            // Trou central : percé dans le disque (on voit ce qu'il y a derrière).
            Circle()
                .fill(Color.black)
                .frame(width: diameter * 0.10, height: diameter * 0.10)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: diameter, height: diameter)
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

#Preview("Cassette qui tourne") {
    SpinningRecordArtwork(coverURL: nil, media: .cassette, title: "Placebo", artist: "Placebo")
        .padding()
        .background(Color.appBackground)
}

#Preview("CD qui tourne") {
    SpinningRecordArtwork(coverURL: nil, media: .cd)
        .padding()
        .background(Color.appBackground)
}
