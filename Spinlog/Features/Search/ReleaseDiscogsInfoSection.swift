import SwiftUI

/// Résumés et tests de présence des blocs « Photos et vidéos » et « Autres informations » de la
/// fiche disque : fonctions pures, sans état, testables sans construire la vue.
nonisolated enum ReleaseDetailSummaries {
    static func hasOtherInfo(_ release: Release) -> Bool {
        (release.extraartists?.isEmpty == false) ||
        (release.companies?.isEmpty == false) ||
        (release.identifiers?.isEmpty == false)
    }

    static func otherInfoSummary(_ release: Release) -> String {
        var parts: [String] = []
        if let credits = release.extraartists, !credits.isEmpty {
            parts.append(String(localized: "Crédits (\(credits.count))"))
        }
        if let companies = release.companies, !companies.isEmpty {
            parts.append(String(localized: "Fabrication (\(companies.count))"))
        }
        if let identifiers = release.identifiers, !identifiers.isEmpty {
            parts.append(String(localized: "Identifiants (\(identifiers.count))"))
        }
        return parts.joined(separator: " · ")
    }

    static func hasMedia(_ release: Release) -> Bool {
        additionalImagesCount(release) > 0 || (release.videos?.isEmpty == false)
    }

    /// La première image est la jaquette : il n'y a des « photos » à ouvrir qu'au-delà.
    static func additionalImagesCount(_ release: Release) -> Int {
        guard let images = release.images, images.count > 1 else { return 0 }
        return images.count
    }

    static func mediaSummary(_ release: Release) -> String {
        var parts: [String] = []
        let imagesCount = additionalImagesCount(release)
        if imagesCount > 0 {
            parts.append(String(localized: "\(imagesCount) photos"))
        }
        if let videosCount = release.videos?.count, videosCount > 0 {
            parts.append(String(localized: "\(videosCount) vidéos"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Ligne cliquable d'une carte de la fiche disque : icône, titre, sous-titre et chevron.
private struct ReleaseDisclosureRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: String
    var subtitleLineLimit: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.spinlogPink)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                            .lineLimit(subtitleLineLimit)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .appleMusicGroupedCard()
        }
        .buttonStyle(.plain)
    }
}

/// Section « Infos Discogs sur la release » : regroupe toutes les données propres à la release
/// et communes à tous les exemplaires (par opposition aux sections propres à l'utilisateur et à
/// ses exemplaires). Hiérarchie portée par l'espacement et la typographie (`SectionEyebrow`),
/// sans conteneur ni fond de carte, conformément au style plat des pages de détail Apple
/// Music/iOS.
struct ReleaseDiscogsInfoSection: View {
    let release: Release
    let initialCoverURL: String?
    let onShowMarketplace: () -> Void
    let onShowMedia: () -> Void
    let onShowOtherInfo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SectionEyebrow(title: "Infos Discogs sur la release", icon: "info.circle.fill")

            VStack(alignment: .leading, spacing: 32) {
                if let community = release.community {
                    CommunityStatsBar(community: community)
                }

                let genres = release.genres ?? []
                let styles = release.styles ?? []
                if !genres.isEmpty || !styles.isEmpty {
                    GenreTagsRow(genres: genres, styles: styles)
                }

                ReleaseInfoCard(release: release)

                if let tracklist = release.tracklist, !tracklist.isEmpty {
                    TracklistSection(
                        tracklist: tracklist,
                        artistName: release.artistNames,
                        albumTitle: release.title,
                        coverURL: release.primaryImageURL ?? initialCoverURL,
                        destination: .release(release.id, coverURL: release.primaryImageURL ?? initialCoverURL)
                    )
                }

                if let numForSale = release.numForSale, numForSale > 0 {
                    MarketplaceButton(numForSale: numForSale, lowestPrice: release.lowestPrice, action: onShowMarketplace)
                }

                if ReleaseDetailSummaries.hasMedia(release) {
                    ReleaseDisclosureRow(
                        icon: "photo.on.rectangle.angled",
                        title: "Photos et vidéos",
                        subtitle: ReleaseDetailSummaries.mediaSummary(release),
                        action: onShowMedia
                    )
                }

                // Section Notes placée sous les photos et vidéos avec déplier/replier
                if let notes = release.notes, !notes.isEmpty {
                    NotesSection(notes: notes)
                }

                // Section cliquable "Autres informations" qui ouvre une bottom sheet avec
                // les identifiants, entreprises de fabrication et crédits
                if ReleaseDetailSummaries.hasOtherInfo(release) {
                    ReleaseDisclosureRow(
                        icon: "info.circle",
                        title: "Autres informations",
                        subtitle: ReleaseDetailSummaries.otherInfoSummary(release),
                        subtitleLineLimit: 1,
                        action: onShowOtherInfo
                    )
                }
            }

            if let url = release.discogsWebURL {
                DiscogsAttributionLink(url: url)
            }
        }
    }
}
