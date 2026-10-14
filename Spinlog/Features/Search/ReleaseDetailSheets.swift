import SwiftUI

/// Feuilles modales (infos complémentaires, médias) de la fiche release — extrait de
/// ReleaseDetailView.swift (1153 lignes à l'origine) pour isoler cette responsabilité.
/// Feuille modale (bottom sheet) regroupant les données complémentaires de la release
struct ReleaseOtherInfoSheet: View {
    let release: Release

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let credits = release.extraartists, !credits.isEmpty {
                        CreditsSection(credits: credits)
                    }

                    if let companies = release.companies, !companies.isEmpty {
                        ReleaseCompaniesSection(companies: companies)
                    }

                    if let identifiers = release.identifiers, !identifiers.isEmpty {
                        ReleaseIdentifiersSection(identifiers: identifiers)
                    }
                }
                .padding()
            }
            .navigationTitle("Autres informations")
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Feuille modale (bottom sheet) regroupant les photos et vidéos de la release.
/// Le visualiseur plein écran est présenté ici même (imbriqué), et non depuis la vue racine :
/// deux présentations modales déclenchées comme frères l'une de l'autre (sheet + fullScreenCover
/// tous deux attachés à `ReleaseDetailView`) entrent en conflit quand la seconde est déclenchée
/// alors que la première est déjà affichée — la mise en plein écran restait alors silencieusement
/// sans effet.
struct ReleaseMediaSheet: View {
    let images: [DiscogsImage]?
    let videos: [ReleaseVideo]?

    @State private var imageViewerRequest: ImageViewerRequest?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let images, images.count > 1 {
                        ReleaseImagesGallery(images: images, onSelect: { index in
                            imageViewerRequest = ImageViewerRequest(startIndex: index)
                        })
                    }

                    if let videos, !videos.isEmpty {
                        ReleaseVideosSection(videos: videos)
                    }
                }
                .padding()
            }
            .navigationTitle("Photos et vidéos")
            .navigationBarTitleDisplayMode(.inline)
            .searchDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton()
                }
            }
        }
        .fullScreenCover(item: $imageViewerRequest) { request in
            ImageViewerView(images: images ?? [], startIndex: request.startIndex)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
