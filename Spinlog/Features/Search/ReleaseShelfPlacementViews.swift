import SwiftUI

/// Emplacement physique dans le meuble, sur la fiche disque.
/// En mode non-premium, affiche une carte verrouillée identique au compteur de lectures.
/// `release` est `nil` quand le rangement est ambigu (exemplaires répartis dans plusieurs
/// dossiers, restriction active — voir `ReleaseDetailView.commonInstanceFolderRelease`) : la
/// bannière reste affichée mais devient non cliquable, avec un sous-titre invitant à balayer
/// l'exemplaire concerné dans « Mes exemplaires » plutôt que de lancer un rangement arbitraire.
struct ReleaseShelfPlacementRow: View {
    let release: Release?
    let onOpen: (Release) -> Void

    @State private var premiumStore = PremiumStore.shared

    var body: some View {
        if !premiumStore.isPremium {
            PremiumLockedCard(
                icon: "books.vertical.fill",
                title: "Emplacement de cet album",
                message: "Passe premium pour savoir instantanément où intercaler cet album dans ton meuble."
            )
        } else if let release {
            Button {
                onOpen(release)
            } label: {
                content(
                    subtitle: "Voir sa place exacte entre ses deux voisins",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        } else {
            content(
                subtitle: SwipeActionsSupport.isAvailable
                    ? String(localized: "Balaie l'exemplaire concerné vers la gauche dans « Mes exemplaires » pour voir où le ranger")
                    : String(localized: "Maintiens le doigt sur l'exemplaire concerné dans « Mes exemplaires » pour voir où le ranger"),
                showsChevron: false
            )
        }
    }

    private func content(subtitle: String, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.title3)
                .foregroundStyle(Color.spinlogPink)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Emplacement de cet album")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    DemoPremiumBadge()
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.appSecondaryText)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.appTertiaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appleMusicGroupedCard()
    }
}

/// Encart de confirmation affiché juste après l'ajout à la collection, avec l'accès direct au
/// guide de rangement. `fallback` (la release générique, sans dossier) n'est utilisée que si
/// l'exemplaire qui vient d'être ajouté n'est, improbablement, pas encore retrouvable dans
/// `actions.collectionInstances` — sinon ce dernier porte le vrai dossier choisi, indispensable
/// pour un rangement restreint au dossier.
struct ReleasePostAddShelfPlacementCard: View {
    let fallback: Release
    let actions: ReleaseActions
    let onOpenShelfPlacement: (Release) -> Void

    @State private var premiumStore = PremiumStore.shared

    var body: some View {
        let targetRelease: Release
        if let lastInstance = actions.collectionInstances.last {
            targetRelease = Release(from: lastInstance)
        } else {
            targetRelease = fallback
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ajouté à ta collection !")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation {
                        actions.justAddedReleaseId = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.appSecondaryText)
                        .padding(6)
                }
                .accessibilityLabel("Masquer ce message")
            }

            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "books.vertical.fill",
                    title: "Emplacement de cet album",
                    message: "Passe premium pour savoir instantanément où intercaler cet album dans ton meuble."
                )
            } else {
                HStack(spacing: 5) {
                    Text("\(AppInfo.name) a déterminé l'emplacement exact de cet album dans ton meuble.")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                    DemoPremiumBadge()
                }

                Button {
                    // Masque l'encart "Ajouté à ta collection !" : une fois qu'on a demandé
                    // l'emplacement, ce rappel n'a plus d'utilité et ne doit pas rester affiché
                    // derrière la feuille de rangement (ni persister une fois celle-ci refermée).
                    withAnimation {
                        actions.justAddedReleaseId = nil
                    }
                    onOpenShelfPlacement(targetRelease)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical.fill")
                        Text("Emplacement de cet album")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.spinlogPink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .appleMusicGroupedCard()
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.spinlogPink.opacity(0.35), lineWidth: 1)
        )
        .motionTransition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
