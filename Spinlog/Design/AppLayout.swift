import SwiftUI

/// Rayons d'arrondi partagés (miroir d'`AppTypography`/`AppTheme`, mais pour la mise en page) :
/// `cornerRadius: 8` était le rayon de facto des pochettes d'album, mais recopié en toutes
/// lettres dans une vingtaine de fichiers (`AsyncCoverImage` + le liseré `RoundedRectangle` qui
/// l'accompagne) plutôt que promu en constante nommée — alors que le défaut du composant
/// `AsyncCoverImage` lui-même (12pt) ne correspondait déjà plus à cette convention.
nonisolated enum AppLayout {
    /// Rayon d'arrondi standard d'une pochette d'album (résultats de recherche, lignes
    /// Collection/Wantlist, fiche d'édition, podium d'écoutes...).
    static let coverCornerRadius: CGFloat = 8
}
