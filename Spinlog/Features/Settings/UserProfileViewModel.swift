import Foundation
import SwiftUI

/// Ligne d'information générique (icône + libellé + valeur), avec lien Safari optionnel
/// quand `url` est renseignée (ex. site personnel).
struct UserProfileInfoItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: LocalizedStringKey
    let value: String
    var url: URL? = nil
}

@Observable
@MainActor
final class UserProfileViewModel {
    private(set) var profile: DiscogsUserProfile?
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    /// Chargement à l'apparition de la vue. Au retour d'un écran poussé depuis celui-ci, les données
    /// sont déjà affichées : on ne repasse PAS par l'état « chargement », qui remplacerait le
    /// contenu défilant par le squelette et ferait perdre la position de lecture (même règle que
    /// `ReleaseDetailViewModel.loadIfNeeded`).
    func loadIfNeeded(username: String) async {
        guard profile?.username != username || errorMessage != nil else { return }
        await load(username: username)
    }

    func load(username: String) async {
        isLoading = true
        errorMessage = nil
        do {
            profile = try await DiscogsAPIClient.shared.userProfile(
                username: username, credentials: DiscogsAuthManager.shared.credentials
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    var profileURL: URL? {
        if let uri = profile?.profileURL, let url = URL(string: uri) {
            return url
        }
        guard let profile else { return nil }
        return DiscogsConstants.websiteURL.appendingPathComponent("user/\(profile.username)")
    }

    // MARK: - 1. Identité & Contact

    func identityItems(for profile: DiscogsUserProfile) -> [UserProfileInfoItem] {
        // Nom d'utilisateur et identifiant déjà affichés sous le pseudo dans l'en-tête
        // (voir `UserProfileSheet.header(for:)`) : inutile de les répéter ici.
        var items: [UserProfileInfoItem] = []

        if let realName = profile.name, !realName.isEmpty {
            items.append(UserProfileInfoItem(icon: "person", title: "Nom réel", value: realName))
        }

        if let email = profile.email, !email.isEmpty {
            items.append(UserProfileInfoItem(icon: "envelope.fill", title: "Adresse e-mail", value: email))
        }

        if let location = profile.location, !location.isEmpty {
            items.append(UserProfileInfoItem(icon: "mappin.and.ellipse", title: "Localisation", value: location))
        }

        if let homePage = profile.homePage, !homePage.isEmpty {
            let url = URL(string: homePage.hasPrefix("http") ? homePage : "https://\(homePage)")
            items.append(UserProfileInfoItem(icon: "link", title: "Site personnel", value: homePage, url: url))
        }

        return items
    }

    // MARK: - 2. Statistiques d'activité

    func activityItems(for profile: DiscogsUserProfile) -> [UserProfileInfoItem] {
        var items: [UserProfileInfoItem] = []

        if let registered = formattedRegisteredDate(profile.registered) {
            items.append(UserProfileInfoItem(icon: "calendar", title: "Inscription", value: registered))
        }

        if let rank = profile.rank {
            let formattedRank = rank.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(rank))" : String(format: "%.1f", rank)
            items.append(UserProfileInfoItem(icon: "trophy.fill", title: "Rang contributeur", value: formattedRank))
        }

        if let contributed = profile.releasesContributed {
            items.append(UserProfileInfoItem(icon: "arrow.up.doc.fill", title: "Sorties ajoutées", value: "\(contributed)"))
        }

        if let numCollection = profile.numCollection {
            items.append(UserProfileInfoItem(icon: "square.stack.fill", title: "Collection", value: "\(numCollection)"))
        }

        if let numWantlist = profile.numWantlist {
            items.append(UserProfileInfoItem(icon: "heart.fill", title: "Wantlist", value: "\(numWantlist)"))
        }

        if let numLists = profile.numLists {
            items.append(UserProfileInfoItem(icon: "list.bullet", title: "Listes publiques", value: "\(numLists)"))
        }

        if let releasesRated = profile.releasesRated, releasesRated > 0 {
            let ratingText = profile.ratingAvg.map { String(format: "%.1f", $0) } ?? "—"
            items.append(UserProfileInfoItem(
                icon: "star.fill",
                title: "Notes données",
                value: "\(releasesRated) (\(String(localized: "moy. \(ratingText)")))"
            ))
        }

        return items
    }

    // MARK: - 3. Marketplace

    private func isSellerActive(_ profile: DiscogsUserProfile) -> Bool {
        if let num = profile.sellerNumRatings, num > 0 {
            return true
        }
        if let rating = profile.sellerRating, rating > 0 {
            return true
        }
        return false
    }

    func marketplaceItems(for profile: DiscogsUserProfile) -> [UserProfileInfoItem] {
        var items: [UserProfileInfoItem] = []

        if let buyerRating = profile.buyerRating {
            let ratingStr = buyerRating.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(buyerRating)) %" : String(format: "%.1f %%", buyerRating)
            items.append(UserProfileInfoItem(icon: "bag.fill", title: "Note acheteur", value: ratingStr))
        }

        if let stars = profile.buyerRatingStars {
            let starsStr = String(format: "%.1f ★", stars)
            let starStr: String
            if let count = profile.buyerNumRatings, count > 0 {
                starStr = "\(starsStr) (\(String(localized: "\(count) avis")))"
            } else {
                starStr = starsStr
            }
            items.append(UserProfileInfoItem(icon: "star.leadinghalf.filled", title: "Évaluation acheteur", value: starStr))
        }

        if isSellerActive(profile) {
            var sellerDetails: [String] = []
            if let rating = profile.sellerRating {
                let formatted = rating.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(rating)) %" : String(format: "%.1f %%", rating)
                sellerDetails.append(formatted)
            }
            if let count = profile.sellerNumRatings, count > 0 {
                sellerDetails.append(String(localized: "\(count) avis"))
            }
            items.append(UserProfileInfoItem(icon: "tag.fill", title: "Statistiques vendeur", value: sellerDetails.joined(separator: " · ")))
        }

        if let currAbbr = profile.currAbbr, !currAbbr.isEmpty {
            items.append(UserProfileInfoItem(icon: "creditcard.fill", title: "Devise préférée", value: currAbbr))
        }

        return items
    }

    private func formattedRegisteredDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }

        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: raw) {
            return date.formatted(date: .long, time: .omitted)
        }

        let formatterStandard = ISO8601DateFormatter()
        formatterStandard.formatOptions = [.withInternetDateTime]
        if let date = formatterStandard.date(from: raw) {
            return date.formatted(date: .long, time: .omitted)
        }

        return raw
    }
}
