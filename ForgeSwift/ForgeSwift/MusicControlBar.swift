import SwiftUI

struct MusicControlBar: View {
    @ObservedObject var controller: AnyMusicController
    var compact: Bool = true

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
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: controller.nowPlaying?.isPlaying)
    }

    private func playingView(track: NowPlayingTrack) -> some View {
        HStack(spacing: 14) {
            ZStack {
                AsyncImage(url: track.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        LinearGradient(
                            colors: [accent, accent.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .overlay(
                            Image(systemName: controller.service.iconName)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .opacity(artworkIconOpacity(for: phase))
                        )
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: track.artworkURL != nil ? .black.opacity(0.25) : accent.opacity(0.4), radius: 8, y: 3)

                if track.isPlaying {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            TimelineView(.animation(minimumInterval: 0.1)) { tl in
                                let t = tl.date.timeIntervalSinceReferenceDate + Double(i) * 0.3
                                let h = 6.0 + abs(sin(t * 3.0 + Double(i))) * 10.0
                                RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 3, height: h)
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(controller.service.rawValue)
                        .font(.system(size: 9, weight: .black)).foregroundColor(accent)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(accent.opacity(0.12)).cornerRadius(4)
                    Text(track.artist).font(.system(size: 12)).foregroundColor(.textTertiary).lineLimit(1)
                    if let bpm = track.bpm {
                        Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                        Text("\(bpm) BPM").font(.system(size: 11, weight: .bold)).foregroundColor(.steel)
                    }
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Button(action: controller.skipBack) {
                    Image(systemName: "backward.fill").font(.system(size: 15)).foregroundColor(.textSecondary).frame(width: 36, height: 36)
                }
                Button(action: controller.togglePlayPause) {
                    ZStack {
                        Circle().fill(accent).frame(width: 36, height: 36).shadow(color: accent.opacity(0.45), radius: 6, y: 2)
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    }
                }
                Button(action: controller.skipForward) {
                    Image(systemName: "forward.fill").font(.system(size: 15)).foregroundColor(.textSecondary).frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, compact ? 9 : 14)
        .background(Color.surface).cornerRadius(compact ? 16 : 20)
        .overlay(RoundedRectangle(cornerRadius: compact ? 16 : 20).stroke(accent.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    @ViewBuilder
    private var emptyView: some View {
        if compact {
            // Mid-workout, a full card that says "nothing is playing" is the most
            // expensive way to convey nothing. One tappable line does the same job.
            Button(action: controller.togglePlayPause) {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill").font(.system(size: 15)).foregroundColor(accent.opacity(0.75))
                    Text("Play \(controller.service.rawValue)").font(.system(size: 12, weight: .semibold)).foregroundColor(.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.surface.opacity(0.6)).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderColor.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(controller.service.rawValue)")
        } else {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list").font(.system(size: 18)).foregroundColor(.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing playing").font(.system(size: 14)).foregroundColor(.textMuted)
                    Text(controller.service.rawValue).font(.system(size: 11, weight: .semibold)).foregroundColor(accent.opacity(0.7))
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.surface).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        }
    }

    private var unauthorizedView: some View {
        Button {
            Task { await controller.requestAccess() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(accent.opacity(0.12)).frame(width: 34, height: 34)
                    Image(systemName: controller.service.iconName).font(.system(size: 14)).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connect \(controller.service.rawValue)").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    Text("Tap to authorize").font(.system(size: 11)).foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.textMuted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.surface).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
