import SwiftUI

/// Cassette audio dessinée de face, pour l'écoute sur platine d'un album sorti en cassette : coque en
/// plastique teintée de la couleur moyenne de la pochette (biseau, reflet, ombre portée), étiquette en
/// papier avec face « A », lignes d'écriture et titre à la main, fenêtre vitrée avec deux bobines
/// métalliques à moyeu dentelé qui tournent et un ruban qui passe peu à peu d'une bobine à l'autre (la
/// bobine pleine se vide, l'autre grossit), et le bas de coque en trapèze avec ses trous de guidage et ses
/// vis en croix : les détails qui font reconnaître une cassette au premier regard. Le titre et
/// l'artiste sont écrits à la main sur l'étiquette. Décoratif. Le mouvement vient de `angle` : sans
/// « Réduire les animations », l'appelant le laisse à zéro et tout est fixe.
///
/// Trois couches : la coque (fixe), les bobines (seule couche qui dépend de `angle`, donc seule
/// redessinée à chaque image) et le reflet de la vitre (fixe, par-dessus les bobines).
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

    fileprivate static let tapeColor = Color(red: 0.40, green: 0.25, blue: 0.15)

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
            CassetteChassis(top: shell.top, bottom: shell.bottom, width: width, title: title, artist: artist)
            CassetteReels(width: width, angle: angle)
            CassetteGlass(width: width)
        }
        .frame(width: width, height: width * 0.64)
    }
}

// MARK: - Coque, étiquette, bas de coque, vis (fixes)

private struct CassetteChassis: View {
    let top: Color
    let bottom: Color
    let width: CGFloat
    let title: String?
    let artist: String?

    private var height: CGFloat { width * 0.64 }
    private var corner: CGFloat { width * 0.055 }

    var body: some View {
        ZStack {
            shellBody
            label
            windowWell
            bottomPanel
            screws
        }
        .frame(width: width, height: height)
    }

    // MARK: Coque

    /// Plastique : dégradé vertical, biseau clair en haut à gauche et sombre en bas à droite, liseré
    /// intérieur en creux, reflet diagonal et ombre portée.
    private var shellBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.40), radius: 9, x: 2, y: 5)

            // Reflet du plastique : bande claire en biais, plus intense en haut à gauche.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.04), .clear], startPoint: .topLeading, endPoint: .center))

            // Ombre au pied de la coque : arrondit visuellement le volume.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [.clear, .black.opacity(0.22)], startPoint: .center, endPoint: .bottom))

            // Biseau : bord lumineux d'un côté, sombre de l'autre.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05), .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.6
                )

            // Liseré en creux, un peu en retrait du bord.
            RoundedRectangle(cornerRadius: corner * 0.7, style: .continuous)
                .strokeBorder(Color.black.opacity(0.16), lineWidth: 0.8)
                .padding(width * 0.018)
        }
    }

    // MARK: Étiquette

    private var label: some View {
        let labelWidth = width * 0.88
        let labelHeight = height * 0.42
        return RoundedRectangle(cornerRadius: width * 0.02, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.89)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(LinearGradient(colors: [top, top.opacity(0.78)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: height * 0.07)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: width * 0.02, topTrailingRadius: width * 0.02))
            }
            .overlay { ruledLines(labelHeight: labelHeight) }
            .overlay { labelContent }
            .overlay(alignment: .topTrailing) { sideBadge }
            // Papier : léger relief (ombre en haut, liseré fin).
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.02, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.6)
            )
            .frame(width: labelWidth, height: labelHeight)
            .shadow(color: .black.opacity(0.28), radius: 1.5, x: 0, y: 1)
            .offset(y: -height * 0.26)
    }

    /// Lignes d'écriture bleu pâle, sous le bandeau de couleur.
    private func ruledLines(labelHeight: CGFloat) -> some View {
        VStack(spacing: labelHeight * 0.17) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle().fill(Color(red: 0.55, green: 0.65, blue: 0.85).opacity(0.35)).frame(height: 0.7)
            }
        }
        .padding(.horizontal, width * 0.03)
        .padding(.top, labelHeight * 0.38)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Face « A » de la cassette, en rond dans le coin de l'étiquette.
    private var sideBadge: some View {
        Text(verbatim: "A")
            .font(.system(size: height * 0.11, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(white: 0.30))
            .frame(width: height * 0.15, height: height * 0.15)
            .background(Circle().fill(Color.white.opacity(0.85)))
            .overlay(Circle().strokeBorder(Color(white: 0.30), lineWidth: 0.8))
            .padding(.top, height * 0.085)
            .padding(.trailing, width * 0.03)
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

    // MARK: Fenêtre (cadre et fond)

    /// Cadre en retrait et fond sombre de la fenêtre ; les bobines se dessinent par-dessus (couche suivante).
    private var windowWell: some View {
        let windowWidth = width * 0.70
        let windowHeight = height * 0.30
        return ZStack {
            RoundedRectangle(cornerRadius: windowHeight * 0.5, style: .continuous)
                .fill(LinearGradient(colors: [Color.black.opacity(0.80), Color.black.opacity(0.58)], startPoint: .top, endPoint: .bottom))
            // Cadre : ombre portée à l'intérieur en haut, lumière en bas (la vitre est en creux).
            RoundedRectangle(cornerRadius: windowHeight * 0.5, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.65), .white.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.8
                )
        }
        .frame(width: windowWidth, height: windowHeight)
        .offset(y: height * 0.12)
    }

    // MARK: Bas de coque

    /// Trapèze du bas de la cassette, en retrait : deux trous de guidage, deux ouvertures pour la tête
    /// de lecture et le galet.
    private var bottomPanel: some View {
        let panelWidth = width * 0.66
        let panelHeight = height * 0.20
        return ZStack {
            CassetteBottomShape()
                .fill(LinearGradient(colors: [.black.opacity(0.30), .black.opacity(0.46)], startPoint: .top, endPoint: .bottom))
            CassetteBottomShape()
                .stroke(Color.white.opacity(0.20), lineWidth: 0.8)

            HStack(spacing: panelWidth * 0.06) {
                guideHole
                cutout
                cutout
                guideHole
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .offset(y: height * 0.395)
    }

    private var guideHole: some View {
        Circle()
            .fill(Color.black.opacity(0.78))
            .frame(width: width * 0.052, height: width * 0.052)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.7))
    }

    private var cutout: some View {
        RoundedRectangle(cornerRadius: width * 0.008, style: .continuous)
            .fill(Color.black.opacity(0.70))
            .frame(width: width * 0.05, height: height * 0.075)
            .overlay(RoundedRectangle(cornerRadius: width * 0.008, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.6))
    }

    // MARK: Vis

    /// Quatre vis à tête fendue en croix, aux coins.
    private var screws: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                // La rotation se pose avant le décalage : après, elle ferait tourner la vis autour du
                // centre de la cassette et la sortirait de son coin.
                screw
                    .rotationEffect(.degrees(Double(index) * 37))
                    .offset(
                        x: (index.isMultiple(of: 2) ? -1 : 1) * width * 0.445,
                        y: (index < 2 ? -1 : 1) * height * 0.425
                    )
            }
        }
    }

    private var screw: some View {
        let size = width * 0.036
        return ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.82), Color(white: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Capsule().fill(Color.black.opacity(0.55)).frame(width: size * 0.78, height: size * 0.14)
            Capsule().fill(Color.black.opacity(0.55)).frame(width: size * 0.14, height: size * 0.78)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
    }
}

// MARK: - Bobines et ruban (seule couche animée)

private struct CassetteReels: View {
    let width: CGFloat
    let angle: Double

    private var height: CGFloat { width * 0.64 }
    private var tapeProgress: Double { CassetteView.tapeProgress(forAngle: angle) }

    var body: some View {
        let windowWidth = width * 0.70
        let windowHeight = height * 0.30
        let minRadius = height * 0.07
        let maxRadius = height * 0.145
        let leftRadius = maxRadius - (maxRadius - minRadius) * tapeProgress
        let rightRadius = minRadius + (maxRadius - minRadius) * tapeProgress
        let reelOffset = width * 0.19

        return ZStack {
            // Ruban tendu entre le bas des deux bobines.
            TapeRun(progress: tapeProgress, minRadius: minRadius, maxRadius: maxRadius, reelOffset: reelOffset)
                .stroke(CassetteView.tapeColor, lineWidth: 1.4)

            tapePack(radius: leftRadius).offset(x: -reelOffset)
            tapePack(radius: rightRadius).offset(x: reelOffset)
            hub.offset(x: -reelOffset)
            hub.offset(x: reelOffset)
        }
        .frame(width: windowWidth, height: windowHeight)
        .clipShape(RoundedRectangle(cornerRadius: windowHeight * 0.5, style: .continuous))
        .offset(y: height * 0.12)
    }

    /// Pelote de ruban : dégradé radial (plus sombre au centre) et fins anneaux, pour qu'on lise des
    /// spires et non un disque uni.
    private func tapePack(radius: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [CassetteView.tapeColor.opacity(0.85), CassetteView.tapeColor, Color(red: 0.50, green: 0.33, blue: 0.20)],
                center: .center, startRadius: radius * 0.2, endRadius: radius
            ))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.22), lineWidth: 0.6).padding(radius * 0.22))
            .frame(width: radius * 2, height: radius * 2)
    }

    /// Moyeu métallique à six dents : c'est lui qui tourne.
    private var hub: some View {
        let radius = height * 0.062
        return ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing))
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(Color(white: 0.20))
                    .frame(width: radius * 0.34, height: radius * 0.78)
                    .offset(y: -radius * 0.50)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
            Circle().fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: radius * 0.5, height: radius * 0.5)
            Circle().fill(Color.black.opacity(0.55)).frame(width: radius * 0.16, height: radius * 0.16)
        }
        .frame(width: radius * 2, height: radius * 2)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.45), radius: 1.2, x: 0.5, y: 1)
        .rotationEffect(.degrees(angle))
    }
}

// MARK: - Vitre (fixe, par-dessus les bobines)

private struct CassetteGlass: View {
    let width: CGFloat
    private var height: CGFloat { width * 0.64 }

    var body: some View {
        let windowWidth = width * 0.70
        let windowHeight = height * 0.30
        RoundedRectangle(cornerRadius: windowHeight * 0.5, style: .continuous)
            .fill(LinearGradient(
                colors: [.white.opacity(0.24), .white.opacity(0.04), .clear],
                startPoint: .topLeading, endPoint: .center
            ))
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: windowWidth * 0.62, height: 1.2)
                    .padding(.top, windowHeight * 0.10)
            }
            .frame(width: windowWidth, height: windowHeight)
            .offset(y: height * 0.12)
            .allowsHitTesting(false)
    }
}

// MARK: - Formes

/// Trapèze du bas de coque : un peu plus étroit en bas qu'en haut, aux coins légèrement arrondis.
private nonisolated struct CassetteBottomShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.07
        let radius = rect.height * 0.18
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.closeSubpath()
        return path
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

#Preview("Cassette, coque grise") {
    CassetteView(tint: nil, width: 260, title: "Placebo", artist: "Placebo", angle: 400)
        .padding(40)
        .background(Color.appBackground)
}
