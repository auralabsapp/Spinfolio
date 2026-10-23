import SwiftUI

/// Enveloppe commune des sous-pages de Réglages : une liste groupée sur le fond de l'app, titre
/// compact. Les sections qu'elle reçoit sont celles de l'ancienne page unique, déplacées telles quelles.
struct SettingsSubPage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        List {
            content()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .listRowSeparatorTint(Color.appSeparator)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Ligne d'entrée de l'écran d'accueil de Réglages : icône, titre, résumé en gris, et la pastille
/// Premium de la démo quand la page est une fonction Premium.
struct SettingsHubRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    var subtitle: String? = nil
    var isPremiumFeature = false

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(systemName: icon, backgroundColor: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if isPremiumFeature {
                        DemoPremiumBadge()
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pages d'enveloppe (sections existantes, inchangées)

struct ListeningSettingsPage: View {
    var body: some View {
        SettingsSubPage(title: "Écoute et Apple Music") {
            SettingsListeningSection()
            SettingsAppleMusicSection()
        }
    }
}

struct ICloudSettingsPage: View {
    var body: some View {
        SettingsSubPage(title: "Synchronisation iCloud") {
            SettingsICloudSyncSection()
        }
    }
}

/// Page « Données hors ligne » pour un compte non Premium : la carte qui présente la fonction.
struct OfflineLockedSettingsPage: View {
    var body: some View {
        SettingsSubPage(title: "Données hors ligne") {
            SettingsOfflineSection()
        }
    }
}

struct AppearanceSettingsPage: View {
    var body: some View {
        SettingsSubPage(title: "Apparence") {
            SettingsAppearanceSection()
        }
    }
}
