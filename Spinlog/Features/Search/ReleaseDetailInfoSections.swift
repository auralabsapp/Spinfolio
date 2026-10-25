import SwiftUI
import Kingfisher

/// Sections d'informations techniques (format, identifiants, labels, companies, vidéos,
/// galerie d'images) et toast d'écoute de la fiche release — extrait de
/// ReleaseDetailSections.swift, voir le commentaire sur `ReleaseDetailOwnershipCards`.
/// Carte d'infos techniques (format, pays, date de sortie, labels/référence catalogue, master).
/// Les lignes label/master sont navigables vers leurs fiches respectives.
struct ReleaseInfoCard: View {
    let release: Release
    @State private var masterYear: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ReleaseInfoRow(systemImage: row.icon, text: row.text, destination: row.destination)
                if index < rows.count - 1 {
                    Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: release.masterId) {
            await fetchMasterYearIfNeeded()
        }
    }

    private var masterLabelText: String {
        if let masterYear, masterYear > 0 {
            return String(localized: "Sortie originale en \(masterYear) – voir le master")
        }
        return String(localized: "Voir le master")
    }

    private func fetchMasterYearIfNeeded() async {
        guard let masterId = release.masterId, masterId > 0 else { return }
        if let year = await MasterYearLookup.year(for: masterId) {
            masterYear = year
        }
    }

    private var rows: [(id: String, icon: String, text: String, destination: SearchDestination?)] {
        var result: [(id: String, icon: String, text: String, destination: SearchDestination?)] = []
        if let formatLine {
            result.append((id: "format", icon: "opticaldisc", text: formatLine, destination: nil))
        }
        if let country = release.country {
            result.append((id: "country", icon: "mappin.and.ellipse", text: country, destination: nil))
        }
        if let dateLine {
            result.append((id: "date", icon: "calendar", text: dateLine, destination: nil))
        }
        for label in release.labels ?? [] {
            let text = [label.name, label.catno].compactMap { $0 }.joined(separator: " – ")
            result.append((id: "label-\(label.id)", icon: "barcode", text: text, destination: .label(label.id)))
        }
        if let masterId = release.masterId {
            result.append((id: "master", icon: "square.stack.3d.up", text: masterLabelText, destination: .master(masterId)))
        }
        return result
    }

    private var formatLine: String? {
        guard let formats = release.formats, !formats.isEmpty else { return nil }
        return formats
            .map { format in
                ([format.name] + (format.descriptions ?? []) + [format.text].compactMap { $0 })
                    .joined(separator: ", ")
            }
            .joined(separator: " / ")
    }

    private var dateLine: String? {
        guard let formatted = release.formattedReleasedDate else { return nil }
        if let year = release.year, !formatted.contains(String(year)) {
            return "\(formatted) (original \(year))"
        }
        return formatted
    }
}

private struct ReleaseInfoRow: View {
    let systemImage: String
    let text: String
    var destination: SearchDestination?

    var body: some View {
        Group {
            if let destination {
                NavigationLink(value: destination) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.spinlogPink)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            if destination != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTertiaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Identifiants du pressage : codes-barres, numéros de matrice/runout, société de gestion
/// des droits, etc.
struct ReleaseIdentifiersSection: View {
    let identifiers: [ReleaseIdentifier]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Identifiants", icon: "number")
            VStack(spacing: 0) {
                ForEach(Array(identifiers.enumerated()), id: \.offset) { index, identifier in
                    HStack(spacing: 12) {
                        Image(systemName: "barcode")
                            .font(.subheadline)
                            .foregroundStyle(Color.spinlogPink)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            let title = [identifier.type, identifier.description]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            // Pas de ternaire de `String` dans `Text` (§6) : « Identifiant » restait en
                            // français ; le titre Discogs, lui, s'affiche tel quel.
                            (title.isEmpty ? Text("Identifiant") : Text(verbatim: title))
                                .font(.subheadline)
                            Text(identifier.value)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    if index < identifiers.count - 1 {
                        Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
            .appleMusicGroupedCard()
        }
    }
}

/// Sociétés liées à la fabrication/diffusion (pressage, distribution, mastering...),
/// distinctes des labels musicaux déjà listés dans `ReleaseInfoCard`.
struct ReleaseCompaniesSection: View {
    let companies: [ReleaseCompany]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Fabrication", icon: "building.2.fill")
            VStack(spacing: 0) {
                ForEach(Array(companies.enumerated()), id: \.offset) { index, company in
                    HStack(spacing: 12) {
                        Image(systemName: "building.2")
                            .font(.subheadline)
                            .foregroundStyle(Color.spinlogPink)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(company.entityTypeName?.isEmpty == false ? company.entityTypeName! : String(localized: "Société"))
                                .font(.subheadline)
                            Text(company.name)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    if index < companies.count - 1 {
                        Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
            .appleMusicGroupedCard()
        }
    }
}

/// Vidéos associées à la release (généralement des extraits YouTube renseignés sur Discogs).
/// Lues directement dans l'app via `YouTubePlayerView` quand l'identifiant YouTube est
/// reconnaissable ; repli vers un lien externe sinon (format d'URL non supporté).
struct ReleaseVideosSection: View {
    let videos: [ReleaseVideo]

    @State private var videoPlayerRequest: VideoPlayerRequest?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(title: "Vidéos", icon: "video.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(videos) { video in
                        if let videoID = video.youTubeVideoID {
                            Button {
                                videoPlayerRequest = VideoPlayerRequest(videoID: videoID, title: video.title)
                            } label: {
                                videoCard(video)
                            }
                            .buttonStyle(.plain)
                        } else if let url = URL(string: video.uri) {
                            Link(destination: url) {
                                videoCard(video)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .fullScreenCover(item: $videoPlayerRequest) { request in
            VideoPlayerSheet(request: request)
        }
    }

    private func videoCard(_ video: ReleaseVideo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // Kingfisher directement (cache disque borné, comme `AsyncCoverImage`, qui reste
                // réservé aux pochettes carrées) : `AsyncImage` retéléchargeait la vignette 16:9 à
                // chaque affichage, sans cache disque.
                KFImage(video.thumbnailURL)
                    .placeholder { Rectangle().fill(.fill.tertiary) }
                    .downsampling(size: CGSize(width: 160 * displayScale, height: 90 * displayScale))
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            Text(video.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
            if let duration = video.formattedDuration {
                Text(duration)
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }
            if let description = video.description, !description.isEmpty, description != video.title {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
            }
        }
    }
}

/// Galerie des photos de cette release (pochette, verso, label du disque...).
/// Chaque miniature ouvre le visualiseur plein écran à son index via `onSelect`.
struct ReleaseImagesGallery: View {
    let images: [DiscogsImage]
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(title: "Images", icon: "photo.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(images.indices, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            AsyncCoverImage(url: images[index].uri, cornerRadius: 10)
                                .frame(width: 140, height: 140)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(images[index].type == "primary" ? Text("Pochette de l'album") : Text("Photo \(index + 1) de la release"))
                        .accessibilityHint("Voir en plein écran")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }
}
