import SwiftUI

/// Échelle de polices centralisée (miroir typographique d'`AppTheme.swift`, qui centralise déjà
/// les couleurs) : avant ce fichier, chaque écran choisissait ses propres tailles `.system(size:)`
/// à l'œil, menant à 24 tailles numériques distinctes (6.5 à 64pt) sans palier cohérent, et à
/// plusieurs textes réels sous le minimum de lisibilité recommandé (~11pt) — un rail de recherche
/// rapide retombant même à 9pt, un badge « PREMIUM » stylé différemment à 3 endroits, etc.
///
/// Pour tout texte "normal" (titres, corps, légendes), préférer les styles sémantiques d'Apple
/// (`.subheadline`, `.caption`, `.footnote`...) : ils suivent Dynamic Type nativement et couvrent
/// déjà l'essentiel des besoins de l'app. Les tokens ci-dessous ne couvrent que les rôles
/// récurrents qui nécessitent une taille fixe (glyphe dans un badge rond, gros chiffre de
/// statistique...) et qui étaient dupliqués à l'identique (ou presque) dans plusieurs fichiers.
extension Font {
    /// Glyphe SF Symbols à l'intérieur d'un petit badge/cercle (icônes de lecture, retrait de tag,
    /// chevron de lien...). Remplace un nuage de tailles ad hoc entre 6.5 et 11pt réparties sur
    /// une quinzaine de fichiers pour exactement le même rôle visuel.
    static let inlineIcon = Font.system(size: 12, weight: .bold)

    /// Libellé court et insistant (« PREMIUM »...) à côté d'une icône `inlineIcon`. Remplace deux
    /// styles différents (9pt bold / 10pt heavy) utilisés pour le même libellé sur deux écrans.
    static let emphasisLabel = Font.system(size: 11, weight: .bold)

    /// Gros chiffre de statistique (écran Stats). Dupliqué à l'identique 3 fois avant ce fichier.
    static let statHeadlineNumber = Font.system(size: 32, weight: .heavy, design: .rounded)

    /// Badge dans le coin d'une pochette miniature (nombre d'exemplaires, note, lecture en cours).
    /// Ces badges utilisaient chacun une taille différente (9, 8, 8, 7 pt) sur la même carte —
    /// unifiés ici en un seul token, à 11 pt (et non plus 10) : ils portent du texte réel (numéro
    /// d'exemplaire, note), qui ne doit pas descendre sous le plancher de lisibilité.
    static let coverCornerBadge = Font.system(size: 11, weight: .bold)
}
