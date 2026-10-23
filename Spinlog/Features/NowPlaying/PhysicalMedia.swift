import Foundation

/// Support physique d'un album, tel que l'écoute sur platine le montre (vinyle, CD ou cassette). Les
/// autres supports (fichier…) retombent sur le vinyle.
nonisolated enum PhysicalMedia: Equatable, Sendable {
    case vinyl
    case cd
    case cassette

    /// Support d'après les noms de formats Discogs (« Vinyl », « CD », « CDr », « SACD », « Box Set »…).
    /// Le premier nom reconnu l'emporte : un « Box Set » suivi de « CD » est un CD, un vinyle accompagné
    /// d'un CD bonus reste un vinyle. Sans nom reconnu : vinyle.
    static func from(formatNames: [String]) -> PhysicalMedia {
        for name in formatNames {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "vinyl" { return .vinyl }
            if normalized == "cd" || normalized == "cdr" || normalized == "sacd" || normalized == "hdcd" {
                return .cd
            }
            if normalized == "cassette" { return .cassette }
        }
        return .vinyl
    }
}
