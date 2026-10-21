import SwiftUI
import Kingfisher

/// Identifie l'URL à ouvrir dans Safari : un simple `Bool` + `URL?` séparés provoquerait une
/// fenêtre Safari vide (la feuille peut s'instancier avant que l'URL associée soit commise),
/// donc on unifie présentation et contenu dans une seule valeur `Identifiable` via `.sheet(item:)`.
private struct SafariTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Vue (poussée dans la pile de navigation de Réglages) affichant l'intégralité des données du
/// profil utilisateur Discogs : Identité & Contact, Statistiques d'activité et données Marketplace.
struct UserProfileSheet: View {
    let username: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var viewModel = UserProfileViewModel()
    @State private var safariTarget: SafariTarget?
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingLogoutConfirmation = false

    var body: some View {
        content
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Profil Discogs")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load(username: username) }
            .sheet(item: $safariTarget) { target in
                SafariView(url: target.url)
            }
            .confirmationDialog("Se déconnecter", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) {
                    DiscogsAuthManager.shared.logout()
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Veux-tu vraiment te déconnecter de ton compte Discogs ?")
            }
            .confirmationDialog(
                "Supprimer le compte Discogs",
                isPresented: $showingDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer le compte sur Discogs.com", role: .destructive) {
                    safariTarget = SafariTarget(url: DiscogsConstants.accountDeletionURL)
                }
                Button("Effacer les données locales & iCloud et se déconnecter", role: .destructive) {
                    DiscogsAuthManager.shared.deleteLocalAccountData()
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ton compte est géré par Discogs. Pour supprimer définitivement ton compte et l'ensemble de tes données, tu dois finaliser la demande sur le site officiel de Discogs.\n\nTu peux également effacer immédiatement toutes les données stockées par l'application sur cet appareil et synchronisées sur iCloud (tags, historique d'écoute, préférences).")
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Indisponible", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Réessayer") {
                    Task { await viewModel.load(username: username) }
                }
                .buttonStyle(.glassProminent)
            }
        } else if let profile = viewModel.profile {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(for: profile)

                    // 1. Identité & Contact
                    if !viewModel.identityItems(for: profile).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionEyebrow(title: "Identité & Contact")
                            infoCard(viewModel.identityItems(for: profile))
                        }
                    }

                    // Biographie si renseignée
                    if let bio = profile.profile, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionEyebrow(title: "Biographie")
                            Text(bio)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // 2. Statistiques d'activité
                    if !viewModel.activityItems(for: profile).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionEyebrow(title: "Statistiques d'activité")
                            infoCard(viewModel.activityItems(for: profile))
                        }
                    }

                    // 3. Marketplace
                    if !viewModel.marketplaceItems(for: profile).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionEyebrow(title: "Marketplace")
                            infoCard(viewModel.marketplaceItems(for: profile))
                        }
                    }

                    // Lien vers la page Web Discogs
                    if let profileURL = viewModel.profileURL {
                        Button {
                            safariTarget = SafariTarget(url: profileURL)
                        } label: {
                            HStack {
                                Spacer()
                                Label("Voir le profil sur Discogs.com", systemImage: "safari")
                                    .font(.subheadline.bold())
                                Spacer()
                            }
                            .padding(.vertical, 14)
                        }
                        .appleMusicGroupedCard()
                    }

                    // Déconnexion, au-dessus de la suppression de compte
                    Button {
                        showingLogoutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Se déconnecter")
                                .font(.subheadline.bold())
                            Spacer()
                        }
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .appleMusicGroupedCard()

                    // Bouton de suppression de compte (Guideline Apple 5.1.1(v))
                    VStack(alignment: .leading, spacing: 8) {
                        Button(role: .destructive) {
                            showingDeleteAccountConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Supprimer mon compte...", systemImage: "trash")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.vertical, 14)
                        }
                        .appleMusicGroupedCard()

                        Text("Ton compte est hébergé sur Discogs. Tu peux lancer la suppression définitive de ton compte ou effacer les données locales et synchronisées sur iCloud (tags, historique d'écoute, préférences).")
                            .font(.footnote)
                            .foregroundStyle(Color.appSecondaryText)
                            .padding(.horizontal, 4)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Header

    private func header(for profile: DiscogsUserProfile) -> some View {
        HStack(spacing: 16) {
            if let avatarURLString = profile.avatarURL, let avatarURL = URL(string: avatarURLString), !avatarURLString.isEmpty {
                KFImage(avatarURL)
                    .placeholder { avatarPlaceholder }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 68, height: 68)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            } else {
                avatarPlaceholder
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name?.isEmpty == false ? profile.name! : profile.username)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text("@\(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)

                    Text("·")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTertiaryText)

                    Text("ID: \(profile.id)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.appSecondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            Spacer()
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.spinlogPink.opacity(0.85), Color.spinlogPink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 68, height: 68)
            Image(systemName: "person.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Helpers

    /// Carte regroupant plusieurs `UserProfileInfoItem`, avec un filet fin entre chaque ligne
    /// (jamais avant la première ni après la dernière).
    private func infoCard(_ items: [UserProfileInfoItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                infoRow(item)
                if index < items.count - 1 {
                    Divider().overlay(Color.appSeparator).opacity(0.15).padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func infoRow(_ item: UserProfileInfoItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.subheadline)
                .foregroundStyle(Color.spinlogPink)
                .frame(width: 20)
            Text(item.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            if let url = item.url {
                Button {
                    // Site personnel indiqué dans le profil : ouvert dans Safari, pas dans la
                    // webview qui garde la session discogs.com (voir `DiscogsWebPolicy`).
                    if DiscogsWebPolicy.isDiscogs(url) {
                        safariTarget = SafariTarget(url: url)
                    } else {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(item.value)
                            .font(.subheadline)
                            .foregroundStyle(Color.spinlogPink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .foregroundStyle(Color.spinlogPink)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(item.value)
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
