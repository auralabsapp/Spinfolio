import SwiftUI

/// Petit badge compact pour une note communautaire ou un format (vinyle, CD...).
struct InfoBadge: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
