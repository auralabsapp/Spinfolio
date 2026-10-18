import Foundation

/// Lecture mémoïsée d'une date `date_added` Discogs (ISO8601, avec ou sans fraction de seconde
/// selon l'endpoint). Centralisé ici : `CollectionItem`/`WantlistItem` dupliquaient à l'identique
/// les deux `ISO8601DateFormatter` statiques et le cache — voir le commentaire original sur la
/// mesure Instruments (615ms de temps propre pour cette seule ré-analyse répétée ligne après
/// ligne pendant un défilement) qui avait motivé ce cache.
enum DiscogsDateParsing {
    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    /// `NSCache` (thread-safe nativement) : cette lecture est appelée aussi bien depuis
    /// l'affichage des lignes (main actor) que depuis le tri en arrière-plan.
    private static let dateCache = NSCache<NSString, NSDate>()

    static func dateAdded(from rawISODate: String) -> Date? {
        let key = rawISODate as NSString
        if let cached = dateCache.object(forKey: key) {
            return cached as Date
        }
        guard let parsed = isoFormatter.date(from: rawISODate) ?? isoFormatterNoFraction.date(from: rawISODate) else {
            return nil
        }
        dateCache.setObject(parsed as NSDate, forKey: key)
        return parsed
    }
}
