import SwiftUI

struct SleepSoundsTab: View {
    private let player = SleepWindDownPlayer.shared
    @State private var selectedCategory: SleepSoundCategory? = nil
    @State private var sleepTimer: Int = 30

    let timerOptions = [15, 30, 45, 60, 90]

    private var libraryGroups: [(category: SleepSoundCategory, items: [SleepSoundItem])] {
        let cats = selectedCategory.map { [$0] } ?? Array(SleepSoundCategory.allCases)
        return cats.compactMap { cat in
            let items = allSleepSounds.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    var body: some View {
        @Bindable var player = player
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if player.isPlaying {
                    nowPlaying(player)
                }

                EditorSection(title: "TIMER") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(timerOptions, id: \.self) { mins in
                                Button {
                                    sleepTimer = mins
                                } label: {
                                    Text("\(mins)m")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(sleepTimer == mins ? .white : .textTertiary)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(sleepTimer == mins ? Color(hex: "6366F1") : Color.surface)
                                        .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                EditorSection(title: "LIBRARY") {
                    Text("Pick one. Each is generated on this phone — café chatter, noise colors, lo-fi, nature. No account, no files.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                EditorSection(title: "CATEGORIES") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedCategory = nil }
                            } label: {
                                Text("All")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selectedCategory == nil ? .white : .textTertiary)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(selectedCategory == nil ? Color(hex: "6366F1") : Color.surface)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(.plain)

                            ForEach(SleepSoundCategory.allCases, id: \.self) { cat in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        selectedCategory = selectedCategory == cat ? nil : cat
                                    }
                                } label: {
                                    Text(cat.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(selectedCategory == cat ? .white : .textTertiary)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(selectedCategory == cat ? Color(hex: "6366F1") : Color.surface)
                                        .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(libraryGroups, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.category.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.1)
                                .foregroundColor(.textMuted)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.items) { sound in
                                SoundLibraryRow(
                                    sound: sound,
                                    isActive: player.isPlaying && player.kind == sound.kind,
                                    onTap: {
                                        FDS.haptic(.medium)
                                        if player.isPlaying, player.kind == sound.kind {
                                            player.stop()
                                        } else {
                                            player.start(kind: sound.kind, minutes: sleepTimer)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .sensoryFeedback(.selection, trigger: sleepTimer)
        .sensoryFeedback(.selection, trigger: selectedCategory)
    }

    @ViewBuilder
    private func nowPlaying(_ player: SleepWindDownPlayer) -> some View {
        @Bindable var player = player
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(player.kind.color.opacity(0.2)).frame(width: 44, height: 44)
                    Image(systemName: player.kind.icon).font(.system(size: 16)).foregroundColor(player.kind.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.kind.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 8) {
                        SoundWaveformBadge()
                        Text(player.remainingLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                Button {
                    player.stop()
                } label: {
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.danger.opacity(0.85))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
                Slider(value: $player.volume, in: 0...1)
                    .tint(player.kind.color)
                    .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "6366F1").opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now playing \(player.kind.displayName), \(player.remainingLabel)")
    }
}

struct SoundLibraryRow: View {
    let sound: SleepSoundItem
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(sound.color.opacity(isActive ? 0.28 : 0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: isActive ? "pause.fill" : sound.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(sound.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sound.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(sound.category.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.textMuted)
                    }
                    Text(sound.blurb)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .background(isActive ? sound.color.opacity(0.10) : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isActive ? sound.color.opacity(0.45) : Color.borderColor.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sound.name). \(sound.blurb)")
        .accessibilityHint(isActive ? "Stops playback" : "Plays this sound")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct SoundWaveformBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 20.0,
            paused: reduceMotion || scenePhase != .active
        )) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { i in
                    let h = reduceMotion ? 8.0 : 4 + 8 * abs(sin(t * 3 + Double(i) * 0.7))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: "6366F1").opacity(0.7))
                        .frame(width: 2, height: CGFloat(h))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
