import SwiftUI

/// Titre de section discret ("eyebrow"), en petites majuscules grises, plutôt qu'un `.headline`
/// gras répété à chaque section — évite que tous les blocs "crient" au même volume visuel.
struct SectionEyebrow: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .kerning(0.4)
    }
}

/// Pastille compacte pour la "bandeau de repères" (note, have/want, marketplace, genres/styles).
private struct FactChip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.fill.tertiary, in: Capsule())
    }
}

/// Bandeau unique regroupant note communauté, have/want, aperçu marketplace (tappable) et
/// tags genres/styles — auparavant 3 blocs empilés avec des styles différents.
struct FactsStripRow: View {
    let community: Community?
    let numForSale: Int?
    let lowestPrice: Double?
    let tags: [String]
    let onTapMarketplace: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let rating = community?.rating, rating.count > 0 {
                    FactChip {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating.average))
                            Text("(\(rating.count))").foregroundStyle(.secondary)
                        }
                    }
                }
                if let community {
                    FactChip { Label("\(community.have)", systemImage: "square.stack") }
                    FactChip { Label("\(community.want)", systemImage: "heart") }
                }
                if let numForSale, numForSale > 0 {
                    Button(action: onTapMarketplace) {
                        FactChip {
                            if let lowestPrice {
                                Text("\(numForSale) en vente dès \(lowestPrice.formatted(.currency(code: "USD")))")
                            } else {
                                Text("\(numForSale) en vente")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(tags, id: \.self) { tag in
                    FactChip { Text(tag) }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// Carte "Mon exemplaire" : notes/champs personnalisés Discogs (si possédé) + tags perso,
/// réunis dans un seul bloc au lieu de deux tuiles séparées.
struct MyItemCard: View {
    let item: CollectionItem?
    let releaseId: Int
    let onOpenNotes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Mon exemplaire")
            VStack(spacing: 0) {
                if let item {
                    Button(action: onOpenNotes) {
                        HStack(spacing: 12) {
                            AsyncCoverImage(url: item.basicInformation.thumb ?? item.basicInformation.coverImage, cornerRadius: 6)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Notes et champs personnalisés")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                if let date = item.dateAddedDate {
                                    Text("Ajouté le \(date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "fr_FR"))))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TagsEditor(releaseId: releaseId)
                }
                .padding(12)
            }
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Carte d'infos techniques (format, pays, date de sortie, labels/référence catalogue, master).
/// Les lignes label/master sont navigables vers leurs fiches respectives.
struct ReleaseInfoCard: View {
    let release: Release

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ReleaseInfoRow(systemImage: row.icon, text: row.text, destination: row.destination)
                if index < rows.count - 1 {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 4)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            result.append((id: "master", icon: "square.stack.3d.up", text: "Voir le master", destination: .master(masterId)))
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
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            if destination != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
            SectionEyebrow(title: "Identifiants")
            VStack(spacing: 0) {
                ForEach(Array(identifiers.enumerated()), id: \.offset) { index, identifier in
                    HStack(spacing: 12) {
                        Image(systemName: "barcode")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            let title = [identifier.type, identifier.description]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            Text(title.isEmpty ? "Identifiant" : title)
                                .font(.subheadline)
                            Text(identifier.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    if index < identifiers.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Sociétés liées à la fabrication/diffusion (pressage, distribution, mastering...),
/// distinctes des labels musicaux déjà listés dans `ReleaseInfoCard`.
struct ReleaseCompaniesSection: View {
    let companies: [ReleaseCompany]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Fabrication")
            VStack(spacing: 0) {
                ForEach(Array(companies.enumerated()), id: \.offset) { index, company in
                    HStack(spacing: 12) {
                        Image(systemName: "building.2")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(company.entityTypeName?.isEmpty == false ? company.entityTypeName! : "Société")
                                .font(.subheadline)
                            Text(company.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    if index < companies.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Vidéos associées à la release (généralement des extraits YouTube renseignés sur Discogs).
struct ReleaseVideosSection: View {
    let videos: [ReleaseVideo]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Vidéos")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(videos) { video in
                        if let url = URL(string: video.uri) {
                            Link(destination: url) {
                                videoCard(video)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func videoCard(_ video: ReleaseVideo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                AsyncImage(url: video.thumbnailURL) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(16.0 / 9.0, contentMode: .fill)
                    } else {
                        Rectangle().fill(.fill.tertiary)
                    }
                }
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
                    .foregroundStyle(.secondary)
            }
            if let description = video.description, !description.isEmpty, description != video.title {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Images")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(images.indices, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            AsyncCoverImage(url: images[index].uri, cornerRadius: 10)
                                .frame(width: 140, height: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
