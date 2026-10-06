import Foundation
import SwiftData

/// Représente l'année de sortie originale immuable d'un Master Discogs (`GET /masters/{id}`).
/// Cette information est un fait historique permanent (ex: "The Dark Side of the Moon" -> 1973)
/// et est donc conservée indéfiniment sans expiration TTL.
@Model
final class MasterRecord {
    @Attribute(.unique) var masterId: Int
    var originalYear: Int
    var fetchedAt: Date

    init(masterId: Int, originalYear: Int, fetchedAt: Date = Date()) {
        self.masterId = masterId
        self.originalYear = originalYear
        self.fetchedAt = fetchedAt
    }
}
