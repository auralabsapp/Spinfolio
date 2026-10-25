import WidgetKit
import SwiftUI
import ImageIO
import OSLog

/// Dupliqué depuis `Secrets.swift` (côté app, non visible depuis l'extension) : Discogs demande
/// un User-Agent identifiable sur toutes les requêtes, y compris les images de pochette.
private let widgetUserAgent = "Spinlog/1.0 +https://github.com/aurelienscarpa/Spinlog"
/// Couleur du thème choisi dans l'app (voir `WidgetSnapshotStore`), avec repli sur le rose
/// historique tant que l'app ne l'a pas encore transmise.
private enum WidgetThemeColor {
    static var onDark: Color {
        WidgetSnapshotStore.themeAccentOnDark ?? Color(red: 232 / 255, green: 76 / 255, blue: 139 / 255)
    }
    static var onLight: Color {
        WidgetSnapshotStore.themeAccentOnLight ?? Color(red: 185 / 255, green: 20 / 255, blue: 90 / 255)
    }
}
private let widgetLogger = Logger(subsystem: "com.aurelienscarpa.Spinlog", category: "WidgetSnapshotSync")

/// Analyse de la couleur et luminosité de la jaquette pour adapter dynamiquement la lisibilité du texte.
struct CoverAnalysis: Sendable {
    let isLight: Bool
    let luminance: Double

    static let darkDefault = CoverAnalysis(isLight: false, luminance: 0.1)

    static func analyze(imageData: Data?) -> CoverAnalysis {
        guard let imageData, let uiImage = UIImage(data: imageData) else {
            return .darkDefault
        }
        guard let cgImage = uiImage.cgImage else {
            return .darkDefault
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return .darkDefault
        }

        // On analyse la zone inférieure de l'image où se superpose le texte
        let bottomHeight = max(1, height / 2)
        let bottomY = height - bottomHeight
        let targetRect = CGRect(x: 0, y: bottomY, width: width, height: bottomHeight)

        guard let cropped = cgImage.cropping(to: targetRect) else {
            return .darkDefault
        }

        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return .darkDefault
        }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0

        // Formule de luminance standard (sRGB / ITU-R BT.709)
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let isLight = lum >= 0.45

        return CoverAnalysis(isLight: isLight, luminance: lum)
    }
}

/// États distincts affichables par le widget (accessible à tous, premium ou non).
/// `appGroupUnavailable` est délibérément séparé de `empty` : ce dernier est un état légitime
/// (collection vide), alors que le premier signale que le pont de données app ↔ widget (App
/// Group) n'a jamais fonctionné — un problème de configuration, pas un état normal de l'app.
enum RandomAlbumWidgetState {
    case appGroupUnavailable
    case empty
    case album(RandomAlbumSnapshotItem, coverImageData: Data?, isLightCover: Bool)
}

struct RandomAlbumEntry: TimelineEntry {
    let date: Date
    let state: RandomAlbumWidgetState
}

struct RandomAlbumProvider: TimelineProvider {
    /// Aperçu affiché pendant le chargement et dans la galerie de widgets : la mise en page
    /// d'un album (masquée par le système en placeholder), plutôt que le message « Aucun disque »,
    /// qui présentait le widget comme vide avant même son ajout.
    private static var sampleEntry: RandomAlbumEntry {
        RandomAlbumEntry(
            date: Date(),
            state: .album(
                RandomAlbumSnapshotItem(releaseId: 0, title: "Kind of Blue", artistNames: "Miles Davis", coverURL: nil),
                coverImageData: nil,
                isLightCover: false
            )
        )
    }

    func placeholder(in context: Context) -> RandomAlbumEntry {
        Self.sampleEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (RandomAlbumEntry) -> Void) {
        // WidgetKit accepte l'appel de `completion` depuis n'importe quel fil, mais ne la déclare
        // pas `Sendable` : sans cette annotation, Swift 6 refuse de la capturer dans la tâche.
        nonisolated(unsafe) let completion = completion
        let isPreview = context.isPreview
        Task {
            let entry = await buildEntry(for: Date())
            // Galerie de widgets : sans collection encore disponible, on montre à quoi ressemble
            // le widget plutôt qu'un message d'état.
            if isPreview, case .album = entry.state {
                completion(entry)
            } else if isPreview {
                completion(Self.sampleEntry)
            } else {
                completion(entry)
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RandomAlbumEntry>) -> Void) {
        // Voir `getSnapshot`.
        nonisolated(unsafe) let completion = completion
        Task {
            let entry = await buildEntry(for: Date())
            let calendar = Calendar.current
            let nextMidnight = calendar.nextDate(
                after: Date(),
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? Date().addingTimeInterval(DiscogsConstants.oneDayTTL)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
        }
    }

    private func buildEntry(for date: Date) async -> RandomAlbumEntry {
        guard WidgetSnapshotStore.hasReceivedDataFromApp else {
            widgetLogger.log("buildEntry : appGroupUnavailable (aucune donnée jamais reçue de l'app).")
            return RandomAlbumEntry(date: date, state: .appGroupUnavailable)
        }
        let pool = WidgetSnapshotStore.loadCollection()
        widgetLogger.log("buildEntry : \(pool.count) disque(s) lus depuis l'App Group.")
        guard let album = WidgetSnapshotStore.randomAlbum(for: date, from: pool) else {
            widgetLogger.log("buildEntry : empty (aucun disque dans l'instantané).")
            return RandomAlbumEntry(date: date, state: .empty)
        }
        widgetLogger.log("buildEntry : album choisi -> \(album.title, privacy: .private) (releaseId=\(album.releaseId)).")
        let data = await fetchImageData(from: album.coverURL)
        let isLight = CoverAnalysis.analyze(imageData: data).isLight
        return RandomAlbumEntry(date: date, state: .album(album, coverImageData: data, isLightCover: isLight))
    }

    private func fetchImageData(from urlString: String?) async -> Data? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(widgetUserAgent, forHTTPHeaderField: "User-Agent")
        // L'extension dispose d'un temps d'exécution limité : mieux vaut afficher le widget sans
        // pochette que d'attendre les 60 s par défaut et risquer d'être interrompu par le système.
        request.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return Self.downsampled(data, maxPixelSize: 600) ?? data
        } catch {
            return nil
        }
    }

    /// Réduit la pochette (souvent 600 à 1200+ px chez Discogs) avant de la décoder et de la
    /// stocker dans l'entrée : une extension de widget a un budget mémoire serré, et WidgetKit
    /// refuse d'afficher les images trop grandes.
    private static func downsampled(_ data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
    }
}

/// Constante locale : `DiscogsConstants` (app) n'est pas visible ici, mais l'extension n'a besoin
/// que de cette seule valeur pour calculer la prochaine échéance de secours.
private enum DiscogsConstants {
    static let oneDayTTL: TimeInterval = 24 * 3600
}

struct RandomAlbumWidgetView: View {
    let entry: RandomAlbumEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.state {
            case .appGroupUnavailable:
                // Aucune donnée encore reçue de l'app : le plus souvent, elle n'a simplement pas
                // été ouverte depuis l'installation. Le diagnostic technique (App Group mal
                // configuré) reste dans les logs, il n'a pas sa place devant l'utilisateur.
                statusView(
                    icon: "opticaldisc",
                    title: "Ouvre Spinfolio",
                    message: "Ouvre l'app une fois pour afficher ici un disque de ta collection."
                )
            case .empty:
                statusView(
                    icon: "opticaldisc",
                    title: "Aucun disque",
                    message: "Ajoute des albums à ta collection Discogs pour activer ce widget."
                )
            case .album(let album, let coverImageData, let isLightCover):
                albumView(album, coverImageData: coverImageData, isLight: isLightCover)
            }
        }
        .containerBackground(for: .widget) {
            Color(white: 0.07)
        }
        .widgetURL(widgetURL)
    }

    private var widgetURL: URL? {
        guard case .album(let album, _, _) = entry.state else { return nil }
        return URL(string: "spinlog://release/\(album.releaseId)")
    }

    @ViewBuilder
    private func albumView(_ album: RandomAlbumSnapshotItem, coverImageData: Data?, isLight: Bool) -> some View {
        switch family {
        case .systemSmall:
            ZStack(alignment: .bottomLeading) {
                cover(data: coverImageData)
                scrim(isLight: isLight)
                VStack(alignment: .leading, spacing: 3) {
                    eyebrow(isLight: isLight)
                    Text(album.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(titleColor(isLight: isLight))
                        .shadow(
                            color: isLight ? .white.opacity(0.6) : .black.opacity(0.8),
                            radius: isLight ? 1 : 2,
                            x: 0,
                            y: 1
                        )
                        .lineLimit(2)
                    Text(album.artistNames)
                        .font(.caption2)
                        .foregroundStyle(artistColor(isLight: isLight))
                        .lineLimit(1)
                }
                .padding(12)
            }

        case .systemMedium:
            ZStack {
                atmosphericBackground(data: coverImageData, isLight: isLight)

                HStack(spacing: 14) {
                    cover(data: coverImageData)
                        .frame(width: 108, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(
                            color: .black.opacity(isLight ? 0.2 : 0.45),
                            radius: 8,
                            x: 0,
                            y: 4
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        eyebrow(isLight: isLight)
                        Text(album.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(titleColor(isLight: isLight))
                            .shadow(
                                color: isLight ? .white.opacity(0.4) : .black.opacity(0.6),
                                radius: 1,
                                x: 0,
                                y: 1
                            )
                            .lineLimit(2)
                        Text(album.artistNames)
                            .font(.caption)
                            .foregroundStyle(artistColor(isLight: isLight))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }

        default:
            ZStack(alignment: .bottomLeading) {
                cover(data: coverImageData)
                scrim(isLight: isLight)
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow(isLight: isLight)
                    Text(album.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(titleColor(isLight: isLight))
                        .shadow(
                            color: isLight ? .white.opacity(0.6) : .black.opacity(0.8),
                            radius: isLight ? 1 : 2,
                            x: 0,
                            y: 1
                        )
                        .lineLimit(2)
                    Text(album.artistNames)
                        .font(.subheadline)
                        .foregroundStyle(artistColor(isLight: isLight))
                        .lineLimit(1)
                }
                .padding(16)
            }
        }
    }

    /// Dégradé de lisibilité en pied de widget adapté au ton clair ou sombre de la jaquette.
    private func scrim(isLight: Bool) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.12),
                .init(color: (isLight ? Color.white : Color.black).opacity(0.55), location: 0.52),
                .init(color: (isLight ? Color.white : Color.black).opacity(0.92), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Couleur du titre avec contraste renforcé selon le fond clair ou sombre.
    private func titleColor(isLight: Bool) -> Color {
        isLight ? Color.black.opacity(0.92) : Color.white
    }

    /// Couleur du nom d'artiste avec lisibilité garantie selon le fond clair ou sombre.
    private func artistColor(isLight: Bool) -> Color {
        isLight ? Color.black.opacity(0.70) : Color.white.opacity(0.80)
    }

    /// Titre "Album du jour" : teinte foncée du thème sur fond clair, teinte vive sur fond sombre.
    private func eyebrow(isLight: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "shuffle")
                .font(.caption2.weight(.bold))
            Text("ALBUM DU JOUR")
                .font(.caption2.weight(.bold))
                .kerning(0.5)
        }
        .foregroundStyle(isLight ? WidgetThemeColor.onLight : WidgetThemeColor.onDark)
    }

    @ViewBuilder
    private func atmosphericBackground(data: Data?, isLight: Bool) -> some View {
        if let data, let uiImage = UIImage(data: data) {
            GeometryReader { proxy in
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 24)
                    .overlay(
                        (isLight ? Color.white : Color.black)
                            .opacity(isLight ? 0.60 : 0.65)
                    )
                    .clipped()
            }
        } else {
            Color(white: 0.07)
        }
    }

    @ViewBuilder
    private func cover(data: Data?) -> some View {
        if let data, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(white: 0.12)
                SpinningVinylIcon(size: family == .systemSmall ? 40 : 56)
            }
        }
    }

    private func statusView(icon: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(WidgetThemeColor.onDark)
            if family != .systemSmall {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Text(message)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(family == .systemSmall ? 3 : 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RandomAlbumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RandomAlbumWidget", provider: RandomAlbumProvider()) { entry in
            RandomAlbumWidgetView(entry: entry)
        }
        .configurationDisplayName("Album du jour")
        .description("Un disque de ta collection Discogs tiré au hasard chaque jour.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview("Clair", as: .systemSmall) {
    RandomAlbumWidget()
} timeline: {
    RandomAlbumEntry(
        date: Date(),
        state: .album(
            RandomAlbumSnapshotItem(
                releaseId: 1,
                title: "The White Album",
                artistNames: "The Beatles",
                coverURL: nil
            ),
            coverImageData: nil,
            isLightCover: true
        )
    )
}

#Preview("Sombre", as: .systemSmall) {
    RandomAlbumWidget()
} timeline: {
    RandomAlbumEntry(
        date: Date(),
        state: .album(
            RandomAlbumSnapshotItem(
                releaseId: 2,
                title: "The Dark Side of the Moon",
                artistNames: "Pink Floyd",
                coverURL: nil
            ),
            coverImageData: nil,
            isLightCover: false
        )
    )
}
