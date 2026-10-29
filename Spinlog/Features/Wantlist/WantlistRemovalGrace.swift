import Foundation

/// Disques retirés de la wantlist pendant la session, à écarter des réponses de Discogs pendant un
/// court délai. L'API de Discogs peut renvoyer encore quelques instants un disque tout juste retiré
/// (propagation côté serveur) ; la liste affichée *fusionne* les pages reçues (voir
/// `WantlistViewModel.mergedWantlistItems`, qui évite qu'un ajout récent disparaisse), donc un disque
/// réintroduit par une réponse en retard n'en repartait plus jamais avant le prochain lancement.
nonisolated struct WantlistRemovalGrace: Sendable {
    /// Au-delà de ce délai, une réponse de Discogs qui contient encore le disque fait foi.
    static let duration: TimeInterval = 120

    private var removedAt: [Int: Date] = [:]

    mutating func markRemoved(_ releaseId: Int, at date: Date = Date()) {
        removedAt[releaseId] = date
    }

    /// Un nouvel ajout (ou l'annulation d'un retrait refusé) lève l'exclusion.
    mutating func unmark(_ releaseId: Int) {
        removedAt[releaseId] = nil
    }

    /// Retire de `items` les disques en sursis ; oublie ceux dont le délai est écoulé ou que la
    /// réponse ne contient plus (Discogs a rattrapé son retard).
    mutating func filtered(_ items: [WantlistItem], now: Date = Date()) -> [WantlistItem] {
        let present = Set(items.map(\.id))
        removedAt = removedAt.filter { id, date in
            now.timeIntervalSince(date) < Self.duration && present.contains(id)
        }
        guard !removedAt.isEmpty else { return items }
        return items.filter { removedAt[$0.id] == nil }
    }
}
