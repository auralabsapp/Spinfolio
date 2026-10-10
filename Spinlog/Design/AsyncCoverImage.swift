import SwiftUI
import Kingfisher

/// Pochette carrée à coins arrondis, avec halo et état de chargement/erreur.
/// Utilise Kingfisher avec cache disque borné à 6h et headers Discogs.
struct AsyncCoverImage: View {
    let url: String?
    var cornerRadius: CGFloat = 12
    var showsBorder: Bool = true
    /// Taille d'affichage prévue (en points), quand elle est connue à l'avance. Permet à
    /// Kingfisher de décoder directement une miniature à cette résolution au lieu de mettre en
    /// cache/décoder l'image d'origine en pleine résolution puis de la sous-échantillonner à
    /// chaque rendu — coûteux pendant le défilement des listes/grilles. `nil` conserve le
    /// comportement précédent (taille inconnue à l'avance, ex: héros avec parallax).
    var targetSize: CGFloat? = nil
    var onAverageColorLoaded: ((UIColor) -> Void)? = nil

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        content
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let urlString = url, let imageURL = URL(string: urlString) {
            configuredImage(url: imageURL, urlString: urlString)
        } else {
            placeholder
        }
    }

    private func configuredImage(url: URL, urlString: String) -> some View {
        var image = KFImage(url)
            .placeholder {
                placeholder.overlay { ProgressView() }
            }
            .onSuccess { result in
                // Le calcul de la couleur moyenne (dessin CGContext de l'image entière dans un
                // contexte 1x1) s'exécutait directement ici, sur le thread principal — `onSuccess`
                // de KFImage y est livré pour pouvoir mettre à jour l'état SwiftUI. Pendant un
                // défilement avec beaucoup de nouvelles pochettes chargées d'un coup, ce dessin
                // répété contribuait aux saccades. Il ne sert qu'à préchauffer `ReleaseColorCache`
                // (dégradé de la fiche détail) : aucune UI ne dépend de sa mise à jour synchrone,
                // donc le dessin lui-même part sur une tâche détachée, et seule l'écriture dans le
                // cache (bon marché) revient sur l'acteur principal.
                let image = result.image
                Task.detached(priority: .utility) {
                    guard let avg = image.averageColor else { return }
                    await MainActor.run {
                        ReleaseColorCache.shared.register(color: avg, url: urlString)
                        onAverageColorLoaded?(avg)
                    }
                }
            }
            .fade(duration: 0.2)
        if let targetSize {
            let pixelSize = targetSize * displayScale
            image = image.downsampling(size: CGSize(width: pixelSize, height: pixelSize))
        }
        return image
            .resizable()
            .aspectRatio(1, contentMode: .fill)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "opticaldisc")
                    .font(.title2)
                    .foregroundStyle(Color.appSecondaryText)
            }
    }
}

extension UIImage {
    /// Calcule la couleur moyenne de l'image (format RGBA) via un contexte bitmap 1x1 ultra-rapide.
    /// `nonisolated` : pur calcul CGContext sans aucun état partagé, appelé depuis une tâche
    /// détachée pour ne pas bloquer le thread principal — l'isolation `MainActor` par défaut du
    /// projet ne s'applique ici que par inférence, pas par une vraie dépendance à l'acteur.
    nonisolated var averageColor: UIColor? {
        guard let cgImage = self.cgImage else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let alpha = CGFloat(pixel[3]) / 255.0
        guard alpha > 0 else { return nil }

        let red = (CGFloat(pixel[0]) / 255.0) / alpha
        let green = (CGFloat(pixel[1]) / 255.0) / alpha
        let blue = (CGFloat(pixel[2]) / 255.0) / alpha

        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
