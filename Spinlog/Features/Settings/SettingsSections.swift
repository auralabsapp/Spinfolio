import SwiftUI
import Kingfisher

/// Sections autonomes de `SettingsView`, extraites car elles ne dépendent que de stores partagés
/// (aucun état local de l'écran) — les sections qui partagent l'état chargé par `SettingsView`
/// (dossiers, champs de suivi de cote, export, confirmations) y restent.

/// Icône d'option de réglage dans un carré arrondi coloré (standard Apple Settings / HIG).
struct SettingsIcon: View {
    let systemName: String
    let backgroundColor: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(backgroundColor)
            )
    }
}

// MARK: - Compte Discogs

struct SettingsAccountSection: View {
    @State private var authManager = DiscogsAuthManager.shared
    @State private var safariRequest: SafariViewRequest?

    var body: some View {
        Section {
            if authManager.isDemoMode {
                demoAccountRows
            } else if authManager.isAuthenticated {
                NavigationLink(value: authManager.username.map { SettingsDestination.userProfile(username: $0) }) {
                    HStack(spacing: 14) {
                        if let avatarURLString = authManager.avatarURL,
                           let avatarURL = URL(string: avatarURLString) {
                            KFImage(avatarURL)
                                .placeholder {
                                    defaultAvatarPlaceholder
                                }
                                .fade(duration: 0.2)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 54, height: 54)
                                .clipShape(Circle())
                        } else {
                            defaultAvatarPlaceholder
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(authManager.username ?? "Utilisateur")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                Text("Connecté à Discogs")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                        }

                        Spacer()

                        GradeInlineBadges()
                    }
                    .padding(.vertical, 4)
                }

                NavigationLink(value: SettingsDestination.grades) {
                    GradeSummaryRow()
                }

            } else {
                Button {
                    Task { await authManager.login() }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "person.crop.circle.badge.plus", backgroundColor: .blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Se connecter à Discogs")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Synchronise ta collection et tes souhaits")
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }

                        Spacer()

                        if authManager.isAuthenticating {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.appTertiaryText)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .disabled(authManager.isAuthenticating)

                // Même page d'inscription que l'écran de connexion (`LoginPromptView`).
                Button {
                    safariRequest = SafariViewRequest(url: DiscogsConstants.accountCreationURL)
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "person.badge.plus", backgroundColor: .green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pas de compte ? Crée-en un")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Inscription gratuite sur Discogs, puis connecte-toi ci-dessus")
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.appTertiaryText)
                    }
                    .padding(.vertical, 2)
                }
                .disabled(authManager.isAuthenticating)

                Button {
                    authManager.startDemo()
                } label: {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "sparkles.rectangle.stack", backgroundColor: .purple)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Explorer avec une collection de démo")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Découvre l'app et ses fonctions Premium, sans compte Discogs")
                                .font(.caption)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .disabled(authManager.isAuthenticating)

                if let error = authManager.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            SectionEyebrow(title: "Compte Discogs", icon: "person.crop.circle.fill")
        } footer: {
            if authManager.isDemoMode {
                Text("Les données affichées sont des exemples et les modifications vers Discogs sont désactivées. Les fonctions Premium sont offertes pendant la démo. Connecte ton compte pour retrouver ta propre collection.")
            } else if authManager.isAuthenticated {
                Text("Gère ton profil Discogs.")
            }
        }
        .sheet(item: $safariRequest) { request in
            SafariView(url: request.url)
        }
    }

    /// Démo : pas de profil Discogs à consulter (le compte n'existe pas), mais un accès direct
    /// à la connexion d'un vrai compte, qui quitte la démo au passage.
    @ViewBuilder
    private var demoAccountRows: some View {
        HStack(spacing: 14) {
            defaultAvatarPlaceholder

            VStack(alignment: .leading, spacing: 3) {
                Text("Collection de démo")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                    Text("Mode démo")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)

        // Signale l'aperçu Premium de la démo : sans cette mention, les fonctions Premium
        // débloquées sans abonnement pouvaient laisser croire à un abonnement actif.
        if PremiumStore.shared.isDemoPreview && !PremiumStore.shared.hasSubscription {
            HStack(alignment: .top, spacing: 14) {
                SettingsIcon(systemName: "crown.fill", backgroundColor: Color.goldWarm)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aperçu Premium (mode démo)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.goldText)
                    Text("Toutes les fonctions Premium sont débloquées pendant la démo, sans abonnement ni achat. Elles se verrouillent en quittant le mode démo.")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }

        Button {
            Task { await authManager.login() }
        } label: {
            HStack(spacing: 14) {
                SettingsIcon(systemName: "person.crop.circle.badge.plus", backgroundColor: .blue)
                Text("Se connecter à Discogs")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if authManager.isAuthenticating {
                    ProgressView()
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(authManager.isAuthenticating)
    }

    private var defaultAvatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.spinlogPink.opacity(0.85), Color.spinlogPink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 54, height: 54)

            Image(systemName: "person.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Écoute & Live Activity

struct SettingsListeningSection: View {
    @State private var appearancePreferences = AppearancePreferencesStore.shared

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { Int(appearancePreferences.maxListeningDuration) },
                set: { appearancePreferences.maxListeningDuration = Double($0) }
            )) {
                ForEach(ListeningMaxDurationOption.allCases) { option in
                    Text(option.label)
                        .tag(option.rawValue)
                }
            } label: {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "timer", backgroundColor: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Arrêt automatique de l'écoute")
                            .foregroundStyle(.primary)
                        Text("Durée maximale de la Live Activity")
                            .font(.caption2)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            }
            .pickerStyle(.menu)
            .tint(Color.spinlogPink)
        } header: {
            SectionEyebrow(title: "Écoute sur platine & Live Activity", icon: "opticaldisc.fill")
        } footer: {
            Text("L'écoute sur platine s'arrête automatiquement après cette durée. En lancer une nouvelle interrompt immédiatement l'album en cours.")
        }
    }
}

// MARK: - Apple Music

struct SettingsAppleMusicSection: View {
    @State private var appleMusicAccount = AppleMusicAccountStore.shared

    var body: some View {
        Section {
            Toggle(isOn: $appleMusicAccount.isConnected) {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "music.note", backgroundColor: .pink)
                    Text("Connecter mon compte Apple Music")
                        .foregroundStyle(.primary)
                }
            }
            .tint(Color.spinlogPink)

            if appleMusicAccount.status != .disconnected {
                statusRow(appleMusicAccount.status)
            }
        } header: {
            SectionEyebrow(title: "Apple Music", icon: "music.note")
        } footer: {
            Text("Permet de lire les titres en entier depuis une fiche album avec un abonnement Apple Music actif. Sans connexion, un extrait de 30 s reste disponible. Ces lectures ne comptent pas comme des écoutes sur platine.")
        }
        // L'état du compte apparaît et change en fondu.
        .animatesSettingsChanges(value: appleMusicAccount.status)
        // L'abonnement a pu changer depuis la dernière vérification (souscription dans l'app Musique).
        .task { await appleMusicAccount.refreshStatus() }
    }

    /// Icône + texte (jamais la couleur seule) : l'abonnement est actif ou non, ou en cours de vérification.
    @ViewBuilder
    private func statusRow(_ status: AppleMusicAccountStatus) -> some View {
        HStack(spacing: 8) {
            switch status {
            case .disconnected:
                EmptyView()
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("Vérification de l'abonnement…")
            case .denied:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.appWarning)
                Text("Accès à Apple Music refusé : autorise-le pour \(AppInfo.name) dans les réglages de l'iPhone.")
            case .noSubscription:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.appWarning)
                Text("Aucun abonnement Apple Music actif : seuls les extraits de 30 s sont lus.")
            case .active:
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.gainPositive)
                Text("Abonnement Apple Music actif : lecture complète des titres.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.appSecondaryText)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Données hors ligne

struct SettingsOfflineSection: View {
    @State private var premiumStore = PremiumStore.shared

    var body: some View {
        Section {
            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "arrow.down.circle.fill",
                    title: "Mode hors ligne",
                    message: "Passe premium pour consulter toute ta collection et les pochettes sans réseau en brocante."
                )
            } else {
                NavigationLink(value: SettingsDestination.offline) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "arrow.down.circle.fill", backgroundColor: .teal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Mode hors ligne")
                                .foregroundStyle(.primary)
                            if let date = OfflineDownloadManager.shared.lastSyncDate {
                                Text("Synchronisé le \(formattedOfflineDate(date)) (\(OfflineDownloadManager.shared.offlineItemCount) albums)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appSecondaryText)
                            } else {
                                Text("Aucune archive locale complète")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                        }
                    }
                }
            }
        } header: {
            SectionEyebrow(title: "Données hors ligne", icon: "arrow.down.circle.fill", isPremiumFeature: true)
        } footer: {
            Text("Télécharge l'ensemble de ta collection et les pochettes d'albums sur ton appareil pour les consulter partout sans connexion Internet.")
        }
    }

    private func formattedOfflineDate(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }
}

// MARK: - Apparence

struct SettingsAppearanceSection: View {
    @State private var appearancePreferences = AppearancePreferencesStore.shared
    @State private var themeManager = ThemeManager.shared
    @State private var premiumStore = PremiumStore.shared

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { appearancePreferences.appearance.rawValue },
                set: { raw in
                    if let theme = AppTheme(rawValue: raw) {
                        appearancePreferences.appearance = theme
                    }
                }
            )) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme.rawValue)
                }
            } label: {
                HStack(spacing: 14) {
                    SettingsIcon(systemName: "circle.lefthalf.filled", backgroundColor: .indigo)
                    Text("Mode d'affichage")
                }
            }
            .pickerStyle(.menu)
            .tint(Color.spinlogPink)

            if !premiumStore.isPremium {
                PremiumLockedCard(
                    icon: "paintpalette.fill",
                    title: "Couleur du thème",
                    message: "Passe premium pour choisir parmi les 9 palettes de thèmes exclusives."
                )
            } else {
                NavigationLink(value: SettingsDestination.colorTheme) {
                    HStack(spacing: 14) {
                        SettingsIcon(systemName: "paintpalette.fill", backgroundColor: themeManager.currentTheme.primaryColor)
                        Text("Couleur du thème")
                        DemoPremiumBadge()
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(themeManager.currentTheme.primaryColor)
                                .frame(width: 12, height: 12)
                            Text(themeManager.currentTheme.displayName)
                                .font(.subheadline)
                                .foregroundStyle(Color.appSecondaryText)
                        }
                    }
                }
            }
        } header: {
            SectionEyebrow(title: "Apparence", icon: "paintbrush.fill")
        }
    }
}
