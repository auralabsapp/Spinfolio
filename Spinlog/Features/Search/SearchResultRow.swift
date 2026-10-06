import SwiftUI

enum SearchDestination: Hashable {
    case release(id: Int, coverURL: String?)
    case master(Int)
    case artist(Int)
    case label(Int)

    static func release(_ id: Int, coverURL: String? = nil) -> SearchDestination {
        .release(id: id, coverURL: coverURL)
    }

    init(from result: SearchResult) {
        switch result.type {
        case "master": self = .master(result.id)
        case "artist": self = .artist(result.id)
        case "label": self = .label(result.id)
        default: self = .release(result.id, coverURL: result.thumb ?? result.coverImage)
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    private var membership = LibraryMembershipStore.shared

    /// Seuls les résultats "release" ont une correspondance directe en collection/wantlist
    /// (masters/artistes/labels n'ont pas d'identifiant de release à vérifier).
    private var isRelease: Bool { result.type == "release" }

    var body: some View {
        NavigationLink(value: SearchDestination(from: result)) {
            HStack(spacing: 12) {
                AsyncCoverImage(url: result.thumb ?? result.coverImage, cornerRadius: 8, targetSize: 56)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.body)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        if let year = result.year, !year.isEmpty {
                            Text(year)
                        }
                        if let format = result.format?.first {
                            Text("· \(format)")
                        }
                        if let label = result.label?.first {
                            Text("· \(label)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)

                    if isRelease && (membership.isInCollection(result.id) || membership.isInWantlist(result.id)) {
                        HStack(spacing: 6) {
                            if membership.isInCollection(result.id) {
                                membershipPill(text: "Collection", systemImage: "square.stack.fill")
                            }
                            if membership.isInWantlist(result.id) {
                                membershipPill(text: "Wantlist", systemImage: "heart.fill")
                            }
                        }
                        .padding(.top, 1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func membershipPill(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.spinlogPinkBadge, in: Capsule())
            .foregroundStyle(Color.spinlogPink)
    }
}
