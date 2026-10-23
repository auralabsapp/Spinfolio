import SwiftUI

/// Un réglage retrouvable par la recherche de Réglages : son libellé, la page où il se trouve, et des
/// mots-clés (français et anglais, jamais affichés) pour qu'on le trouve sous plusieurs noms.
struct SettingsSearchEntry: Identifiable {
    let id: String
    /// Libellé affiché (déjà traduit).
    let title: String
    /// Page de Réglages qui le contient (déjà traduite), affichée sous le libellé.
    let location: String
    let symbol: String
    let color: Color
    let destination: SettingsDestination
    /// Mots-clés propres à la recherche : volontairement hors catalogue de traductions, pour qu'une
    /// recherche en anglais fonctionne même avec l'app en français, et inversement.
    let keywords: [String]
    var requiresAccount = false
}

/// Règle de correspondance de la recherche, séparée pour être testée : chaque mot saisi doit se
/// retrouver quelque part dans le libellé, la page ou les mots-clés, sans tenir compte de la casse ni
/// des accents.
nonisolated enum SettingsSearchMatcher {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    static func matches(query: String, haystack: [String]) -> Bool {
        let tokens = normalize(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return false }
        let normalizedHaystack = normalize(haystack.joined(separator: " "))
        return tokens.allSatisfy { normalizedHaystack.contains($0) }
    }
}

/// Index des réglages de l'écran d'accueil : une entrée par réglage, qui ouvre la page concernée.
@MainActor
enum SettingsSearchIndex {
    static func entries(isAuthenticated: Bool, isPremium: Bool) -> [SettingsSearchEntry] {
        let organization = String(localized: "Organisation")
        let shelving = String(localized: "Rangement")
        let gain = String(localized: "Suivi de plus-value")
        let export = String(localized: "Export")
        let listening = String(localized: "Écoute et Apple Music")
        let iCloud = String(localized: "Synchronisation iCloud")
        let offline = String(localized: "Données hors ligne")
        let appearance = String(localized: "Apparence")
        let about = String(localized: "À propos")
        let account = String(localized: "Compte Discogs")
        let help = String(localized: "Aide & personnalisation")

        let all: [SettingsSearchEntry] = [
            .init(id: "grades", title: String(localized: "Mes grades"), location: account, symbol: "rosette", color: Color.spinlogPink,
                  destination: .grades, keywords: ["grade", "badge", "rang", "niveau", "rank", "level", "récompense", "reward"]),
            .init(id: "tags", title: String(localized: "Gestion des tags"), location: organization, symbol: "tag.fill", color: .orange,
                  destination: .tags, keywords: ["tag", "étiquette", "label"]),
            .init(id: "folders", title: String(localized: "Gestion des dossiers"), location: organization, symbol: "folder.fill", color: .blue,
                  destination: .folders, keywords: ["dossier", "folder", "défaut", "default", "ajout"], requiresAccount: true),
            .init(id: "shelfRule", title: String(localized: "Règle de rangement dans le meuble"), location: shelving, symbol: "books.vertical.fill", color: .indigo,
                  destination: .shelving, keywords: ["meuble", "rangement", "classement", "étagère", "shelf", "sort", "tri"]),
            .init(id: "articles", title: String(localized: "Ignorer les articles (The...)"), location: organization, symbol: "text.quote", color: .teal,
                  destination: .organization, keywords: ["article", "the", "le", "la", "les", "beatles"]),
            .init(id: "lastName", title: String(localized: "Trier par nom de famille"), location: organization, symbol: "person.text.rectangle", color: .purple,
                  destination: .organization, keywords: ["nom de famille", "artiste", "last name", "surname", "artist"]),
            .init(id: "sameFolder", title: String(localized: "Limiter au dossier Discogs"), location: shelving, symbol: "square.stack.3d.up.fill", color: .orange,
                  destination: .shelving, keywords: ["dossier", "folder", "guide de rangement", "comparer"]),
            .init(id: "artistSort", title: String(localized: "Personnaliser le tri des artistes"), location: organization, symbol: "slider.horizontal.3", color: .pink,
                  destination: .artistSort, keywords: ["artiste", "artist", "tri", "ordre", "personnaliser", "custom"]),
            .init(id: "gainHelp", title: String(localized: "Comment ça fonctionne ?"), location: gain, symbol: "questionmark.circle.fill", color: .mint,
                  destination: .purchasePriceHelp, keywords: ["plus-value", "gain", "aide", "help", "cote", "valeur", "value"]),
            .init(id: "purchaseField", title: String(localized: "Champ prix d'achat"), location: gain, symbol: "tag.fill", color: .green,
                  destination: .gainTracking, keywords: ["prix", "achat", "payé", "purchase", "price", "paid"], requiresAccount: true),
            .init(id: "conditionField", title: String(localized: "Champ état du disque"), location: gain, symbol: "opticaldisc.fill", color: .purple,
                  destination: .gainTracking, keywords: ["état", "condition", "media", "sleeve", "mint", "conservation"], requiresAccount: true),
            .init(id: "currency", title: String(localized: "Devise par défaut"), location: gain, symbol: "eurosign.circle.fill", color: .blue,
                  destination: .gainTracking, keywords: ["devise", "currency", "euro", "dollar", "monnaie"], requiresAccount: true),
            .init(id: "csv", title: String(localized: "Exporter la collection en CSV"), location: export, symbol: "tablecells", color: .green,
                  destination: .export, keywords: ["csv", "excel", "numbers", "tableur", "spreadsheet", "exporter"]),
            .init(id: "pdf", title: String(localized: "Déclaration de collection (PDF)"), location: export, symbol: "doc.richtext", color: .indigo,
                  destination: .export, keywords: ["pdf", "assurance", "assureur", "insurance", "déclaration", "inventaire"]),
            .init(id: "autoStop", title: String(localized: "Arrêt automatique de l'écoute"), location: listening, symbol: "timer", color: .indigo,
                  destination: .listening, keywords: ["live activity", "durée", "duration", "platine", "turntable", "timer", "automatique"]),
            .init(id: "appleMusic", title: String(localized: "Connecter mon compte Apple Music"), location: listening, symbol: "music.note", color: .pink,
                  destination: .listening, keywords: ["apple music", "musique", "music", "streaming", "extrait", "abonnement"]),
            .init(id: "iCloud", title: String(localized: "Synchroniser avec iCloud"), location: iCloud, symbol: "icloud.fill", color: .blue,
                  destination: .iCloud, keywords: ["icloud", "cloud", "synchro", "sync", "appareils", "devices"]),
            .init(id: "offline", title: String(localized: "Mode hors ligne"), location: offline, symbol: "arrow.down.circle.fill", color: .teal,
                  destination: isPremium ? .offline : .offlineLocked, keywords: ["hors ligne", "offline", "archive", "brocante", "télécharger", "download", "réseau"]),
            .init(id: "display", title: String(localized: "Mode d'affichage"), location: appearance, symbol: "circle.lefthalf.filled", color: .indigo,
                  destination: .appearance, keywords: ["sombre", "clair", "dark", "light", "système", "system", "apparence"]),
            .init(id: "theme", title: String(localized: "Couleur du thème"), location: appearance, symbol: "paintpalette.fill", color: Color.spinlogPink,
                  destination: .appearance, keywords: ["thème", "theme", "couleur", "color", "palette"]),
            .init(id: "guide", title: String(localized: "Guide"), location: help, symbol: "book.fill", color: .indigo,
                  destination: .guide, keywords: ["aide", "help", "tutoriel", "tutorial", "comment", "fonctions"]),
            .init(id: "website", title: String(localized: "Site web Discogs"), location: about, symbol: "globe", color: .cyan,
                  destination: .about, keywords: ["discogs", "site", "web"]),
            .init(id: "subscription", title: String(localized: "Gérer mon abonnement"), location: about, symbol: "creditcard.fill", color: .indigo,
                  destination: .about, keywords: ["abonnement", "subscription", "premium", "facturation", "billing", "résilier", "cancel"]),
            .init(id: "version", title: String(localized: "Version"), location: about, symbol: "info.circle.fill", color: .brown,
                  destination: .about, keywords: ["version", "build"])
        ]
        return all.filter { isAuthenticated || !$0.requiresAccount }
    }

    static func results(for query: String, isAuthenticated: Bool, isPremium: Bool) -> [SettingsSearchEntry] {
        entries(isAuthenticated: isAuthenticated, isPremium: isPremium).filter {
            SettingsSearchMatcher.matches(query: query, haystack: [$0.title, $0.location] + $0.keywords)
        }
    }
}

/// Résultats de la recherche : une ligne par réglage, avec la page qui le contient.
struct SettingsSearchResultsView: View {
    let query: String

    @State private var authManager = DiscogsAuthManager.shared
    @State private var premiumStore = PremiumStore.shared

    var body: some View {
        let results = SettingsSearchIndex.results(
            for: query,
            isAuthenticated: authManager.isAuthenticated,
            isPremium: premiumStore.isPremium
        )
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(results) { entry in
                NavigationLink(value: entry.destination) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: entry.symbol, backgroundColor: entry.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .foregroundStyle(.primary)
                            Text(entry.location)
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .listRowSeparatorTint(Color.appSeparator)
        }
    }
}
