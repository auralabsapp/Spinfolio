import SwiftUI

/// Maquettes de la section « Écoute sur platine » (voir `GuideVisualView`).

// MARK: - Écoute depuis une fiche

struct ListeningMock: View {
    var body: some View {
        // Mêmes boutons et même pastille que `ListeningLogCard` pendant une écoute.
        HStack(spacing: 10) {
            Image(systemName: "opticaldisc.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.spinlogPink, in: Circle())

            Image(systemName: "stop.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.spinlogPink)
                    .frame(width: 7, height: 7)
                Text("Écoute en cours")
                    .font(.caption.bold())
                    .foregroundStyle(Color.spinlogPink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.spinlogPink.opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - Live Activity

struct LiveActivityMock: View {
    var body: some View {
        HStack(spacing: 12) {
            CoverPlaceholder(size: 40)

            VStack(alignment: .leading, spacing: 6) {
                TextLine(width: 110)
                TextLine(width: 70)
            }

            Spacer(minLength: 0)

            Image(systemName: "waveform")
                .foregroundStyle(Color.spinlogPink)
            Image(systemName: "timer")
                .foregroundStyle(Color.appSecondaryText)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}

// MARK: - Apple Music

struct AppleMusicMock: View {
    var body: some View {
        // Même ligne que le réglage de `SettingsAppleMusicSection`, non interactive.
        HStack(spacing: 14) {
            SettingsIcon(systemName: "music.note", backgroundColor: .pink)
            Text("Connecter mon compte Apple Music")
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Toggle(isOn: .constant(true)) { EmptyView() }
                .labelsHidden()
                .tint(Color.spinlogPink)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Widget « Album du jour »

struct WidgetMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Spacer(minLength: 0)
            Text("Album du jour")
                .font(.caption2.bold())
                .textCase(.uppercase)
                .foregroundStyle(Color.spinlogPink)
            TextLine(width: 64)
            TextLine(width: 44)
        }
        .padding(12)
        .frame(width: 118, height: 118, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.primary.opacity(0.12)))
    }
}

#Preview {
    VStack(spacing: 16) {
        GuideVisualView(visual: .listening)
        GuideVisualView(visual: .liveActivity)
        GuideVisualView(visual: .appleMusic)
        GuideVisualView(visual: .widget)
    }
    .padding()
}
