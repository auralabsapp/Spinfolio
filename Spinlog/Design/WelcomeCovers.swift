import SwiftUI

/// Pochettes embarquées dans l'app (jeu d'images `WelcomeCover1`, `WelcomeCover2`… du catalogue
/// d'assets) : aucune dépendance à Discogs. Utilisées par l'écran de connexion (`WelcomeView`) et par
/// les écrans vides de la Collection et de la Wantlist (`EmptyLibraryScene`). Pour en ajouter, créer
/// un jeu d'images au nom suivant dans la série (`WelcomeCover7`…, jusqu'à `WelcomeCover30`) : il est
/// pris en compte tout seul. Les images absentes sont ignorées, les écrans fonctionnent aussi sans
/// aucune pochette.
enum WelcomeCovers {
    static let names: [String] = (1...30)
        .map { "WelcomeCover\($0)" }
        .filter { UIImage(named: $0) != nil }
}
