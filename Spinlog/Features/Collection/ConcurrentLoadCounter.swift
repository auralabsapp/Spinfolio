/// Compte les chargements de la Collection en cours en même temps. À la connexion, la pile de
/// Collection est recréée : le chargement lancé par l'ancienne vue est interrompu pendant que celui de
/// la nouvelle démarre. L'interrompu, en se terminant, ne doit ni déclarer « premier chargement
/// terminé » ni éteindre l'indicateur de chargement tant qu'un autre est en cours, sinon l'écran
/// affichait un instant « Collection vide » (une `ScrollView`) à la place de la liste, et la barre de
/// navigation ne suivait plus la liste qui revenait ensuite (grand titre figé, barre transparente).
nonisolated struct ConcurrentLoadCounter {
    private(set) var inFlight = 0

    /// Au moins un autre chargement que celui qui interroge est en cours.
    var othersInFlight: Bool { inFlight > 1 }

    mutating func begin() {
        inFlight += 1
    }

    /// Termine un chargement ; vrai si c'était le dernier encore en cours.
    mutating func end() -> Bool {
        inFlight = max(0, inFlight - 1)
        return inFlight == 0
    }
}
