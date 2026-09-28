import SwiftUI

/// Pochette carrée à coins arrondis, avec halo et état de chargement/erreur.
/// Passe par `DiscogsImageLoader` (et non `AsyncImage` seul) car l'API Discogs exige un
/// `User-Agent` et une signature OAuth même pour les images, avec un cache borné à 6h.
struct AsyncCoverImage: View {
    let url: String?
    var cornerRadius: CGFloat = 12
    var showsBorder: Bool = true
    var onAverageColorLoaded: ((UIColor) -> Void)? = nil

    @State private var uiImage: UIImage?
    @State private var isLoading = true

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
            .task(id: url) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
        } else if isLoading {
            placeholder.overlay { ProgressView() }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "opticaldisc")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    private func load() async {
        uiImage = nil
        guard let urlString = url, let imageURL = URL(string: urlString) else {
            isLoading = false
            return
        }
        isLoading = true
        do {
            let data = try await DiscogsImageLoader.shared.loadData(
                from: imageURL, credentials: DiscogsAuthManager.shared.credentials
            )
            let image = UIImage(data: data)
            uiImage = image
            if let avg = image?.averageColor {
                onAverageColorLoaded?(avg)
            }
        } catch {
            uiImage = nil
        }
        isLoading = false
    }
}

extension UIImage {
    /// Calcule la couleur moyenne de l'image (format RGBA) via un contexte bitmap 1x1 ultra-rapide.
    var averageColor: UIColor? {
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
