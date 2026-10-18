import Foundation

/// Format "m:ss" utilisé par Discogs pour les durées de piste (ex: "3:45"). Centralisé ici :
/// avant ce fichier, le format et le parse de ce même format étaient réimplémentés à l'identique
/// dans `MiniPlayerBar`, `ReleaseDetailTracklist`, `Release.swift` et `AppleMusicPlaybackService`.
extension String {
    /// Lit cette chaîne comme une durée au format Discogs ("m:ss"), `nil` si absente ou invalide.
    var discogsDurationSeconds: Int? {
        guard let colonIndex = firstIndex(of: ":") else { return nil }
        let minutesPart = self[..<colonIndex]
        let secondsPart = self[index(after: colonIndex)...]
        guard let minutes = Int(minutesPart), let seconds = Int(secondsPart) else { return nil }
        return minutes * 60 + seconds
    }
}

extension Int {
    /// Formate ce nombre de secondes au format Discogs ("m:ss").
    var formattedAsMinutesSeconds: String {
        String(format: "%d:%02d", self / 60, self % 60)
    }
}
