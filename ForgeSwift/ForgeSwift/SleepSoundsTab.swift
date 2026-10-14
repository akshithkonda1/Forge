import SwiftUI

struct SleepSoundsTab: View {
    private let player = SleepWindDownPlayer.shared
    @State private var selectedCategory: SleepSoundCategory? = nil
    @State private var sleepTimer: Int = 30

    let timerOptions = SleepMixTimer.options
    @StateObject private var music = MusicControllerFactory.make(for: .appleMusic)
    @State private var playlists = SleepForgePlaylistStore.load()

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
            VStack(spacing: FDS.Spacing.lg) {
                if player.isPlaying {
                    nowPlaying(player)
                }

                EditorSection(title: "TIMER") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: FDS.Spacing.sm) {
                            ForEach(timerOptions, id: \.self) { mins in
                                Button {
                                    sleepTimer = mins
                                } label: {
                                    Text(SleepMixTimer.label(mins))
                                        .font(FDS.TypeScale.Dynamic.caption)
                                        .foregroundColor(sleepTimer == mins ? .white : .textTertiary)
                                        .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.sm)
                                        .background(sleepTimer == mins ? SleepHud.plate : Color.surface)
                                        .cornerRadius(FDS.Radius.xl)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("Tap a second sound while one is playing to mix up to three. Timer stops generated beds and linked Apple Music.")
                        .font(ForgeType.caption)
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SleepAppleMusicCard(music: music, player: player, minutes: sleepTimer)

                if !playlists.isEmpty {
                    EditorSection(title: "FORGE PLAYLISTS") {
                        VStack(spacing: FDS.Spacing.sm) {
                            ForEach(playlists) { list in
                                Button {
                                    let kinds = list.kinds.compactMap(SleepSoundKind.init(rawValue:))
                                    player.startMix(kinds: kinds, minutes: list.minutes)
                                } label: {
                                    HStack {
                                        Image(systemName: "music.note.list")
                                            .foregroundColor(SleepHud.plate)
                                        Text(list.name)
                                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                        Text(SleepMixTimer.label(list.minutes))
                                            .font(ForgeType.caption)
                                            .foregroundColor(.textTertiary)
                                    }
                                    .padding(.vertical, FDS.Spacing.xs)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                EditorSection(title: "LIBRARY") {
                    HStack {
                        Text("Generated on this phone. Mix up to three, or save the mix as a Forge playlist.")
                            .font(ForgeType.body)
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Save mix") {
                            SleepForgePlaylistStore.add(
                                name: player.mix.map(\.displayName).joined(separator: " + "),
                                kinds: player.mix,
                                minutes: sleepTimer
                            )
                            playlists = SleepForgePlaylistStore.load()
                            FDS.haptic(.light)
                        }
                        .font(ForgeType.caption)
                        .foregroundColor(SleepHud.plate)
                    }
                }

                EditorSection(title: "CATEGORIES") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: FDS.Spacing.sm) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedCategory = nil }
                            } label: {
                                Text("All")
                                    .font(FDS.TypeScale.Dynamic.caption)
                                    .foregroundColor(selectedCategory == nil ? .white : .textTertiary)
                                    .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.sm)
                                    .background(selectedCategory == nil ? Color.indigo : Color.surface)
                                    .cornerRadius(FDS.Radius.xl)
                            }
                            .buttonStyle(.plain)

                            ForEach(SleepSoundCategory.allCases, id: \.self) { cat in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        selectedCategory = selectedCategory == cat ? nil : cat
                                    }
                                } label: {
                                    Text(cat.rawValue)
                                        .font(FDS.TypeScale.Dynamic.caption)
                                        .foregroundColor(selectedCategory == cat ? .white : .textTertiary)
                                        .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.sm)
                                        .background(selectedCategory == cat ? Color.indigo : Color.surface)
                                        .cornerRadius(FDS.Radius.xl)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                LazyVStack(alignment: .leading, spacing: FDS.Spacing.lg) {
                    ForEach(libraryGroups, id: \.category) { group in
                        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                            Text(group.category.rawValue.uppercased())
                                .font(FDS.TypeScale.Dynamic.micro)
                                .tracking(1.1)
                                .foregroundColor(.textMuted)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.items) { sound in
                                SoundLibraryRow(
                                    sound: sound,
                                    isActive: player.isPlaying && player.mix.contains(sound.kind),
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
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.bottom, 100)
        }
        .sensoryFeedback(.selection, trigger: sleepTimer)
        .sensoryFeedback(.selection, trigger: selectedCategory)
    }

    @ViewBuilder
    private func nowPlaying(_ player: SleepWindDownPlayer) -> some View {
        @Bindable var player = player
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.lg) {
                ZStack {
                    Circle().fill(player.kind.color.opacity(0.2)).frame(width: 44, height: 44)
                    Image(systemName: player.kind.icon).font(ForgeType.headline).foregroundColor(player.kind.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.kind.displayName)
                        .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                        .foregroundColor(.textPrimary)
                    HStack(spacing: FDS.Spacing.sm) {
                        SoundWaveformBadge(playing: player.isPlaying)
                        SleepCountdownLabel(player: player)
                            .font(ForgeType.caption)
                            .foregroundColor(.textTertiary)
                    }
                }
                Spacer()
                Button {
                    player.stop()
                } label: {
                    Text("Stop")
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, FDS.Spacing.lg)
                        .padding(.vertical, FDS.Spacing.sm)
                        .background(Color.danger.opacity(0.85))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: FDS.Spacing.md) {
                Image(systemName: "speaker.fill")
                    .font(ForgeType.micro)
                    .foregroundColor(.textMuted)
                Slider(value: $player.volume, in: 0...1)
                    .tint(player.kind.color)
                    .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
                    .font(ForgeType.micro)
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: Color.indigo)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now playing \(player.kind.displayName), \(player.remainingLabel)")
    }
}

struct SleepAppleMusicCard: View {
    @ObservedObject var music: AnyMusicController
    @Bindable var player: SleepWindDownPlayer
    var minutes: Int

    var body: some View {
        EditorSection(title: "APPLE MUSIC") {
            VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                Text("Forge can ride whatever is already in Apple Music. Timed stop pauses it with the generated beds. Forge playlists are local mixes — creating a catalog playlist needs your Apple Music key on device, never in the repo.")
                    .font(ForgeType.caption)
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if music.isAuthorized {
                    HStack(spacing: FDS.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(music.nowPlaying?.title ?? "Nothing playing")
                                .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                                .foregroundColor(.textPrimary)
                            Text(music.nowPlaying?.artist ?? "Play from Apple Music, then link the timer")
                                .font(ForgeType.caption)
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        Button(music.nowPlaying?.isPlaying == true ? "Pause" : "Play") {
                            music.togglePlayPause()
                            player.linksAppleMusic = true
                        }
                        .font(ForgeType.caption)
                        .foregroundColor(SleepHud.plate)
                    }
                    Toggle("Stop Apple Music with the timer", isOn: $player.linksAppleMusic)
                        .tint(SleepHud.plate)
                        .font(ForgeType.body)
                } else {
                    Button("Connect Apple Music") {
                        Task { await music.requestAccess() }
                    }
                    .font(ForgeType.body.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, FDS.Spacing.lg)
                    .padding(.vertical, FDS.Spacing.sm)
                    .background(SleepHud.appleMusic)
                    .clipShape(Capsule())
                }
            }
        }
        .onAppear { music.refresh() }
    }
}

struct SoundLibraryRow: View {
    let sound: SleepSoundItem
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: FDS.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                        .fill(sound.color.opacity(isActive ? 0.28 : 0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: isActive ? "pause.fill" : sound.icon)
                        .font(ForgeType.title)
                        .foregroundColor(sound.color)
                }
                VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                    HStack {
                        Text(sound.name)
                            .font(FDS.TypeScale.Dynamic.headline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(sound.category.rawValue.uppercased())
                            .font(FDS.TypeScale.Dynamic.micro)
                            .tracking(0.8)
                            .foregroundColor(.textMuted)
                    }
                    Text(sound.blurb)
                        .font(ForgeType.body)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(FDS.Spacing.lg)
            .background(isActive ? sound.color.opacity(0.10) : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                    .stroke(isActive ? sound.color.opacity(0.45) : Color.borderColor.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sound.name). \(sound.blurb)")
        .accessibilityHint(isActive ? "Stops playback" : "Plays this sound")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct SleepCountdownLabel: View {
    let player: SleepWindDownPlayer

    var body: some View {
        Group {
            if let range = player.countdownRange {
                Text(timerInterval: range, countsDown: true)
            } else {
                Text(player.remainingLabel)
            }
        }
        .monospacedDigit()
    }
}

struct SoundWaveformBadge: View {
    var playing: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 12.0,
            paused: reduceMotion || scenePhase != .active || !playing
        )) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { i in
                    let h = reduceMotion ? 8.0 : 4 + 8 * abs(sin(t * 3 + Double(i) * 0.7))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.indigo.opacity(0.7))
                        .frame(width: 2, height: CGFloat(h))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
