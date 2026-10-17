import SwiftUI
import ForgeCore

struct MusicControlBar: View {
    @ObservedObject var controller: AnyMusicController
    var compact: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnscreen = true

    /// Equalizer clock. 10 Hz is already under the 12 Hz ceiling; it still
    /// pauses off-screen, under Reduce Motion, or when the scene is inactive.
    static let tickHz: Double = 10
    static let tickInterval: Double = 1.0 / tickHz

    static func isClockPaused(reduceMotion: Bool, sceneActive: Bool, onscreen: Bool) -> Bool {
        ForgeMotion.isDecorativeClockPaused(
            reduceMotion: reduceMotion,
            sceneActive: sceneActive,
            onscreen: onscreen
        )
    }

    private var equalizerPaused: Bool {
        Self.isClockPaused(
            reduceMotion: reduceMotion,
            sceneActive: scenePhase == .active,
            onscreen: isOnscreen
        )
    }

    private var accent: Color { controller.service.accentColor }

    private func artworkIconOpacity(for phase: AsyncImagePhase) -> Double {
        if case .empty = phase {
            return 0
        }
        return 1
    }

    var body: some View {
        Group {
            if let track = controller.nowPlaying {
                playingView(track: track)
            } else if controller.isAuthorized {
                emptyView
            } else {
                unauthorizedView
            }
        }
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: controller.nowPlaying?.isPlaying)
        .onAppear { isOnscreen = true }
        .onDisappear { isOnscreen = false }
        .onScrollVisibilityChange { isOnscreen = $0 }
    }

    // MARK: Playing

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous)
    }

    private func artwork(track: NowPlayingTrack) -> some View {
        ZStack {
            AsyncImage(url: track.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    LinearGradient.flat(accent)
                    .overlay(
                        Image(systemName: controller.service.iconName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(artworkIconOpacity(for: phase))
                    )
                }
            }
            .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
            .clipShape(artworkShape)

            if track.isPlaying {
                artworkShape
                    .fill(Color.black.opacity(0.35))
                    .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                equalizer
            }
        }
        .accessibilityHidden(true)
    }

    /// Runs only while a track is playing, and sits still under Reduce Motion.
    private var equalizer: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                equalizerBar(i)
            }
        }
    }

    @ViewBuilder
    private func equalizerBar(_ i: Int) -> some View {
        if reduceMotion {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white)
                .frame(width: 3, height: 8 + CGFloat(i % 3) * 4)
        } else {
            TimelineView(.animation(minimumInterval: Self.tickInterval, paused: equalizerPaused)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate + Double(i) * 0.3
                let h = 6.0 + abs(sin(t * 3.0 + Double(i))) * 10.0
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 3, height: h)
            }
        }
    }

    private func trackText(track: NowPlayingTrack) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
            Text(track.title)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            Text(track.artist)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            if !compact {
                serviceRow(track: track)
            }
        }
    }

    /// Full-size context only. In compact mode the artwork already names the
    /// service and the BPM lives in the metrics.
    private func serviceRow(track: NowPlayingTrack) -> some View {
        HStack(spacing: FDS.Spacing.sm) {
            ForgeChip(label: controller.service.rawValue, energy: accent, selected: true)
            if let bpm = track.bpm {
                Text("\(bpm) BPM")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.steel)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
        }
    }

    private func skipButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func controls(track: NowPlayingTrack) -> some View {
        HStack(spacing: FDS.Spacing.sm) {
            skipButton(systemImage: "backward.fill", label: "Previous track", action: controller.skipBack)
            ForgeIconButton(
                systemImage: track.isPlaying ? "pause.fill" : "play.fill",
                accent: accent,
                accessibilityLabel: track.isPlaying ? "Pause" : "Play",
                action: controller.togglePlayPause
            )
            skipButton(systemImage: "forward.fill", label: "Next track", action: controller.skipForward)
        }
    }

    private func playingRow(track: NowPlayingTrack) -> some View {
        HStack(spacing: FDS.Spacing.md) {
            artwork(track: track)
            trackText(track: track)
                .layoutPriority(1)
            Spacer(minLength: 0)
            controls(track: track)
        }
    }

    @ViewBuilder
    private func playingView(track: NowPlayingTrack) -> some View {
        if compact {
            playingRow(track: track)
                .padding(.horizontal, ForgeLayout.compactCardPadding)
                .padding(.vertical, FDS.Spacing.xs)
                .forgeGlassCard(cornerRadius: FDS.Radius.lg)
        } else {
            playingRow(track: track)
                .forgeContentCard(padding: ForgeLayout.compactCardPadding)
        }
    }

    // MARK: Empty

    @ViewBuilder
    private var emptyView: some View {
        if compact {
            // Mid-workout, a full card that says "nothing is playing" is the most
            // expensive way to convey nothing. One tappable line does the same job.
            Button(action: controller.togglePlayPause) {
                HStack(spacing: FDS.Spacing.sm) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.85))
                        .accessibilityHidden(true)
                    Text("Play \(controller.service.rawValue)")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, FDS.Spacing.md)
                .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
                .forgeInsetTile(radius: FDS.Radius.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(controller.service.rawValue)")
        } else {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "music.note.list", tint: accent)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("Nothing playing")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                    Text(controller.service.rawValue)
                        .font(HomeType.micro)
                        .foregroundStyle(accent)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .forgeContentCard(padding: ForgeLayout.compactCardPadding)
        }
    }

    // MARK: Unauthorized

    private func connect() {
        Task { await controller.requestAccess() }
    }

    @ViewBuilder
    private var unauthorizedView: some View {
        if compact {
            // In-session the connect prompt is one 44 pt button, not a card.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForgeIconButton(
                    systemImage: "music.note",
                    accent: .ember,
                    accessibilityLabel: "Connect \(controller.service.rawValue)",
                    action: connect
                )
            }
        } else {
            Button(action: connect) {
                ForgeListRow(
                    icon: controller.service.iconName,
                    iconColor: accent,
                    title: "Connect \(controller.service.rawValue)",
                    subtitle: "Tap to authorize",
                    showChevron: true
                )
                .forgeContentCard(padding: ForgeLayout.compactCardPadding)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect \(controller.service.rawValue)")
            .accessibilityHint("Tap to authorize")
        }
    }
}
