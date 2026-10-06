import SwiftUI

/// Mini-lecteur audio flottant au-dessus de la barre d'onglets façon Liquid Glass (iOS 26 / Apple Music).
/// Apparaît dès qu'un titre est en cours d'écoute.
/// - Pochette à gauche.
/// - Titre et artiste empilés verticalement au centre.
/// - Position temporelle et durée (`0:12 / 0:30`) à droite, juste à côté du bouton pause.
/// - Bouton pause avec symbole reprenant exactement la couleur d'arrière-plan du système.
/// - Barre de progression tactile et interactive permettant de se déplacer instantanément dans le morceau.
/// - Un appui sur le mini-lecteur ramène immédiatement l'utilisateur sur la vue (Release ou Master)
///   d'où la lecture a été lancée.
struct MiniPlayerBar: View {
    @State private var service = AppleMusicPlaybackService.shared
    @ObservedObject private var activityManager = NowPlayingActivityManager.shared
    @State private var coordinator = TabNavigationCoordinator.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isDraggingProgress = false
    @State private var scrubProgress: Double = 0.0

    private var appleMusicRed: Color {
        colorScheme == .dark
            ? Color(red: 222 / 255, green: 56 / 255, blue: 72 / 255)
            : Color(red: 246 / 255, green: 66 / 255, blue: 84 / 255)
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
            appleMusicPlayerView(item: item)
        } else if let releaseId = activityManager.activeReleaseId, activityManager.isAnyPlaying {
            turntablePlayerView(releaseId: releaseId)
        }
    }

    @ViewBuilder
    private func appleMusicPlayerView(item: NowPlayingItem) -> some View {
        GlassEffectContainer {
                ZStack(alignment: .bottom) {
                    // Contenu principal : parfaitement centré verticalement
                    HStack(spacing: 12) {
                        // Zone cliquable : Pochette + Textes (ramène à la vue source)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            coordinator.returnToPlayingItem(item)
                        } label: {
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

                                // 2. Titre et Artiste l'un en dessous de l'autre (avec défilement auto si trop long)
                                VStack(alignment: .leading, spacing: 0.5) {
                                    AutoScrollingText(
                                        text: item.trackTitle,
                                        font: .subheadline.weight(.semibold),
                                        color: .primary
                                    )

                                    AutoScrollingText(
                                        text: item.artistName,
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
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.trackTitle), \(item.artistName). \(formatTime(effectiveTime)) sur \(formatTime(service.totalDuration)). Toucher pour ouvrir l'album.")

                        // 4. Bouton pause à droite réduit et compact (centré verticalement par rapport au texte)
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            service.stop()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(appleMusicRed)
                                    .frame(width: 25, height: 25)

                                Image(systemName: "pause.fill")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Color(uiColor: .systemBackground))
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
                .glassEffect(.regular.interactive())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
                    removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94))
                )
            )
    }

    @ViewBuilder
    private func turntablePlayerView(releaseId: Int) -> some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                // Zone cliquable : Pochette + Textes (ramène à l'album vinyle)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    coordinator.returnToRelease(releaseId: releaseId, coverURL: activityManager.activeCoverURL)
                } label: {
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

                        // 2. Titre de l'album et sous-titre "Lecture en cours sur votre platine"
                        VStack(alignment: .leading, spacing: 0.5) {
                            AutoScrollingText(
                                text: activityManager.activeAlbumTitle ?? "Album vinyle",
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
                        .offset(y: -2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(activityManager.activeAlbumTitle ?? ""), \(activityManager.activeArtistName ?? ""). Lecture en cours sur votre platine. Toucher pour ouvrir l'album.")

                // 3. Badge "Sur platine" avec icône vinyle rose Spinlog animée
                HStack(spacing: 5) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.spinlogPink)
                        .symbolEffect(.pulse, options: .repeating)

                    Text("Sur platine")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.spinlogPink)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.spinlogPink.opacity(0.12), in: Capsule())
                .offset(y: -2)

                // 4. Bouton Stop à droite (cercle rose Spinlog avec icône stop.fill)
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
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(y: -2)
                .zIndex(2)
                .accessibilityLabel("Arrêter l'écoute sur la platine")
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
                removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94))
            )
        )
    }

    private func turntableSubtitle(artist: String?) -> String {
        if let artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(artist) • Lecture en cours sur votre platine"
        } else {
            return "Lecture en cours sur votre platine"
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

/// Modifieur ajoutant le mini-lecteur audio dans le `safeAreaInset` inférieur d'un onglet,
/// se positionnant automatiquement au millimètre près au-dessus de la barre d'onglets.
struct MiniPlayerContainerModifier: ViewModifier {
    @State private var service = AppleMusicPlaybackService.shared
    @ObservedObject private var activityManager = NowPlayingActivityManager.shared

    /// Le `safeAreaInset` n'est monté que lorsqu'il y a effectivement quelque chose à afficher :
    /// même vide, sa seule présence force une renégociation de la zone de sécurité à chaque image
    /// pendant le défilement, en concurrence avec `.tabBarMinimizeBehavior(.onScrollDown)` qui
    /// redimensionne déjà la barre d'onglets au scroll — perceptible comme des saccades même sans
    /// aucune lecture en cours.
    private var isActive: Bool {
        (service.currentItem != nil && service.isPlaying)
            || (activityManager.activeReleaseId != nil && activityManager.isAnyPlaying)
    }

    func body(content: Content) -> some View {
        if isActive {
            content.safeAreaInset(edge: .bottom) {
                MiniPlayerBar()
            }
        } else {
            content
        }
    }
}

extension View {
    /// Active la présence du mini-lecteur audio Liquid Glass au-dessus de la barre d'onglets
    /// pour cette pile de navigation.
    func withMiniPlayer() -> some View {
        modifier(MiniPlayerContainerModifier())
    }
}
