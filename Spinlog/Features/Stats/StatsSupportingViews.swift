import SwiftUI

/// Feuilles de détail (par genre, support, artiste, année) et carte de compteur de
/// l'onglet Stats — extrait de StatsView.swift, voir le commentaire sur `StatsChartsView`.
/// `internal` (et non `private`) car instanciées depuis `StatsView.content`/`countersRow`,
/// dans un autre fichier.
struct GenreReleasesSheetView: View {
    let data: GenreReleasesSheetData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if data.items.isEmpty {
                    ContentUnavailableView(
                        "Aucun élément",
                        systemImage: "opticaldisc",
                        description: Text("Aucun album trouvé pour ce genre.")
                    )
                } else {
                    List {
                        ForEach(data.items) { item in
                            NavigationLink(value: SearchDestination.release(
                                item.releaseId,
                                coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
                            )) {
                                CollectionRow(item: item)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listRowSeparatorTint(Color.appSeparator)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("\(data.genre) · \(data.items.count) albums")
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }
}

struct MediaFormatReleasesSheetView: View {
    let data: MediaFormatReleasesSheetData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if data.items.isEmpty {
                    ContentUnavailableView(
                        "Aucun élément",
                        systemImage: "opticaldisc",
                        description: Text("Aucun album trouvé pour ce support.")
                    )
                } else {
                    List {
                        ForEach(data.items) { item in
                            NavigationLink(value: SearchDestination.release(
                                item.releaseId,
                                coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
                            )) {
                                CollectionRow(item: item)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listRowSeparatorTint(Color.appSeparator)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("\(data.title) · \(data.items.count) albums")
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }
}

struct ArtistReleasesSheetView: View {
    let data: ArtistReleasesSheetData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if data.items.isEmpty {
                    ContentUnavailableView(
                        "Aucun élément",
                        systemImage: "opticaldisc",
                        description: Text("Aucun album trouvé pour cet artiste.")
                    )
                } else {
                    List {
                        ForEach(data.items) { item in
                            NavigationLink(value: SearchDestination.release(
                                item.releaseId,
                                coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
                            )) {
                                CollectionRow(item: item)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listRowSeparatorTint(Color.appSeparator)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("\(data.artist) · \(data.items.count) albums")
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                // Même titre, mais le nom de l'artiste ouvre sa fiche (dans la pile de la feuille,
                // comme les albums de la liste).
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        ArtistNameLinks(
                            artists: data.artists,
                            fallback: data.artist,
                            displayName: { ArtistShelfSortHelper.cleanDiscogsSuffix($0.name) }
                        )
                        .foregroundStyle(Color.spinlogPink)
                        Text(verbatim: " · ")
                        Text("\(data.items.count) albums")
                    }
                    .font(.headline)
                    .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }
}

struct YearReleasesSheetView: View {
    let data: YearReleasesSheetData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if data.items.isEmpty {
                    ContentUnavailableView(
                        "Aucun élément",
                        systemImage: "opticaldisc",
                        description: Text("Aucun élément trouvé pour cette année.")
                    )
                } else {
                    List {
                        ForEach(data.items) { item in
                            NavigationLink(value: SearchDestination.release(
                                item.releaseId,
                                coverURL: item.basicInformation.coverImage ?? item.basicInformation.thumb
                            )) {
                                CollectionRow(item: item)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listRowSeparatorTint(Color.appSeparator)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(Text("\(data.title) · \(data.items.count) éléments"))
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
    }
}

struct StatCounterCard: View {
    let title: LocalizedStringResource
    let value: String
    var subtitle: String? = nil
    let systemImage: String
    let tint: Color
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    /// Contenu partagé entre la variante cliquable (dans un `Button`) et la variante
    /// purement informative (sans action), pour que cette dernière garde ses couleurs
    /// pleines — un `Button` désactivé via `.disabled()` atténue automatiquement son
    /// contenu, ce qu'on ne veut pas ici puisque ce n'est pas un état "indisponible".
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                Spacer()
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }

            Text(value)
                .font(.title.bold())
                .monospacedDigit()

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
            }
        }
        // `maxHeight: .infinity` : sans ça, une carte dont le `subtitle` n'est pas encore connu
        // (ex: compteur encore en cours de chargement) est plus courte que ses voisines et se
        // retrouve centrée verticalement dans la rangée au lieu d'avoir le même fond que les 2
        // autres — `alignment: .top` garde le contenu collé en haut une fois la carte étirée.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .appleMusicGroupedCard()
    }
}
