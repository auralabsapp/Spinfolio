import SwiftUI

enum SearchDestination: Hashable {
    case release(Int)
    case master(Int)
    case artist(Int)
    case label(Int)

    init(from result: SearchResult) {
        switch result.type {
        case "master": self = .master(result.id)
        case "artist": self = .artist(result.id)
        case "label": self = .label(result.id)
        default: self = .release(result.id)
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        NavigationLink(value: SearchDestination(from: result)) {
            HStack(spacing: 12) {
                AsyncCoverImage(url: result.thumb ?? result.coverImage, cornerRadius: 8)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
