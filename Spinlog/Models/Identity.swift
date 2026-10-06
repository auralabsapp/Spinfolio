import Foundation

/// Réponse de `GET /oauth/identity`, confirmant l'utilisateur derrière l'access token courant.
struct Identity: Decodable {
    let id: Int
    let username: String
    let resourceURL: String

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case resourceURL = "resource_url"
    }
}

/// Profil utilisateur Discogs (`GET /users/{username}`).
struct DiscogsUserProfile: Decodable, Sendable {
    let id: Int
    let username: String
    let name: String?
    let email: String?
    let profile: String?
    let location: String?
    let homePage: String?
    let registered: String?
    let numCollection: Int?
    let numWantlist: Int?
    let numLists: Int?
    let releasesContributed: Int?
    let rank: Double?
    let releasesRated: Int?
    let ratingAvg: Double?
    let buyerRating: Double?
    let buyerRatingStars: Double?
    let buyerNumRatings: Int?
    let sellerRating: Double?
    let sellerRatingStars: Double?
    let sellerNumRatings: Int?
    let currAbbr: String?
    let avatarURL: String?
    let profileURL: String?
    let resourceURL: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case email
        case profile
        case location
        case homePage = "home_page"
        case registered
        case numCollection = "num_collection"
        case numWantlist = "num_wantlist"
        case numLists = "num_lists"
        case releasesContributed = "releases_contributed"
        case rank
        case releasesRated = "releases_rated"
        case ratingAvg = "rating_avg"
        case buyerRating = "buyer_rating"
        case buyerRatingStars = "buyer_rating_stars"
        case buyerNumRatings = "buyer_num_ratings"
        case sellerRating = "seller_rating"
        case sellerRatingStars = "seller_rating_stars"
        case sellerNumRatings = "seller_num_ratings"
        case currAbbr = "curr_abbr"
        case avatarURL = "avatar_url"
        case profileURL = "uri"
        case resourceURL = "resource_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // id peut être un Int ou une String
        if let idInt = try? container.decode(Int.self, forKey: .id) {
            id = idInt
        } else if let idStr = try? container.decode(String.self, forKey: .id), let idInt = Int(idStr) {
            id = idInt
        } else {
            id = try container.decode(Int.self, forKey: .id)
        }

        username = try container.decode(String.self, forKey: .username)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        homePage = try container.decodeIfPresent(String.self, forKey: .homePage)
        registered = try container.decodeIfPresent(String.self, forKey: .registered)

        numCollection = Self.decodeInt(from: container, forKey: .numCollection)
        numWantlist = Self.decodeInt(from: container, forKey: .numWantlist)
        numLists = Self.decodeInt(from: container, forKey: .numLists)
        releasesContributed = Self.decodeInt(from: container, forKey: .releasesContributed)
        rank = Self.decodeDouble(from: container, forKey: .rank)
        releasesRated = Self.decodeInt(from: container, forKey: .releasesRated)
        ratingAvg = Self.decodeDouble(from: container, forKey: .ratingAvg)

        buyerRating = Self.decodeDouble(from: container, forKey: .buyerRating)
        buyerRatingStars = Self.decodeDouble(from: container, forKey: .buyerRatingStars)
        buyerNumRatings = Self.decodeInt(from: container, forKey: .buyerNumRatings)

        sellerRating = Self.decodeDouble(from: container, forKey: .sellerRating)
        sellerRatingStars = Self.decodeDouble(from: container, forKey: .sellerRatingStars)
        sellerNumRatings = Self.decodeInt(from: container, forKey: .sellerNumRatings)

        currAbbr = try container.decodeIfPresent(String.self, forKey: .currAbbr)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        profileURL = try container.decodeIfPresent(String.self, forKey: .profileURL)
        resourceURL = try container.decodeIfPresent(String.self, forKey: .resourceURL)
    }

    private static func decodeInt(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let val = try? container.decodeIfPresent(Int.self, forKey: key) {
            return val
        }
        if let str = try? container.decodeIfPresent(String.self, forKey: key), let val = Int(str) {
            return val
        }
        if let dbl = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(dbl)
        }
        return nil
    }

    private static func decodeDouble(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let val = try? container.decodeIfPresent(Double.self, forKey: key) {
            return val
        }
        if let str = try? container.decodeIfPresent(String.self, forKey: key), let val = Double(str) {
            return val
        }
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(intVal)
        }
        return nil
    }
}
