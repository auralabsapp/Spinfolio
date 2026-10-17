import SwiftUI

/// Mini-lecteur audio façon Liquid Glass (iOS 26 / Apple Music), posé en accessoire bas du `TabView`.
/// Apparaît dès qu'un titre est en cours d'écoute, et adapte sa présentation à `tabViewBottomAccessoryPlacement` :
/// - `.expanded` (barre d'onglets taille normale) : carte flottante complète au-dessus de la barre
///   (pochette, titre/artiste, position/durée, barre de progression tactile).
/// - `.inline` (barre d'onglets réduite au swipe up) : version compacte intégrée dans la pilule réduite,
///   entre l'icône de l'onglet courant à gauche et l'icône de recherche à droite.
/// Un appui sur le mini-lecteur ramène immédiatement l'utilisateur sur la vue (Release ou Master)
/// d'où la lecture a été lancée.
struct MiniPlayerBar: View {
    @State private var service = AppleMusicPlaybackService.shared
    private var activityManager = NowPlayingActivityManager.shared
    @State private var coordinator = TabNavigationCoordinator.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement

    @State private var isDraggingProgress = false
    @State private var scrubProgress: Double = 0.0

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

    private var effectiveProgress: Double {
        isDraggingProgress ? scrubProgress : service.playbackProgress
    }

    private var effectiveTime: TimeInterval {
        isDraggingProgress ? (scrubProgress * service.totalDuration) : service.playbackTime
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN, !time.isInfinite, time >= 0 else { return "0:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        if let item = service.currentItem, service.isPlaying {
            if accessoryPlacement == .inline {
                compactAppleMusicPlayerView(item: item)
            } else {
                appleMusicPlayerView(item: item)
            }
        } else if let releaseId = activityManager.activeReleaseId, activityManager.isAnyPlaying {
            if accessoryPlacement == .inline {
                compactTurntablePlayerView(releaseId: releaseId)
            } else {
                turntablePlayerView(releaseId: releaseId)
            }
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
            .accessibilityLabel("\(item.trackTitle), \(item.artistName), lecture sur Apple Music. Touche pour ouvrir l'album.")
            .accessibilityAddTraits(.isButton)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                service.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mettre en pause et fermer le lecteur")
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            coordinator.returnToPlayingItem(item)
        }
    }

    @ViewBuilder
    private func compactTurntablePlayerView(releaseId: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                AsyncCoverImage(
                    url: activityManager.activeCoverURL,
                    cornerRadius: 6,
                    showsBorder: true,
                    targetSize: 30
                )
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5)
                .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 0) {
                    AutoScrollingText(
                        text: activityManager.activeAlbumTitle ?? String(localized: "Album vinyle"),
                        font: .subheadline.weight(.semibold),
                        color: .primary
                    )

                    AutoScrollingText(
                        text: turntableSubtitle(artist: activityManager.activeArtistName),
                        font: .caption,
                        color: Color.appSecondaryText
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(activityManager.activeAlbumTitle ?? ""). Écoute en cours sur la platine. Touche pour ouvrir l'album.")
            .accessibilityAddTraits(.isButton)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    await activityManager.endCurrentActivity()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.spinlogPink)
                    .contentShape(Rectangle())
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
            coordinator.returnToRelease(releaseId: releaseId, coverURL: activityManager.activeCoverURL)
        }
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
                            if service.totalDuration > 0 {
                                Text("\(formatTime(effectiveTime)) / \(formatTime(service.totalDuration))")
                                    .font(.caption)
                                    .foregroundStyle(isDraggingProgress ? .primary : Color.appSecondaryText)
                                    .monospacedDigit()
                                    .offset(y: -2)
                                    .animation(.easeInOut(duration: 0.15), value: isDraggingProgress)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.trackTitle), \(item.artistName), lecture sur Apple Music. \(formatTime(effectiveTime)) sur \(formatTime(service.totalDuration)). Touche pour ouvrir l'album.")
                        .accessibilityAddTraits(.isButton)

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
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(y: -2)
                        .zIndex(2)
                        .accessibilityLabel("Mettre en pause et fermer le lecteur")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        coordinator.returnToPlayingItem(item)
                    }

                    // 5. Barre de progression tactile alignée sur le bord inférieur (ne décale pas le contenu)
                    if service.totalDuration > 0 {
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
                        .padding(.leading, 60)
                        .padding(.trailing, 16)
                        .padding(.bottom, 3)
                        .animation(.easeInOut(duration: 0.15), value: isDraggingProgress)
                    }
                }
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
                removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94))
            )
        )
    }

    @ViewBuilder
    private func turntablePlayerView(releaseId: Int) -> some View {
        HStack(spacing: 12) {
                // Zone combinée : Pochette + Textes (ramène à l'album vinyle)
                HStack(spacing: 12) {
                    // 1. Jaquette à gauche (36x36, coins arrondis 7)
                    AsyncCoverImage(
                        url: activityManager.activeCoverURL,
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
                            text: activityManager.activeAlbumTitle ?? String(localized: "Album vinyle"),
                            font: .subheadline.weight(.semibold),
                            color: .primary
                        )

                        AutoScrollingText(
                            text: turntableSubtitle(artist: activityManager.activeArtistName),
                            font: .caption,
                            color: Color.appSecondaryText
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(activityManager.activeAlbumTitle ?? ""), \(activityManager.activeArtistName ?? ""). Écoute en cours sur la platine. Touche pour ouvrir l'album.")
                .accessibilityAddTraits(.isButton)

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
                    .contentShape(Circle())
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
                coordinator.returnToRelease(releaseId: releaseId, coverURL: activityManager.activeCoverURL)
            }
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
                removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94))
            )
        )
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

// MARK: - Auto-scrolling Marquee Text

private struct AutoScrollTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Affiche un texte sur une seule ligne. Si la largeur du texte dépasse l'espace disponible,
/// déclenche un défilement automatique horizontal élégant (pause initiale, défilement fluide, pause finale et retour).
private struct AutoScrollingText: View {
    let text: String
    let font: Font
    var color: Color = .primary

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        // Vue fantôme masquée pour réserver la hauteur exacte de la ligne de texte
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .overlay(
                GeometryReader { geo in
                    let containerWidth = geo.size.width
                    let isOverflowing = textWidth > containerWidth && containerWidth > 0
                    let excess = max(0, textWidth - containerWidth)

                    ZStack(alignment: .leading) {
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .offset(x: isOverflowing ? offset : 0)
                    }
                    .frame(width: containerWidth, height: geo.size.height, alignment: .leading)
                    .clipped()
                    .mask(
                        HStack(spacing: 0) {
                            if isOverflowing && offset < -2 {
                                LinearGradient(
                                    colors: [.clear, .black],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 8)
                            }
                            Rectangle().fill(Color.black)
                            if isOverflowing && offset > -excess + 2 {
                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 8)
                            }
                        }
                    )
                    .task(id: "\(text)|\(Int(containerWidth))|\(Int(textWidth))") {
                        guard textWidth > containerWidth, containerWidth > 0 else {
                            offset = 0
                            return
                        }
                        let excess = textWidth - containerWidth
                        let scrollSpeed: Double = 26.0
                        let scrollDuration = max(1.8, Double(excess / scrollSpeed))

                        while !Task.isCancelled {
                            offset = 0
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            if Task.isCancelled { break }

                            withAnimation(.linear(duration: scrollDuration)) {
                                offset = -excess
                            }
                            try? await Task.sleep(nanoseconds: UInt64((scrollDuration + 1.8) * 1_000_000_000))
                            if Task.isCancelled { break }

                            withAnimation(.easeInOut(duration: 0.7)) {
                                offset = 0
                            }
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                        }
                    }
                }
            )
            .background(
                // Mesure hors écran de la largeur naturelle non contrainte du texte
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .background(
                        GeometryReader { textGeo in
                            Color.clear
                                .preference(key: AutoScrollTextWidthKey.self, value: textGeo.size.width)
                        }
                    )
            )
            .onPreferenceChange(AutoScrollTextWidthKey.self) { newWidth in
                textWidth = newWidth
            }
            .allowsHitTesting(false)
    }
}

