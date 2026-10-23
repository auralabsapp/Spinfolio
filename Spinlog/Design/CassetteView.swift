import SwiftUI

/// Cassette audio dessinée de face, pour l'écoute sur platine d'un album sorti en cassette : coque
/// teintée de la couleur moyenne de la pochette, étiquette vierge, fenêtre avec deux bobines à moyeu
/// dentelé qui tournent et un ruban qui passe peu à peu d'une bobine à l'autre (la bobine pleine se
/// vide, l'autre grossit) — le détail qui fait reconnaître une cassette au premier regard. Le titre et
/// l'artiste sont écrits à la main sur l'étiquette. Décoratif. Le mouvement vient de `angle` : sans
/// « Réduire les animations », l'appelant le laisse à zéro et tout est fixe.
struct CassetteView: View {
    /// Couleur moyenne de la pochette (ou `nil` : coque gris fumé).
    let tint: UIColor?
    var width: CGFloat = 170
    /// Titre et artiste « écrits au stylo » sur l'étiquette. Le texte court sur toute la largeur de
    /// l'étiquette : quand la pochette recouvre une partie de la cassette, le début des lignes
    /// disparaît derrière elle, comme sur une vraie cassette à moitié sortie de son boîtier.
    var title: String? = nil
    var artist: String? = nil

    /// Angle cumulé des bobines en degrés, fourni par le mouvement du support (voir `SpinProfile`) :
    /// les bobines tournent, ralentissent et s'arrêtent avec lui, et le ruban avance avec elles.
    var angle: Double = 0

    private var height: CGFloat { width * 0.64 }
    /// Vitesse de croisière des bobines (40 tours/minute, assez vif pour qu'on voie les dents tourner),
    /// en degrés par seconde.
    nonisolated static let reelDegreesPerSecond: Double = 240
    /// Durée, à vitesse de croisière, du passage du ruban d'une bobine à l'autre.
    private nonisolated static let tapeLegSeconds: Double = 90

    /// Répartition du ruban selon l'angle des bobines : 0,2 = presque tout à gauche, 0,85 = presque
    /// tout à droite, aller-retour d'une bobine à l'autre sans saut. Calculée à partir de l'angle (et
    /// non d'une animation propre) pour que le ruban s'arrête quand les bobines s'arrêtent.
    nonisolated static func tapeProgress(forAngle angle: Double) -> Double {
        let cycle = reelDegreesPerSecond * tapeLegSeconds * 2
        let phase = angle / cycle
        let fraction = phase - phase.rounded(.down)
        let triangle = 1 - abs(2 * fraction - 1)
        return 0.2 + 0.65 * triangle
    }

    private var tapeProgress: Double { Self.tapeProgress(forAngle: angle) }
    private static let tapeColor = Color(red: 0.40, green: 0.25, blue: 0.15)

    /// Teinte de la coque d'après la couleur de la pochette : saturation et luminosité bornées, pour
    /// que la coque reste lisible sur fond clair comme sombre, ni grise et terne ni fluo, que la
    /// pochette soit presque blanche ou presque noire. Règle pure, testée à part.
    nonisolated static func shellHSB(hue: Double, saturation: Double, brightness: Double)
        -> (hue: Double, saturation: Double, top: Double, bottom: Double) {
        let sat = min(max(saturation, 0.12), 0.85)
        let base = min(max(brightness, 0.38), 0.82)
        return (hue, sat, min(base + 0.10, 0.92), base * 0.62)
    }

    private var shellColors: (top: Color, bottom: Color) {
        guard let tint else { return (Color(white: 0.48), Color(white: 0.28)) }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        tint.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let shell = Self.shellHSB(hue: hue, saturation: saturation, brightness: brightness)
        return (
            Color(hue: shell.hue, saturation: shell.saturation, brightness: shell.top),
            Color(hue: shell.hue, saturation: shell.saturation, brightness: shell.bottom)
        )
    }

    var body: some View {
        let shell = shellColors
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
                .fill(LinearGradient(colors: [shell.top, shell.bottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.35), radius: 8, x: 2, y: 3)
            RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)

            label(accent: shell.top)
            window
            footer
            screws
        }
        .frame(width: width, height: height)
    }

    // MARK: - Étiquette (titre et artiste écrits au stylo, ou vierge sans texte)

    private func label(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: width * 0.02, style: .continuous)
            .fill(Color(white: 0.95))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(accent)
                    .frame(height: height * 0.07)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: width * 0.02, topTrailingRadius: width * 0.02))
            }
            .overlay { labelContent }
            .frame(width: width * 0.88, height: height * 0.42)
            .offset(y: -height * 0.26)
    }

    /// Écriture à la main (Noteworthy), au stylo bleu, légèrement penchée. Sans titre : deux lignes
    /// tracées, comme une étiquette vierge.
    @ViewBuilder
    private var labelContent: some View {
        if let title, !title.isEmpty {
            VStack(alignment: .leading, spacing: height * 0.012) {
                Text(title)
                    .font(.custom("Noteworthy-Bold", size: width * 0.074))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let artist, !artist.isEmpty {
                    Text(artist)
                        .font(.custom("Noteworthy-Light", size: width * 0.066))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .opacity(0.9)
                }
            }
            .foregroundStyle(Color(red: 0.13, green: 0.16, blue: 0.38))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, width * 0.04)
            .padding(.top, height * 0.072)
            .rotationEffect(.degrees(-1.5))
        } else {
            VStack(spacing: height * 0.045) {
                Capsule().fill(Color.black.opacity(0.10)).frame(height: 1)
                Capsule().fill(Color.black.opacity(0.10)).frame(height: 1)
            }
            .padding(.horizontal, width * 0.06)
            .padding(.top, height * 0.10)
        }
    }

    // MARK: - Fenêtre : bobines et ruban

    private var window: some View {
        let windowWidth = width * 0.70
        let windowHeight = height * 0.30
        let minRadius = height * 0.07
        let maxRadius = height * 0.145
        let leftRadius = maxRadius - (maxRadius - minRadius) * tapeProgress
        let rightRadius = minRadius + (maxRadius - minRadius) * tapeProgress
        let reelOffset = width * 0.19

        return ZStack {
            RoundedRectangle(cornerRadius: windowHeight * 0.5, style: .continuous)
                .fill(Color.black.opacity(0.62))

            // Ruban tendu entre le bas des deux bobines.
            TapeRun(progress: tapeProgress, minRadius: minRadius, maxRadius: maxRadius, reelOffset: reelOffset)
                .stroke(Self.tapeColor, lineWidth: 1.4)

            tapePack(radius: leftRadius).offset(x: -reelOffset)
            tapePack(radius: rightRadius).offset(x: reelOffset)
            hub.offset(x: -reelOffset)
            hub.offset(x: reelOffset)
        }
        .frame(width: windowWidth, height: windowHeight)
        .offset(y: height * 0.12)
    }

    private func tapePack(radius: CGFloat) -> some View {
        Circle()
            .fill(Self.tapeColor)
            .frame(width: radius * 2, height: radius * 2)
    }

    /// Moyeu blanc à six dents : c'est lui qui tourne.
    private var hub: some View {
        let radius = height * 0.062
        return ZStack {
            Circle().fill(Color(white: 0.92))
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(Color(white: 0.22))
                    .frame(width: radius * 0.34, height: radius * 0.78)
                    .offset(y: -radius * 0.50)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
            Circle().fill(Color(white: 0.92)).frame(width: radius * 0.5, height: radius * 0.5)
        }
        .frame(width: radius * 2, height: radius * 2)
        .rotationEffect(.degrees(angle))
    }

    // MARK: - Bas de coque et vis

    private var footer: some View {
        HStack(spacing: width * 0.18) {
            Circle().fill(Color.black.opacity(0.35)).frame(width: width * 0.035)
            Circle().fill(Color.black.opacity(0.35)).frame(width: width * 0.035)
        }
        .frame(width: width * 0.46, height: height * 0.12)
        .background(Color.black.opacity(0.28), in: UnevenRoundedRectangle(bottomLeadingRadius: width * 0.02, bottomTrailingRadius: width * 0.02))
        .offset(y: height * 0.44)
        .mask(Rectangle().frame(height: height * 0.12).offset(y: height * 0.44))
    }

    private var screws: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: width * 0.025)
                    .offset(
                        x: (index.isMultiple(of: 2) ? -1 : 1) * width * 0.45,
                        y: (index < 2 ? -1 : 1) * height * 0.43
                    )
            }
        }
    }
}

/// Ruban tendu entre le bas des deux bobines : sa pente suit la grosseur de chaque pelote (animable :
/// il se redresse et s'incline à mesure que le ruban passe d'une bobine à l'autre).
private nonisolated struct TapeRun: Shape {
    var progress: Double
    let minRadius: CGFloat
    let maxRadius: CGFloat
    let reelOffset: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let leftRadius = maxRadius - (maxRadius - minRadius) * progress
        let rightRadius = minRadius + (maxRadius - minRadius) * progress
        let centerY = rect.midY
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - reelOffset, y: centerY + leftRadius))
        path.addLine(to: CGPoint(x: rect.midX + reelOffset, y: centerY + rightRadius))
        return path
    }
}

#Preview("Cassette") {
    CassetteView(tint: UIColor(red: 0.85, green: 0.30, blue: 0.25, alpha: 1), title: "Legacy", artist: "Five Finger Death Punch")
        .padding(40)
        .background(Color.appBackground)
}
