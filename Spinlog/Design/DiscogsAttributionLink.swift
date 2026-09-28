import SwiftUI

/// Mention exigée par les CGU de l'API Discogs ("Data provided by Discogs" + lien hypertexte
/// vers la page discogs.com correspondante), à afficher à côté du contenu qui en provient —
/// distincte de la mention générale de non-affiliation des Réglages, qui ne couvre pas cette
/// obligation d'attribution par donnée affichée.
struct DiscogsAttributionLink: View {
    let url: URL

    @State private var showingSafari = false

    var body: some View {
        Button {
            showingSafari = true
        } label: {
            HStack(spacing: 4) {
                Text("Données fournies par Discogs")
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(Color.appTertiaryText)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSafari) {
            SafariView(url: url)
        }
    }
}
