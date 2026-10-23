import SwiftUI

/// Repère de visée du scan par lot : quatre coins qui « respirent » tant que la caméra cherche un
/// code. Purement décoratif (la reconnaissance couvre tout le champ) ; immobile avec « Réduire les
/// animations ».
struct BatchScanViewfinder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        ScanCorners()
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 230, height: 150)
            .scaleEffect(isExpanded ? 1.05 : 0.97)
            .opacity(isExpanded ? 0.5 : 0.9)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: isExpanded
            )
            .onAppear { isExpanded = true }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Quatre coins d'un cadre de visée.
private nonisolated struct ScanCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.22
        var path = Path()
        for (corner, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
            (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)
        ] {
            path.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
        }
        return path
    }
}

/// Éclair vert sur le pourtour de l'écran quand un code est reconnu. Chaque incrément de `trigger`
/// rejoue l'éclair ; sans animations, un fondu bref remplace le mouvement.
struct BatchScanRecognitionFlash: View {
    let trigger: Int

    @State private var intensity = 0.0

    var body: some View {
        Rectangle()
            .strokeBorder(
                LinearGradient(colors: [.green.opacity(0.95), .green.opacity(0.35)], startPoint: .top, endPoint: .bottom),
                lineWidth: 10
            )
            .opacity(intensity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) {
                intensity = 1
                withAnimation(.easeOut(duration: 0.55)) { intensity = 0 }
            }
    }
}

/// Pastille « disque reconnu » : la pochette et le titre du pressage retenu, qui s'affichent un
/// instant au-dessus du compteur avant de « glisser » dedans.
struct BatchScanFoundChip: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 10) {
            AsyncCoverImage(url: result.thumb ?? result.coverImage, cornerRadius: 6, targetSize: 36)
                .frame(width: 36, height: 36)
            Text(result.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(.black.opacity(0.7), in: Capsule())
        .frame(maxWidth: 320)
        .accessibilityElement(children: .combine)
    }
}
