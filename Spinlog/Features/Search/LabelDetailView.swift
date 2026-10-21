import SwiftUI

struct LabelDetailView: View {
    /// Partagée entre la vraie pochette et `labelDetailSkeleton`, pour que le squelette ne puisse
    /// pas diverger silencieusement de la taille réelle.
    private static let coverSize: CGFloat = 200

    let labelId: Int

    @State private var viewModel = LabelDetailViewModel()

    var body: some View {
        content
            .background(Color.appBackground.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
            .navigationTitle(viewModel.label?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .disablesContentPopGesture()
            .task { await viewModel.loadIfNeeded(labelId: labelId) }
            // Seul des 4 écrans de détail (Release/Artist/Master/Label) à ne pas s'enregistrer
            // auprès de `TabNavigationCoordinator` : sa déduplication de navigation (ex: ne pas
            // repousser la même destination si elle est déjà au sommet de la pile) ne fonctionnait
            // donc pas quand une fiche label était au sommet.
            .onAppear {
                TabNavigationCoordinator.shared.registerTopDestination(.label(labelId))
            }
            .onDisappear {
                TabNavigationCoordinator.shared.unregisterTopDestination(.label(labelId))
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            labelDetailSkeleton
                .transition(.opacity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Impossible de charger ce label", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Réessayer") {
                    Task { await viewModel.load(labelId: labelId) }
                }
                .buttonStyle(.glassProminent)
            }
        } else if let label = viewModel.label {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AsyncCoverImage(url: label.primaryImageURL)
                        .frame(width: Self.coverSize, height: Self.coverSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
                        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 10)
                        .frame(maxWidth: .infinity)

                    Text(label.name).font(.title2.bold())

                    if let profile = label.profile, !profile.isEmpty {
                        Text(profile).font(.body)
                    }

                    if let url = label.discogsWebURL {
                        DiscogsAttributionLink(url: url)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding()
            }
            .transition(.opacity)
        }
    }

    /// Gabarit neutre affiché pendant le chargement, à la place d'une icône de chargement :
    /// reproduit la structure réelle (pochette centrée, nom, paragraphe de profil) avec des
    /// blocs animés (voir `SkeletonBlock`), pour que l'apparition du contenu réel ne fasse pas
    /// sauter la page.
    private var labelDetailSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SkeletonBlock(cornerRadius: 8, width: Self.coverSize, height: Self.coverSize)
                    .frame(maxWidth: .infinity)

                SkeletonBlock(width: 180, height: 22)

                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(height: 14)
                    SkeletonBlock(height: 14)
                    SkeletonBlock(width: 220, height: 14)
                }
            }
            .padding()
        }
        .scrollDisabled(true)
    }
}
