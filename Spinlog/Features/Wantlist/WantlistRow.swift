import SwiftUI

struct WantlistRow: View {
    let item: WantlistItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncCoverImage(url: item.basicInformation.thumb ?? item.basicInformation.coverImage, cornerRadius: 8)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.basicInformation.title).lineLimit(2)
                Text(item.basicInformation.artistNames)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
