import SwiftUI

/// Bouton Marketplace élégant et discret placé sous la tracklist
struct MarketplaceButton: View {
    let numForSale: Int
    /// Prix le plus bas renvoyé par `/releases/{id}`, toujours en dollars.
    let lowestPrice: Double?
    let action: () -> Void

    /// Prix converti dans la devise choisie (Réglages → Suivi de cote) ; `nil` tant que la
    /// conversion n'est pas faite, le prix s'affiche alors en dollars comme avant.
    @State private var convertedPrice: (amount: Double, currency: String)?

    private var formattedLowestPrice: String? {
        if let convertedPrice {
            return convertedPrice.amount.formatted(.currency(code: convertedPrice.currency))
        }
        return lowestPrice?.formatted(.currency(code: "USD"))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.title3)
                    .foregroundStyle(Color.spinlogPink)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Marketplace Discogs")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let formattedLowestPrice {
                        Text("\(numForSale) exemplaires en vente dès \(formattedLowestPrice)")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
                    } else {
                        Text("\(numForSale) exemplaires en vente")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondaryText)
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
        .task(id: lowestPrice) {
            guard let lowestPrice, let username = DiscogsAuthManager.shared.username else { return }
            let currency = CollectionPreferencesStore.defaultCurrency(for: username)
            guard currency != "USD" else { return }
            let amount = await CurrencyConversionService.shared.convert(lowestPrice, from: "USD", to: currency)
            convertedPrice = (amount, currency)
        }
    }
}

/// Bandeau compact et moderne des statistiques communautaires (Note moyenne, Possesseurs, Souhaits)
struct CommunityStatsBar: View {
    let community: Community

    var body: some View {
        HStack(spacing: 0) {
            if let rating = community.rating, rating.count > 0 {
                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Color.ratingStar)
                        Text(rating.average.formatted(.number.precision(.fractionLength(1))))
                            .font(.subheadline.weight(.bold))
                    }
                    Text("\(rating.count) avis")
                        .font(.caption2)
                        .foregroundStyle(Color.appSecondaryText)
                }
                .frame(maxWidth: .infinity)

                Divider().overlay(Color.appSeparator)
                    .opacity(0.15)
                    .frame(height: 24)
            }

            VStack(spacing: 2) {
                Text(community.have.formatted())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.spinlogPink)
                Text("Possesseurs")
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(Color.appSeparator)
                .opacity(0.15)
                .frame(height: 24)

            VStack(spacing: 2) {
                Text(community.want.formatted())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.spinlogPink)
                Text("Souhaits")
                    .font(.caption2)
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
    }
}

/// Ligne 3 : tags genres/styles ; défile horizontalement car cette liste dépasse souvent la
/// largeur de l'écran. `.scrollBounceBehavior(.basedOnSize)` désactive l'effet élastique quand
/// le contenu tient déjà à l'écran.
struct GenreTagsRow: View {
    /// Genres larges (ex. "Rock") : mis en évidence, affichés en premier.
    let genres: [String]
    /// Styles/sous-genres (ex. "Alternative Rock") : affichage plus discret.
    let styles: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.spinlogPink, in: Capsule())
                }
                ForEach(styles, id: \.self) { style in
                    Text(style)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
