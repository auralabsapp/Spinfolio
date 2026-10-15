import SwiftUI

/// Composant visuel représentant une pochette de vinyle avec son disque noir qui dépasse sur la droite.
/// Donne un rendu réaliste et immersif de vinyle physique pour le mode Carrousel.
struct VinylSleeveCover: View {
    let coverURL: String?
    var size: CGFloat = 240

    var body: some View {
        ZStack(alignment: .trailing) {
            // Disque vinyle noir peeking sur la droite
            vinylDisc
                .frame(width: size * 0.94, height: size * 0.94)
                .offset(x: size * 0.18)
                .shadow(color: .black.opacity(0.35), radius: 10, x: 6, y: 5)

            // Pochette d'album carrée
            AsyncCoverImage(url: coverURL, cornerRadius: 10, targetSize: size)
                .frame(width: size, height: size)
                // Ombre de contact (très proche) puis ombre d'ambiance flottante (large et
                // douce), même recette que les autres pochettes de l'app.
                .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        }
        .frame(width: size * 1.18, height: size)
    }

    private var vinylDisc: some View {
        ZStack {
            // Disque noir avec reflets
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.08),
                            Color(white: 0.18),
                            Color(white: 0.09),
                            Color(white: 0.22),
                            Color(white: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Sillons concentriques réalistes
            Circle().stroke(Color.white.opacity(0.04), lineWidth: 1).padding(size * 0.05)
            Circle().stroke(Color.white.opacity(0.05), lineWidth: 1).padding(size * 0.10)
            Circle().stroke(Color.white.opacity(0.04), lineWidth: 1).padding(size * 0.15)
            Circle().stroke(Color.white.opacity(0.05), lineWidth: 1).padding(size * 0.20)
            Circle().stroke(Color.white.opacity(0.04), lineWidth: 1).padding(size * 0.25)

            // Macaron central (étiquette)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.spinlogPink, Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.34, height: size * 0.34)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

            // Trou central
            Circle()
                .fill(Color.appBackground)
                .frame(width: size * 0.07, height: size * 0.07)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
        }
    }
}
