import SwiftUI

/// Origine de la fenêtre de lecture ouverte depuis le mini-lecteur : Apple Music (fenêtre plein
/// écran, `NowPlayingFullScreenView`) ou écoute sur platine (petite feuille,
/// `NowPlayingTurntableSheet`).
struct NowPlayingPresentation: Identifiable {
    enum Source { case appleMusic, turntable }

    let id = UUID()
    let source: Source
}

/// Feuille ouverte depuis la fenêtre de lecture (une seule à la fois).
private enum NowPlayingSheet: Identifiable {
    case tracklist
    var id: Int { 0 }
}

/// Fenêtre de lecture plein écran ouverte depuis le mini-lecteur, sur le modèle de l'écran
/// « Lecture en cours » d'Apple Music : pochette en grand qui se fond dans un arrière-plan flouté,
/// titre et artiste à gauche, barre de progression, commandes, volume, puis AirPlay et liste des
/// pistes. Elle sort du mini-lecteur (transition zoom) et se ferme en glissant vers le bas.
struct NowPlayingFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = NowPlayingViewModel()
    @State private var service = AppleMusicPlaybackService.shared

    @State private var isDraggingProgress = false
    @State private var scrubProgress: Double = 0
    @State private var sheet: NowPlayingSheet?
    /// Dernier titre Apple Music connu : entre deux pistes, `service.currentItem` repasse un
    /// instant à `nil`, et la fenêtre ne doit alors ni se vider ni se fermer.
    @State private var lastItem: NowPlayingItem?
    /// Arrêt demandé : un second toucher pendant la fermeture est ignoré (voir `stopAndClose`).
    @State private var isStopping = false

    /// Part de la hauteur de l'écran occupée par la pochette, comme sur l'écran d'Apple Music.
    private static let coverHeightRatio = 0.55

    // MARK: - Données affichées

    private var item: NowPlayingItem? { service.currentItem ?? lastItem }

    private var destination: SearchDestination? { item?.destination }

    private var titleText: String { item?.trackTitle ?? "" }

    private var artistText: String { item?.artistName ?? "" }

    private var coverURL: String? { viewModel.album?.coverURL ?? item?.coverURL }

    /// Fin de la lecture (arrêt depuis le mini-lecteur, fin du morceau) : la fenêtre n'a plus rien
    /// à montrer.
    private var isSessionOver: Bool {
        service.currentItem == nil && service.isLoadingTrackID == nil
    }

    private var effectiveProgress: Double {
        isDraggingProgress ? scrubProgress : service.playbackProgress
    }

    private var effectiveTime: TimeInterval {
        isDraggingProgress ? scrubProgress * service.totalDuration : service.playbackTime
    }

    private var remainingTime: TimeInterval {
        max(0, service.totalDuration - effectiveTime)
    }

    // MARK: - Corps

    var body: some View {
        GeometryReader { geo in
            let coverHeight = geo.size.height * Self.coverHeightRatio
            ZStack(alignment: .top) {
                backgroundLayer

                VStack(spacing: 0) {
                    coverHeader(width: geo.size.width, height: coverHeight)

                    VStack(spacing: 0) {
                        titleRow
                        Spacer(minLength: 14)
                        if service.totalDuration > 0 { progressBar }
                        Spacer(minLength: 14)
                        transportRow
                        Spacer(minLength: 14)
                        volumeRow
                        Spacer(minLength: 14)
                        bottomRow
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
                }

                grabber
                    .padding(.top, geo.safeAreaInsets.top + 6)
            }
            // Une seule couche composée : pochette en dégradé, fond et contrôles se déplacent
            // ensemble pendant la transition zoom.
            .compositingGroup()
            .ignoresSafeArea()
        }
        // Fond sombre quel que soit le thème, comme l'écran d'Apple Music.
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape) { dismiss() }
        .task(id: destination) {
            await viewModel.load(destination: destination)
        }
        .onAppear { lastItem = service.currentItem }
        .onChange(of: service.currentItem) { _, newValue in
            if let newValue { lastItem = newValue }
        }
        .onChange(of: isSessionOver) { _, over in
            if over { dismiss() }
        }
        .sheet(item: $sheet) { _ in
            NowPlayingTracklistSheet(
                album: viewModel.album,
                isLoading: viewModel.isLoading,
                loadFailed: viewModel.loadFailed,
                playingItem: item,
                onPlay: { track in
                    if let item { play(track, from: item) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Arrière-plan et pochette

    /// Fond : la pochette réduite à une miniature puis étirée sur tout l'écran, ce qui la rend
    /// naturellement floue (sans filtre de flou plein écran, très coûteux à redessiner à chaque
    /// image), assombrie pour garder le texte lisible. Aplatie en une seule texture
    /// (`drawingGroup`) : en descendant, la fenêtre déplace une image déjà calculée au lieu de
    /// refaire le flou quand elle passe sur le verre du mini-lecteur (c'était là que ça saccadait).
    private var backgroundLayer: some View {
        ZStack {
            Color.black
            AsyncCoverImage(url: coverURL, cornerRadius: 0, showsBorder: false, targetSize: 24)
                .scaleEffect(4)
                .blur(radius: 6)
                .opacity(0.85)
            Color.black.opacity(0.4)
        }
        .clipped()
        .drawingGroup()
        .accessibilityHidden(true)
    }

    /// Pochette pleine largeur (recadrée sur les côtés) qui se fond vers le bas dans l'arrière-plan.
    private func coverHeader(width: CGFloat, height: CGFloat) -> some View {
        AsyncCoverImage(url: coverURL, cornerRadius: 0, showsBorder: false, targetSize: max(width, height))
            .frame(width: max(width, height), height: max(width, height))
            .frame(width: width, height: height)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.6),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .accessibilityHidden(true)
    }

    /// Repère de glissé en haut de l'écran ; touchable aussi, pour fermer sans glisser.
    private var grabber: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: 40, height: 5)
                .frame(width: 120, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fermer le lecteur")
    }

    // MARK: - Titre, artiste, fiche du disque

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !artistText.isEmpty {
                    Text(artistText)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Text("Lecture sur Apple Music")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            // Un seul choix possible : bouton direct plutôt qu'un menu « … » à une entrée.
            if destination != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                    openSourcePage()
                } label: {
                    Image(systemName: "opticaldisc")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voir la fiche du disque")
            }
        }
    }

    /// Retour à la fiche (release ou master) d'où la lecture a été lancée.
    private func openSourcePage() {
        if let item { TabNavigationCoordinator.shared.returnToPlayingItem(item) }
    }

    // MARK: - Progression

    private var progressBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: isDraggingProgress ? 10 : 7)
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: max(0, min(width * CGFloat(effectiveProgress), width)), height: isDraggingProgress ? 10 : 7)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDraggingProgress {
                                isDraggingProgress = true
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                            scrubProgress = max(0, min(Double(value.location.x / width), 1))
                        }
                        .onEnded { value in
                            let ratio = max(0, min(Double(value.location.x / width), 1))
                            service.seek(to: ratio * service.totalDuration)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.chartSelection) { isDraggingProgress = false }
                        }
                )
            }
            .frame(height: 24)
            .animation(.chartSelection, value: isDraggingProgress)
            // Alternative VoiceOver au glissé : avancer ou reculer de 5 secondes.
            .accessibilityElement()
            .accessibilityLabel("Position dans le morceau")
            .accessibilityValue("\(Int(effectiveTime).formattedAsMinutesSeconds) sur \(Int(service.totalDuration).formattedAsMinutesSeconds)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: service.seek(to: service.playbackTime + 5)
                case .decrement: service.seek(to: service.playbackTime - 5)
                @unknown default: break
                }
            }

            // Temps écoulé à gauche, temps restant à droite, comme dans Apple Music.
            HStack {
                Text(Int(effectiveTime).formattedAsMinutesSeconds)
                Spacer()
                Text("−\(Int(remainingTime).formattedAsMinutesSeconds)")
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .accessibilityHidden(true)
        }
    }

    // MARK: - Commandes

    private var transportRow: some View {
        HStack {
            transportButton(systemImage: "backward.fill", label: "Piste précédente", isEnabled: item != nil, size: 38) {
                playAdjacent(offset: -1)
            }
            Spacer()
            // Le service de lecture n'a pas de pause : le bouton central arrête (et ferme) la lecture.
            transportButton(systemImage: "stop.fill", label: "Arrêter la lecture", isEnabled: true, size: 48) {
                stopAndClose()
            }
            Spacer()
            transportButton(systemImage: "forward.fill", label: "Piste suivante", isEnabled: nextTrack != nil, size: 38) {
                playAdjacent(offset: 1)
            }
        }
        .padding(.horizontal, 24)
    }

    private func transportButton(
        systemImage: String,
        label: LocalizedStringKey,
        isEnabled: Bool,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
            SystemVolumeSlider()
                .frame(height: 34)
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.6))
        .accessibilityElement(children: .contain)
    }

    private var bottomRow: some View {
        HStack(spacing: 56) {
            SystemRoutePickerButton()
                .frame(width: 44, height: 44)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                sheet = .tracklist
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Liste des pistes")
        }
    }

    /// La fenêtre rentre d'abord dans le mini-lecteur (zoom inverse de l'ouverture), le son
    /// baissant en fondu, puis la lecture s'arrête et le mini-lecteur s'efface. Auparavant l'arrêt
    /// immédiat faisait disparaître le mini-lecteur, cible du zoom : la fenêtre se fermait d'un coup.
    private func stopAndClose() {
        guard !isStopping else { return }
        isStopping = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
        if reduceMotion {
            service.stop()
        } else {
            Task { await service.fadeOutAndStop(over: 0.45) }
        }
    }

    // MARK: - Lecture d'une piste

    private var nextTrack: Track? {
        adjacentTrack(offset: 1)
    }

    private func adjacentTrack(offset: Int) -> Track? {
        guard let item, let tracks = viewModel.album?.tracklist else { return nil }
        return NowPlayingAlbum.adjacentTrack(in: tracks, from: item.trackID, offset: offset) {
            service.matchStatus(for: $0.id) != false
        }
    }

    /// « Précédent » revient à la piste d'avant, ou au début du morceau s'il n'y en a pas.
    private func playAdjacent(offset: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let item, let track = adjacentTrack(offset: offset) else {
            if offset < 0 { service.seek(to: 0) }
            return
        }
        play(track, from: item)
    }

    private func play(_ track: Track, from item: NowPlayingItem) {
        // `toggle` arrêterait la lecture si on rejouait le titre en cours.
        guard track.id != item.trackID, service.matchStatus(for: track.id) != false else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await service.toggle(
                trackID: track.id,
                artistName: item.artistName,
                albumTitle: item.albumTitle,
                trackTitle: track.title,
                trackDuration: track.duration,
                coverURL: item.coverURL,
                destination: item.destination,
                sourceTab: item.sourceTab
            )
        }
    }
}
