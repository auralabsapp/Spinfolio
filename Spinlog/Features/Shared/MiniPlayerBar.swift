import SwiftUI

/// Mini-lecteur audio façon Liquid Glass (iOS 26 / Apple Music), posé en accessoire bas du `TabView`.
/// Apparaît dès qu'un titre est en cours d'écoute, et adapte sa présentation à `tabViewBottomAccessoryPlacement` :
/// - `.expanded` (barre d'onglets taille normale) : carte flottante complète au-dessus de la barre
///   (pochette, titre/artiste, position/durée, barre de progression tactile).
/// - `.inline` (barre d'onglets réduite au swipe up) : version compacte intégrée dans la pilule réduite,
///   entre l'icône de l'onglet courant à gauche et l'icône de recherche à droite.
/// Un appui sur le mini-lecteur ouvre la fenêtre de lecture plein écran (`NowPlayingFullScreenView`),
/// d'où l'on peut rejoindre la vue (Release ou Master) où la lecture a été lancée.
struct MiniPlayerBar: View {
    /// Identifiant de la source de la transition zoom vers `NowPlayingFullScreenView`.
    static let transitionSourceID = "nowPlayingMiniPlayer"

    let transitionNamespace: Namespace.ID

    @State private var service = AppleMusicPlaybackService.shared
    private var activityManager = NowPlayingActivityManager.shared
    @State private var coordinator = TabNavigationCoordinator.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDraggingProgress = false
    @State private var scrubProgress: Double = 0.0

    /// Apparition du contenu (glisse depuis le bas en s'estompant et en rétrécissant ; simple fondu
    /// avec Réduire les animations), par exemple au passage d'Apple Music à une écoute sur platine.
    private var playerTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94))
    }

    /// Vrai dès qu'un titre Apple Music ou une écoute "platine" est active. Sert à piloter
    /// `tabViewBottomAccessory(isEnabled:)` sur le `TabView` racine.
    static var isActive: Bool {
        let service = AppleMusicPlaybackService.shared
        let activityManager = NowPlayingActivityManager.shared
        return (service.currentItem != nil && service.isPlaying)
            || (activityManager.activeReleaseId != nil && activityManager.isAnyPlaying)
    }

    /// Teinte gauche du dégradé, nettement plus lumineuse / pastel pour un contraste prononcé.
    private var progressStartColor: Color {
        Color.spinlogPurpleLight.mix(with: .white, by: colorScheme == .dark ? 0.40 : 0.50)
    }

    /// Album d'une écoute sur platine, tel qu'affiché.
    struct TurntableInfo: Equatable {
        let releaseId: Int
        let title: String?
        let artist: String?
        let coverURL: String?
    }

    // Dernier contenu affiché, figé à l'arrêt : l'accessoire est retiré d'un bloc, capsule et
    // contenu ensemble. Sans ça, le contenu se vidait (titre effacé, barre de progression masquée)
    // avant que la capsule ne disparaisse.
    @State private var frozenAppleItem: NowPlayingItem?
    @State private var frozenTime: TimeInterval = 0
    @State private var frozenDuration: TimeInterval = 0
    @State private var frozenTurntable: TurntableInfo?

    private var isAppleMusicLive: Bool { service.currentItem != nil && service.isPlaying }

    private var liveTurntable: TurntableInfo? {
        guard let releaseId = activityManager.activeReleaseId, activityManager.isAnyPlaying else { return nil }
        return TurntableInfo(
            releaseId: releaseId,
            title: activityManager.activeAlbumTitle,
            artist: activityManager.activeArtistName,
            coverURL: activityManager.activeCoverURL
        )
    }

    private var isLive: Bool { isAppleMusicLive || liveTurntable != nil }

    private var displayedDuration: TimeInterval {
        isAppleMusicLive ? service.totalDuration : frozenDuration
    }

    private var effectiveProgress: Double {
        if isDraggingProgress { return scrubProgress }
        guard isAppleMusicLive else { return frozenDuration > 0 ? min(frozenTime / frozenDuration, 1) : 0 }
        return service.playbackProgress
    }

    private var effectiveTime: TimeInterval {
        if isDraggingProgress { return scrubProgress * displayedDuration }
        return isAppleMusicLive ? service.playbackTime : frozenTime
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN, !time.isInfinite, time >= 0 else { return "0:00" }
        return Int(time).formattedAsMinutesSeconds
    }

    var body: some View {
        // Même branche pour le contenu en cours et le contenu figé : rien ne change à l'écran au
        // moment de l'arrêt, seul l'accessoire entier se retire (voir `RootTabView`).
        Group {
            if let item = isAppleMusicLive ? service.currentItem : frozenAppleItem {
                if accessoryPlacement == .inline {
                    compactAppleMusicPlayerView(item: item)
                } else {
                    appleMusicPlayerView(item: item)
                }
            } else if let info = liveTurntable ?? frozenTurntable {
                if accessoryPlacement == .inline {
                    compactTurntablePlayerView(info: info)
                } else {
                    turntablePlayerView(info: info)
                }
            }
        }
        // Figé, il ne répond plus (il n'y a plus rien à ouvrir ni à arrêter).
        .allowsHitTesting(isLive)
        // Source de la transition zoom : la fenêtre de lecture sort de ce mini-lecteur et y rentre.
        .matchedTransitionSource(id: Self.transitionSourceID, in: transitionNamespace)
        .onChange(of: service.currentItem, initial: true) { _, item in
            guard let item, service.isPlaying else { return }
            frozenAppleItem = item
            frozenTurntable = nil
        }
        .onChange(of: service.playbackTime) { _, time in
            // À l'arrêt, le temps repasse à 0 : seul le temps d'une lecture en cours est retenu.
            guard isAppleMusicLive else { return }
            frozenTime = time
            frozenDuration = service.totalDuration
        }
        .onChange(of: liveTurntable, initial: true) { _, info in
            guard let info else { return }
            frozenTurntable = info
            frozenAppleItem = nil
        }
    }

    // MARK: - Présentation compacte (barre d'onglets réduite)

    @ViewBuilder
    private func compactAppleMusicPlayerView(item: NowPlayingItem) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                AsyncCoverImage(
                    url: item.coverURL,
                    cornerRadius: 6,
                    showsBorder: true,
                    targetSize: 30
                )
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5)
                .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 0) {
                    AutoScrollingText(
                        text: item.trackTitle,
                        font: .subheadline.weight(.semibold),
                        color: .primary
                    )

                    AutoScrollingText(
                        text: appleMusicSubtitle(artist: item.artistName),
                        font: .caption,
                        color: Color.appSecondaryText
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.trackTitle), \(item.artistName), lecture sur Apple Music")
            .accessibilityHint("Ouvre le lecteur.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { coordinator.presentNowPlaying(.appleMusic) }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                service.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .expandedHitArea(visibleSide: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Arrêter la lecture")
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            coordinator.presentNowPlaying(.appleMusic)
        }
        .transition(playerTransition)
    }

    @ViewBuilder
    private func compactTurntablePlayerView(info: TurntableInfo) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                AsyncCoverImage(
                    url: info.coverURL,
                    cornerRadius: 6,
                    showsBorder: true,
                    targetSize: 30
                )
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5)
                .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 0) {
                    AutoScrollingText(
                        text: info.title ?? String(localized: "Album vinyle"),
                        font: .subheadline.weight(.semibold),
                        color: .primary
                    )

                    AutoScrollingText(
                        text: turntableSubtitle(artist: info.artist),
                        font: .caption,
                        color: Color.appSecondaryText
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(info.title ?? ""). Écoute en cours sur la platine")
            .accessibilityHint("Ouvre le lecteur.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { coordinator.presentNowPlaying(.turntable) }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    await activityManager.endCurrentActivity()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .expandedHitArea(visibleSide: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Arrêter l'écoute sur la platine")
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            coordinator.presentNowPlaying(.turntable)
        }
        .transition(playerTransition)
    }

    @ViewBuilder
    private func appleMusicPlayerView(item: NowPlayingItem) -> some View {
        ZStack(alignment: .bottom) {
                    // Contenu principal : parfaitement centré verticalement
                    HStack(spacing: 12) {
                        // Zone cliquable : Pochette + Textes + position temporelle (ramène à la vue source)
                        HStack(spacing: 12) {
                            // 1. Jaquette à gauche (légèrement réduite)
                            AsyncCoverImage(
                                url: item.coverURL,
                                cornerRadius: 7,
                                showsBorder: true,
                                targetSize: 36
                            )
                            .frame(width: 36, height: 36)
                            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5)
                            .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)

                            // 2. Titre et Artiste l'un en dessous de l'autre (avec défilement auto si trop long)
                            VStack(alignment: .leading, spacing: 0.5) {
                                AutoScrollingText(
                                    text: item.trackTitle,
                                    font: .subheadline.weight(.semibold),
                                    color: .primary
                                )

                                AutoScrollingText(
                                    text: appleMusicSubtitle(artist: item.artistName),
                                    font: .caption,
                                    color: Color.appSecondaryText
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offset(y: -2)

                            // 3. Position temporelle et durée juste à gauche du bouton pause (remontée également)
                            if displayedDuration > 0 {
                                Text("\(formatTime(effectiveTime)) / \(formatTime(displayedDuration))")
                                    .font(.caption)
                                    .foregroundStyle(isDraggingProgress ? .primary : Color.appSecondaryText)
                                    .monospacedDigit()
                                    .offset(y: -2)
                                    .animation(.easeInOut(duration: 0.15), value: isDraggingProgress)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.trackTitle), \(item.artistName), lecture sur Apple Music. \(formatTime(effectiveTime)) sur \(formatTime(displayedDuration))")
                        .accessibilityHint("Ouvre le lecteur.")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { coordinator.presentNowPlaying(.appleMusic) }

                        // 4. Bouton Stop à droite (cercle rose Spinlog avec icône stop.fill), identique au mode platine
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            service.stop()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.spinlogPink)
                                    .frame(width: 25, height: 25)

                                Image(systemName: "stop.fill")
                                    .font(.coverCornerBadge)
                                    .foregroundStyle(Color.white)
                            }
                            .frame(width: 36, height: 36)
                            .expandedHitArea(visibleSide: 36)
                        }
                        .buttonStyle(.plain)
                        .offset(y: -2)
                        .zIndex(2)
                        .accessibilityLabel("Arrêter la lecture")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        coordinator.presentNowPlaying(.appleMusic)
                    }

                    // 5. Barre de progression tactile alignée sur le bord inférieur (ne décale pas le contenu)
                    if displayedDuration > 0 {
                        GeometryReader { geo in
                            let width = geo.size.width
                            let progressWidth = max(0, min(width * CGFloat(effectiveProgress), width))

                            ZStack(alignment: .leading) {
                                // Zone tactile confortable pour le doigt
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 14)

                                // Rail d'arrière-plan
                                Capsule()
                                    .fill(Color.primary.opacity(0.12))
                                    .frame(height: isDraggingProgress ? 3.5 : 1.75)

                                // Remplissage actif (dégradé horizontal du clair vers le foncé)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [progressStartColor, Color.spinlogPurple, Color.spinlogPurpleDeep],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: progressWidth, height: isDraggingProgress ? 3.5 : 1.75)

                                // Curseur rond visible pendant le déplacement
                                if isDraggingProgress {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 8, height: 8)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.spinlogPurple, lineWidth: 1.5)
                                        )
                                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                                        .offset(x: max(0, min(progressWidth - 4, width - 8)))
                                }
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if !isDraggingProgress {
                                            isDraggingProgress = true
                                            UISelectionFeedbackGenerator().selectionChanged()
                                        }
                                        let ratio = max(0, min(Double(value.location.x / width), 1.0))
                                        scrubProgress = ratio
                                    }
                                    .onEnded { value in
                                        let ratio = max(0, min(Double(value.location.x / width), 1.0))
                                        let targetTime = ratio * service.totalDuration
                                        service.seek(to: targetTime)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            isDraggingProgress = false
                                        }
                                    }
                            )
                        }
                        .frame(height: 14)
                        // Le glissé n'existe pas pour VoiceOver : la barre devient un élément
                        // réglable (balayer vers le haut ou le bas avance ou recule de 15 s).
                        .accessibilityElement()
                        .accessibilityLabel("Position de lecture")
                        .accessibilityValue("\(formatTime(effectiveTime)) sur \(formatTime(displayedDuration))")
                        .accessibilityAdjustableAction { direction in
                            let step: TimeInterval = direction == .increment ? 15 : -15
                            service.seek(to: max(0, min(effectiveTime + step, service.totalDuration)))
                        }
                        .padding(.leading, 60)
                        .padding(.trailing, 16)
                        .padding(.bottom, 3)
                        .animation(.easeInOut(duration: 0.15), value: isDraggingProgress)
                    }
                }
        .transition(playerTransition)
    }

    @ViewBuilder
    private func turntablePlayerView(info: TurntableInfo) -> some View {
        HStack(spacing: 12) {
                // Zone combinée : Pochette + Textes (ramène à l'album vinyle)
                HStack(spacing: 12) {
                    // 1. Jaquette à gauche (36x36, coins arrondis 7)
                    AsyncCoverImage(
                        url: info.coverURL,
                        cornerRadius: 7,
                        showsBorder: true,
                        targetSize: 36
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5)
                    .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)

                    // 2. Titre de l'album et sous-titre "Écoute sur platine"
                    VStack(alignment: .leading, spacing: 0.5) {
                        AutoScrollingText(
                            text: info.title ?? String(localized: "Album vinyle"),
                            font: .subheadline.weight(.semibold),
                            color: .primary
                        )

                        AutoScrollingText(
                            text: turntableSubtitle(artist: info.artist),
                            font: .caption,
                            color: Color.appSecondaryText
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(info.title ?? ""), \(info.artist ?? ""). Écoute en cours sur la platine")
                .accessibilityHint("Ouvre le lecteur.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { coordinator.presentNowPlaying(.turntable) }

                // 3. Bouton Stop à droite (cercle rose Spinlog avec icône stop.fill)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        await activityManager.endCurrentActivity()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.spinlogPink)
                            .frame(width: 25, height: 25)

                        Image(systemName: "stop.fill")
                            .font(.coverCornerBadge)
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 36, height: 36)
                    .expandedHitArea(visibleSide: 36)
                }
                .buttonStyle(.plain)
                .zIndex(2)
                .accessibilityLabel("Arrêter l'écoute sur la platine")
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                coordinator.presentNowPlaying(.turntable)
            }
        .transition(playerTransition)
    }

    private func appleMusicSubtitle(artist: String) -> String {
        if !artist.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "\(artist) • Lecture sur Apple Music")
        } else {
            return String(localized: "Lecture sur Apple Music")
        }
    }

    private func turntableSubtitle(artist: String?) -> String {
        if let artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "\(artist) • Écoute sur platine")
        } else {
            return String(localized: "Écoute sur platine")
        }
    }
}
