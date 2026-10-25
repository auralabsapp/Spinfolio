import Foundation
import SwiftUI

/// Stratégie de classement physique des vinyles dans le meuble de l'utilisateur.
enum ShelfSortStrategy: String, CaseIterable, Identifiable, Codable, Sendable {
    case artistThenMasterYear
    case artistThenTitle
    case chronologicalOnly
    case artistThenReleaseYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artistThenMasterYear:
            return String(localized: "Artiste → Année originale (Master)")
        case .artistThenTitle:
            return String(localized: "Artiste → Titre d'album (A-Z)")
        case .chronologicalOnly:
            return String(localized: "Pur chronologique (Année originale)")
        case .artistThenReleaseYear:
            return String(localized: "Artiste → Année du pressage (Release)")
        }
    }

    var shortTitle: String {
        switch self {
        case .artistThenMasterYear:
            return String(localized: "Artiste → Année (Master)")
        case .artistThenTitle:
            return String(localized: "Artiste → Titre")
        case .chronologicalOnly:
            return String(localized: "Année (Master)")
        case .artistThenReleaseYear:
            return String(localized: "Artiste → Pressage")
        }
    }

    var description: String {
        switch self {
        case .artistThenMasterYear:
            return String(localized: "Artiste A-Z, puis année originale (Master)")
        case .artistThenTitle:
            return String(localized: "Artiste A-Z, puis titre d'album de A à Z")
        case .chronologicalOnly:
            return String(localized: "Toute la collection par année originale (Master)")
        case .artistThenReleaseYear:
            return String(localized: "Artiste A-Z, puis année exacte de pressage")
        }
    }

    /// Indique si cette règle s'appuie sur l'année originale (Master) plutôt que sur celle du pressage.
    /// `nonisolated` : pur calcul sur `self` (Sendable), appelé depuis `compareShelf`, qui est
    /// `nonisolated` pour pouvoir trier hors du fil principal.
    nonisolated var usesMasterYear: Bool {
        switch self {
        case .artistThenMasterYear, .chronologicalOnly:
            return true
        case .artistThenTitle, .artistThenReleaseYear:
            return false
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "artistThenMasterYear", "artistThenYear":
            self = .artistThenMasterYear
        case "artistThenTitle":
            self = .artistThenTitle
        case "chronologicalOnly":
            self = .chronologicalOnly
        case "artistThenReleaseYear":
            self = .artistThenReleaseYear
        default:
            return nil
        }
    }
}

/// Outils d'aide au tri alphabétique physique des artistes (inversion « Prénom Nom » -> « Nom, Prénom »,
/// préservation des groupes et ensembles musicaux, gestion des articles et des suffixes Discogs).
/// `nonisolated` : table de données et fonctions pures, sans aucun état partagé — appelée
/// depuis la tâche détachée de `CollectionViewModel.computeSections()` pour le tri `.shelf`.
nonisolated enum ArtistShelfSortHelper {
    /// Nettoie les numéros de désambiguïsation Discogs (ex: « Bill Evans (3) » -> « Bill Evans »).
    static func cleanDiscogsSuffix(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(\d+\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Liste de référence des groupes et duos célèbres (en minuscules) à ne JAMAIS inverser.
    static let knownBands: Set<String> = [
        "pink floyd", "led zeppelin", "daft punk", "deep purple", "dire straits",
        "black sabbath", "iron maiden", "judas priest", "fleetwood mac", "talking heads",
        "depeche mode", "new order", "joy division", "sonic youth", "pearl jam",
        "soundgarden", "alice in chains", "foo fighters", "green day", "smashing pumpkins",
        "massive attack", "chemical brothers", "aphex twin", "tame impala", "arctic monkeys",
        "arcade fire", "vampire weekend", "nine inch nails", "guns n' roses", "steely dan",
        "jethro tull", "lynyrd skynyrd", "king crimson", "beach boys", "the beach boys",
        "simple minds", "tears for fears", "pet shop boys", "beastie boys", "wu-tang clan",
        "public enemy", "cypress hill", "dead kennedys", "bad religion", "sex pistols",
        "ac/dc", "zz top", "status quo", "uriah heep", "dream theater", "slipknot",
        "system of a down", "rage against the machine", "red hot chili peppers",
        "queens of the stone age", "maroon 5", "coldplay", "blondie", "kasabian",
        "franz ferdinand", "royal blood", "wet leg", "khruangbin", "noir désir", "noir desir",
        "téléphone", "telephone", "indochine", "louise attaque", "mano negra",
        "les négresses vertes", "les negresses vertes", "rita mitsouko", "les rita mitsouko",
        "shaka ponk", "caravan palace", "skip the use", "la femme", "feu! chatterton",
        "l'impératrice", "l'imperatrice", "limperatrice", "cassius", "modjo", "stardust",
        "kavinsky", "carpenter brut", "fonky family", "sexion d'assaut", "casseurs flowters",
        "boulevard des airs", "mass hysteria", "counting crows", "modern talking", "savage garden",
        "culture club", "wham!", "soft cell", "cocteau twins", "dead can dance", "boards of canada",
        "godspeed you! black emperor", "neutral milk hotel", "death cab for cutie", "modest mouse",
        "the strokes", "strokes", "the white stripes", "white stripes", "the black keys", "black keys", "the arcs", "arcs",
        "kings of leon", "gorillaz", "kraftwerk", "radiohead", "nirvana", "queen", "aerosmith", "kiss",
        "rammstein", "air", "justice", "phoenix", "mgmt", "chvrches", "alt-j", "foals", "idles",
        "fontaines d.c.", "metallica", "megadeth", "slayer", "anthrax", "motörhead", "motorhead",
        "pantera", "ramones", "the clash", "clash", "the cure", "cure", "the smiths", "smiths",
        "the beatles", "beatles", "the rolling stones", "rolling stones", "the who", "who",
        "the doors", "doors", "the velvet underground", "velvet underground", "the police", "police",
        "the cranberries", "cranberries", "bad brains", "fugazi", "minor threat", "black flag",
        "circle jerks", "social distortion", "dead boys", "new york dolls", "television",
        "patti smith group", "richard hell & the voidoids", "hanoi rocks", "mötley crüe", "motley crue",
        "poison", "skid row", "twisted sister", "quiet riot", "def leppard", "iron butterfly",
        "grand funk railroad", "blue öyster cult", "blue oyster cult", "foghat", "bad company",
        "free", "thin lizzy", "ufo", "scorpions", "krokus", "saxon", "diamond head",
        "venom", "celtic frost", "bathory", "mayhem", "burzum", "darkthrone", "emperor", "immortal",
        "dimmu borgir", "cradle of filth", "cannibal corpse", "death", "morbid angel", "obituary",
        "deicide", "sepultura", "soulfly", "korn", "deftones", "incubus", "disturbed", "godsmack",
        "avenged sevenfold", "bullet for my valentine", "trivium", "killswitch engage", "mastodon",
        "gojira", "meshuggah", "the dillinger escape plan", "between the buried and me", "periphery",
        "animals as leaders", "porcupine tree", "the pineapple thief", "marillion", "genesis", "yes",
        "rush", "camel", "caravan", "soft machine", "gong", "magma", "gentle giant",
        "van der graaf generator", "emerson, lake & palmer", "procol harum", "the moody blues",
        "traffic", "blind faith", "cream", "the yardbirds", "the animals", "the kinks", "the troggs",
        "the zombies", "the hollies", "the monkees", "the turtles", "the byrds", "buffalo springfield",
        "crosby, stills & nash", "crosby, stills, nash & young", "the allman brothers band",
        "the doobie brothers", "little feat", "the band", "the grateful dead", "grateful dead",
        "jefferson airplane", "jefferson starship", "starship", "quicksilver messenger service",
        "big brother & the holding company", "spirit", "love", "moby grape", "electric prunes",
        "13th floor elevators", "the sonics", "the standells", "the seeds", "the shadows",
        "the ventures", "the champs", "booker t. & the m.g.'s", "the meters", "sly & the family stone",
        "kool & the gang", "earth, wind & fire", "the isley brothers", "the o'jays", "the spinners",
        "the four tops", "the temptations", "the miracles", "the supremes", "the marvelettes",
        "martha reeves & the vandellas", "the ronettes", "the crystals", "the shirelles",
        "the shangri-las", "the chordettes", "the platters", "the coasters", "the drifters",
        "the ink spots", "the mills brothers"
    ]

    /// Mots-clés désignant une formation collective musicale qui ne doit pas être inversée.
    static let bandKeywords: Set<String> = [
        "band", "orchestra", "orchestre", "quartet", "quintet", "sextet", "septet", "octet",
        "trio", "duo", "ensemble", "choir", "chorale", "philharmonic", "philharmonique",
        "symphony", "experience", "project", "all stars", "soundsystem", "sound system",
        "collective", "syndicate", "gang", "brothers", "sisters", "family"
    ]

    /// Particules nobiliaires / préfixes de noms de famille restant attachés au nom (ex: « Maxime Le Forestier » -> « Le Forestier, Maxime »).
    static let particlesPrefix: Set<String> = [
        "le", "la", "du", "del", "di", "de"
    ]

    /// Particules placées après le prénom (ex: « Ludwig van Beethoven » -> « Beethoven, Ludwig van »).
    static let particlesSuffix: Set<String> = [
        "van", "von"
    ]

    /// Suffixes de génération (ex: « Sammy Davis Jr. » -> « Davis, Sammy Jr. »).
    static let nameSuffixes: Set<String> = [
        "jr.", "jr", "sr.", "sr", "ii", "iii", "iv"
    ]
}

extension String {
    /// Retourne la clé de tri par artiste pour le meuble physique :
    /// - Nettoie le numéro de désambiguïsation Discogs (« (2) », etc.)
    /// - Applique en priorité absolue les surcharges de tri définies par l'utilisateur
    /// - Ignore les articles initiaux (« The Beatles » -> « Beatles »)
    /// - Inverse les artistes solo (« David Bowie » -> « Bowie, David »)
    /// - Préserve les formations (« Pink Floyd », « Led Zeppelin », « Dave Matthews Band »)
    nonisolated func shelfArtistSortKey(
        ignoreArticles: Bool = true,
        sortByLastName: Bool = false,
        overrides: [String: String]? = nil
    ) -> String {
        let cleaned = ArtistShelfSortHelper.cleanDiscogsSuffix(self)
        guard !cleaned.isEmpty else { return "" }

        if let overrides, let custom = overrides[cleaned], !custom.isEmpty {
            return custom.normalizedForArtistSorting(ignoreArticles: ignoreArticles)
        }

        guard sortByLastName else {
            return cleaned.normalizedForArtistSorting(ignoreArticles: ignoreArticles)
        }

        let (coreName, initialArticle) = cleaned.extractingInitialArticle()
        let lowerPrimary = cleaned.lowercased()
        let lowerCore = coreName.lowercased()

        func buildFinalName(_ name: String) -> String {
            if let initialArticle {
                if ignoreArticles {
                    return "\(name), \(initialArticle)"
                } else {
                    return "\(initialArticle) \(name)"
                }
            } else {
                return name
            }
        }

        // Si c'est un groupe répertorié, ne pas inverser
        if ArtistShelfSortHelper.knownBands.contains(lowerPrimary) || ArtistShelfSortHelper.knownBands.contains(lowerCore) {
            return buildFinalName(coreName)
        }

        // Si le nom contient déjà une virgule (déjà inversé « Nom, Prénom », « Nom, The » ou nom de formation avec virgule), ne pas inverser
        if coreName.contains(",") {
            return buildFinalName(coreName)
        }

        let words = coreName.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Mots-clés de groupe (ex: « Dave Matthews Band », « Miles Davis Quintet »)
        if words.count > 1 {
            if let lastWord = words.last?.lowercased(), ArtistShelfSortHelper.bandKeywords.contains(lastWord) {
                return buildFinalName(coreName)
            }
            if words.count >= 2 {
                let lastTwo = "\(words[words.count - 2]) \(words[words.count - 1])".lowercased()
                if ArtistShelfSortHelper.bandKeywords.contains(lastTwo) {
                    return buildFinalName(coreName)
                }
            }
        }

        // Cas 1 : Artiste en 2 mots (ex: « David Bowie » -> « Bowie, David »)
        if words.count == 2 {
            let firstName = words[0]
            let lastName = words[1]
            if lastName.hasPrefix("(") && lastName.hasSuffix(")") {
                return buildFinalName(firstName)
            }
            return buildFinalName("\(lastName), \(firstName)")
        }

        // Cas 2 : Artiste en 3 mots (ex: « Stevie Ray Vaughan », « Ludwig van Beethoven », « Maxime Le Forestier », « Sammy Davis Jr. »)
        if words.count == 3 {
            if words[2].hasPrefix("(") && words[2].hasSuffix(")") {
                return buildFinalName("\(words[1]), \(words[0])")
            }

            let secondLower = words[1].lowercased()
            let thirdLower = words[2].lowercased()

            if ArtistShelfSortHelper.nameSuffixes.contains(thirdLower) {
                return buildFinalName("\(words[1]), \(words[0]) \(words[2])")
            }

            if ArtistShelfSortHelper.particlesPrefix.contains(secondLower) {
                return buildFinalName("\(words[1]) \(words[2]), \(words[0])")
            }

            if ArtistShelfSortHelper.particlesSuffix.contains(secondLower) {
                return buildFinalName("\(words[2]), \(words[0]) \(words[1])")
            }

            // Structure « Prénom DeuxièmePrénom Nom » (ex: « Stevie Ray Vaughan » -> « Vaughan, Stevie Ray »)
            return buildFinalName("\(words[2]), \(words[0]) \(words[1])")
        }

        return buildFinalName(coreName)
    }

    /// Extrait l'article initial s'il existe : ("Beatles", "The") pour "The Beatles"
    nonisolated func extractingInitialArticle() -> (core: String, article: String?) {
        let text = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ("", nil) }

        if text.count > 2 {
            let prefix2 = text.prefix(2)
            let lower2 = prefix2.lowercased()
            if lower2 == "l'" || lower2 == "l’" {
                let rest = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return (rest, String(prefix2))
            }
        }

        let articles = ["the ", "les ", "le ", "la ", "a ", "an "]
        let lower = text.lowercased()
        for article in articles {
            if lower.hasPrefix(article) {
                let actualArticle = String(text.prefix(article.count)).trimmingCharacters(in: .whitespaces)
                let rest = String(text.dropFirst(article.count)).trimmingCharacters(in: .whitespaces)
                return (rest, actualArticle)
            }
        }

        return (text, nil)
    }

    /// Normalise le nom d'un artiste en plaçant les articles initiaux en fin de nom (« Beatles, The »)
    /// si `ignoreArticles` est actif, ou conserve « The Beatles » si inactif.
    nonisolated func normalizedForArtistSorting(ignoreArticles: Bool = true) -> String {
        guard ignoreArticles else {
            return self.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let (core, article) = self.extractingInitialArticle()
        guard let article else {
            return core
        }
        return "\(core), \(article)"
    }
}

extension Notification.Name {
    static let shelfPreferencesChanged = Notification.Name("com.spinlog.shelfPreferencesChanged")
}
