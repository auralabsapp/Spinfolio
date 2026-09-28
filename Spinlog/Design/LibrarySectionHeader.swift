import SwiftUI

/// En-tête sticky sur 2 lignes partagé par Collection et Wantlist : le jeton (lettre ou année
/// sur 2 chiffres, cohérent avec la barre de navigation rapide) puis la valeur complète du
/// groupe (artiste, album, mois...), et le nombre d'éléments de la section à droite.
struct LibrarySectionHeader: View {
    let token: String
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(token)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 0)
        .padding(.trailing, 4)
    }
}
