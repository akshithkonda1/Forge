import SwiftUI
import ForgeCore

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

    private var timerChoices: [ForgeSegmentOption<Int>] {
        timerOptions.map { ForgeSegmentOption(value: $0, title: SleepMixTimer.label($0)) }
    }

    private var categoryChoices: [ForgeSegmentOption<String>] {
        var choices = [ForgeSegmentOption(value: "All", title: "All")]
        for cat in SleepSoundCategory.allCases {
            choices.append(ForgeSegmentOption(value: cat.rawValue, title: cat.rawValue))
        }
        return choices
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { selectedCategory?.rawValue ?? "All" },
            set: { name in
                selectedCategory = SleepSoundCategory.allCases.first { $0.rawValue == name }
            }
        )
    }

    var body: some View {
        @Bindable var player = player
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                if player.isPlaying {
                    nowPlaying(player)
                }

                timerCard

                SleepAppleMusicCard(music: music, player: player, minutes: sleepTimer)

                if !playlists.isEmpty {
                    playlistsCard
                }

                libraryCard

                ForEach(libraryGroups, id: \.category) { group in
                    groupCard(group)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeScreenInsets(top: FDS.Spacing.lg)
        }
    }

    // MARK: Cards

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("TIMER")
            ForgeSegmentedControl(
                timerChoices,
                selection: $sleepTimer,
                accent: .steel,
                bleed: ForgeLayout.cardPadding
            )
            Text("Tap a second sound while one is playing to mix up to three. Timer stops generated beds and linked Apple Music.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .steel)
    }

    private var playlistsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("FORGE PLAYLISTS", meta: "\(playlists.count)")
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                ForEach(playlists) { list in
                    playlistRow(list)
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private func playlistRow(_ list: SleepForgePlaylist) -> some View {
        let duration = SleepMixTimer.label(list.minutes)
        return Button {
            ForgeHaptics.play(.press)
            let kinds = list.kinds.compactMap(SleepSoundKind.init(rawValue:))
            player.startMix(kinds: kinds, minutes: list.minutes)
        } label: {
            ForgeListRow(
                icon: "music.note.list",
                iconColor: .steel,
                title: list.name,
                trailing: duration
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(list.name), \(duration)")
        .accessibilityHint("Starts this mix")
    }

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("LIBRARY")
            Text("Generated on this phone. Mix up to three, or save the mix as a Forge playlist.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            ForgeSegmentedControl(
                categoryChoices,
                selection: categoryBinding,
                accent: .steel,
                bleed: ForgeLayout.cardPadding
            )
        }
        .forgeContentCard(tint: .steel)
    }

    private func groupCard(_ group: (category: SleepSoundCategory, items: [SleepSoundItem])) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(group.category.rawValue)
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(group.items) { sound in
                    SoundLibraryRow(
                        sound: sound,
                        isActive: player.isPlaying && player.mix.contains(sound.kind),
                        onTap: {
                            ForgeHaptics.play(.selection)
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
        .forgeContentCard()
    }

    private func saveMix() {
        SleepForgePlaylistStore.add(
            name: player.mix.map(\.displayName).joined(separator: " + "),
            kinds: player.mix,
            minutes: sleepTimer
        )
        playlists = SleepForgePlaylistStore.load()
        ForgeHaptics.play(.success)
    }

    // MARK: Now playing (the one hero)

    @ViewBuilder
    private func nowPlaying(_ player: SleepWindDownPlayer) -> some View {
        @Bindable var player = player
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            ForgeCardHeader(title: "Now playing", tint: .steel) {
                SoundWaveformBadge(playing: player.isPlaying)
            }
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: player.kind.icon, tint: player.kind.color)
                VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                    Text(player.kind.displayName)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    SleepCountdownLabel(player: player)
                        .font(HomeType.metric)
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                        .forgeSingleLine()
                        .contentTransition(.numericText())
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Now playing \(player.kind.displayName), \(player.remainingLabel)")

            HStack(spacing: ForgeLayout.rowGap) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
                Slider(value: $player.volume, in: 0...1)
                    .tint(player.kind.color)
                    .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }

            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
                ForgeSecondaryButton(title: "Stop", icon: "stop.fill", accent: .steel) {
                    player.stop()
                }
                ForgeSecondaryButton(title: "Save mix", icon: "plus", accent: .steel) {
                    saveMix()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
        .accessibilityElement(children: .contain)
    }
}

struct SleepAppleMusicCard: View {
    @ObservedObject var music: AnyMusicController
    @Bindable var player: SleepWindDownPlayer
    var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("APPLE MUSIC")
            Text("Play anything from Apple Music — the sleep timer can pause it too.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            if music.isAuthorized {
                connectedContent
            } else {
                ForgeSecondaryButton(title: "Connect Apple Music", icon: "music.note", accent: .steel) {
                    Task { await music.requestAccess() }
                }
            }
        }
        .forgeContentCard(tint: .steel)
        .onAppear { music.refresh() }
    }

    private var isPlaying: Bool {
        music.nowPlaying?.isPlaying == true
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                    Text(music.nowPlaying?.title ?? "Nothing playing")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text(music.nowPlaying?.artist ?? "Play from Apple Music, then link the timer")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForgeChipButton(
                    label: isPlaying ? "Pause" : "Play",
                    icon: isPlaying ? "pause.fill" : "play.fill",
                    energy: .steel,
                    selected: true
                ) {
                    music.togglePlayPause()
                    player.linksAppleMusic = true
                }
            }
            Toggle(isOn: $player.linksAppleMusic) {
                Text("Stop Apple Music with the timer")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
            }
            .tint(.steel)
            .frame(minHeight: ForgeUX.minTap)
        }
    }
}

struct SoundLibraryRow: View {
    let sound: SleepSoundItem
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: isActive ? "pause.fill" : sound.icon, tint: sound.color)
                VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                    Text(sound.name)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text(sound.blurb)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .forgeWrapping()
                }
                .layoutPriority(1)
                Spacer(minLength: ForgeLayout.pairGap)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(sound.color)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .contentShape(Rectangle())
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
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.steel.opacity(0.7))
                        .frame(width: 2, height: CGFloat(h))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
