import SwiftUI
import UIKit
import ForgeCore

struct SleepDayTab: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    private var presence: SleepSurfacePresence { store.sleepSurface }

    private var isInitialLoading: Bool {
        presence.kind == .loading
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                if isInitialLoading {
                    ForgeSkeletonBlock(height: 88, cornerRadius: FDS.Radius.xl)
                    ForgeSkeletonBlock(height: 160, cornerRadius: FDS.Radius.xl)
                    ForgeSkeletonBlock(height: 120, cornerRadius: FDS.Radius.xl)
                } else if presence.showsEmptyCard {
                    SleepSourceStrip(presence: presence)
                    ForgeEmptyStateCard(
                        icon: "moon.zzz.fill",
                        title: presence.emptyTitle,
                        message: presence.emptyMessage,
                        accent: Color.indigo,
                        cta: presence.emptyCTA,
                        action: {
                            Task {
                                if store.healthKitLive {
                                    await hkService.refreshFromAppleHealth(into: store, force: true)
                                } else {
                                    await store.reconnectHealthKit()
                                    await hkService.refreshFromAppleHealth(into: store, force: true)
                                }
                            }
                        }
                    )
                    SleepLifestyleCaption()
                    if let window = hkService.lastInBedWindow {
                        SleepInBedFact(window: window)
                    }
                } else {
                    SleepSourceStrip(presence: presence)
                    EnergyScheduleCard()
                    SleepLastNightStrip()
                    AISleepPredictionCard()
                    AISmartRecommendationsView()
                    SleepStreakCard()
                    SleepWeekRhythm()
                    SleepLifestyleCaption()
                }
            }
            .forgeScreenInsets(top: ForgeLayout.screenTop)
        }
    }
}

struct SleepNightTab: View {
    @EnvironmentObject var store: AppStore
    @Binding var showPersonalization: Bool
    @State private var showSounds = false

    private var coach: SleepBedtimeCoach {
        SleepBedtimeCoach.make(from: store.sleepData, lowEnergyDay: store.readiness.overall < 60)
    }

    private var askAriaButton: some View {
        Button {
            store.openChat(with: coach.ariaPrompt, voice: false)
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ARIAIdentityMark(state: .idle, mood: .energized, size: 22, amplitude: 0.24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("Ask ARIA to get you to bed")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(coach.phase == .dayplan
                         ? "A short landing plan for tonight"
                         : "No score. Just the next step.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                Spacer(minLength: ForgeLayout.pairGap)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.aurora)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: ForgeUX.minTap)
            .forgeContentCard(tint: .aurora, padding: ForgeLayout.compactCardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a chat with ARIA")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                SleepSourceStrip(presence: store.sleepSurface)
                SleepTonightHero(coach: coach)
                SleepInBedCard()
                SleepEveningStoryCard(store: store, coach: coach)
                SleepWindDownRitual(coach: coach, onSounds: { showSounds = true })
                SleepTonightSoundDock(onMore: { showSounds = true })
                askAriaButton

                AISleepEnvironmentView()
                SleepLastNightDetail()
                ChronotypeBadge(onTap: { showPersonalization = true })
            }
            .forgeScreenInsets(top: ForgeLayout.screenTop)
        }
        .sheet(isPresented: $showSounds) {
            NavigationStack {
                SleepSoundsTab()
                    .navigationTitle("Sounds")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSounds = false }
                        }
                    }
            }
        }
    }
}

struct SleepInBedFact: View {
    let window: InBedWindow
    /// True when the fact sits inside another card; it then renders as a well
    /// instead of a second glass card.
    var nested: Bool = false

    private var windowLine: String {
        let start = window.start.formatted(date: .omitted, time: .shortened)
        let end = window.end.formatted(date: .omitted, time: .shortened)
        return "\(start) → \(end) · \(EnergySchedule.durationLabel(window.hours))"
    }

    private var factContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text("Last in-bed window")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .accessibilityAddTraits(.isHeader)
            Text(windowLine)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            Text("In-bed is not a sleep score. Stages land when Apple Watch or iPhone records the night.")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        if nested {
            factContent.forgeWell()
        } else {
            factContent.forgeContentCard(tint: .steel)
        }
    }
}

struct SleepInBedCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLogSheet = false
    @State private var logStart = Calendar.current.date(byAdding: .hour, value: -8, to: Date()) ?? Date()
    @State private var logEnd = Date()
    @State private var writeFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("IN BED")

            if let start = hkService.inBedStartedAt {
                activeContent(since: start)
            } else {
                idleContent
            }

            if writeFailed {
                Text("Connect Apple Health to save this window. The clock stays until it writes.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.warning)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .steel)
        .sheet(isPresented: $showLogSheet) {
            logSheet
        }
    }

    private func activeContent(since start: Date) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            TimelineView(.animation(minimumInterval: 30, paused: scenePhase != .active)) { context in
                let hours = context.date.timeIntervalSince(start) / 3600
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("In bed since \(start.formatted(date: .omitted, time: .shortened))")
                        .font(HomeType.sessionTitle)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text("\(EnergySchedule.durationLabel(hours)) so far. Tap I'm up to write this window to Apple Health.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
            }
            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
                ForgeSecondaryButton(title: "I'm up", accent: .steel) {
                    Task {
                        writeFailed = false
                        let ok = await hkService.endInBed()
                        writeFailed = !ok
                        if ok {
                            await hkService.refreshFromAppleHealth(into: store)
                        }
                    }
                }
                ForgeSecondaryButton(title: "Cancel", accent: .steel) {
                    hkService.cancelInBed()
                }
            }
        }
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text("Log the window you were actually in bed. Apple Health still owns stages.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
                ForgeSecondaryButton(title: "I'm in bed", accent: .steel) {
                    hkService.beginInBed()
                    writeFailed = false
                }
                ForgeSecondaryButton(title: "Log a window", accent: .steel) {
                    logEnd = Date()
                    logStart = Calendar.current.date(byAdding: .hour, value: -8, to: logEnd) ?? logEnd
                    showLogSheet = true
                }
            }
            if let window = hkService.lastInBedWindow {
                SleepInBedFact(window: window, nested: true)
            }
        }
    }

    private var logSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Got in bed", selection: $logStart)
                DatePicker("Got up", selection: $logEnd)
            }
            .navigationTitle("Log in-bed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showLogSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            writeFailed = false
                            let ok = await hkService.logInBedWindow(startedAt: logStart, endedAt: logEnd)
                            writeFailed = !ok
                            if ok {
                                showLogSheet = false
                                await hkService.refreshFromAppleHealth(into: store)
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct SleepTonightHero: View {
    let coach: SleepBedtimeCoach
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 30, paused: scenePhase != .active)) { context in
            let live = coach.advancing(now: context.date)
            VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
                ForgeCardHeader("TONIGHT", tint: .steel)
                Text(live.headline)
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
                    Text(live.bedtimeLabel)
                        .font(HomeType.heroScore)
                        .foregroundStyle(Color.steel)
                        .monospacedDigit()
                        .forgeSingleLine()
                        .layoutPriority(1)
                    Text(live.countdownLabel == "now" ? "lights out" : "in \(live.countdownLabel)")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                Text(live.cue)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudPlate(energy: .steel)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SleepEveningStoryCard: View {
    let store: AppStore
    let coach: SleepBedtimeCoach

    private var lastNight: SleepNight? {
        guard let night = SleepData.lastNight(in: store.sleepData) else { return nil }
        let start = night.onset ?? Date().addingTimeInterval(-night.totalHours * 3600)
        var cursor = start
        var segments: [SleepStageSegment] = []
        func add(_ minutes: Int, _ stage: SleepStage) {
            guard minutes > 0 else { return }
            let end = cursor.addingTimeInterval(Double(minutes) * 60)
            segments.append(SleepStageSegment(start: cursor, end: end, stage: stage))
            cursor = end
        }
        add(night.deepMinutes, .deep)
        add(night.remMinutes, .rem)
        add(night.lightMinutes, .core)
        add(night.awakeMinutes, .awake)
        return segments.isEmpty ? nil : SleepNight(segments: segments)
    }

    private var windDown: WindDownPlan? {
        let onsets = store.sleepData.compactMap(\.onset)
        let minutes = store.sleepData.map { $0.totalHours * 60 }
        return WindDownPredictor.plan(
            recentOnsets: onsets,
            recentSleepMinutes: minutes
        )
    }

    var body: some View {
        let story = SleepStoryEngine.story(
            night: lastNight,
            readiness: ReadinessScore(
                overall: store.readiness.overall,
                sleepQuality: store.readiness.sleepQuality,
                recovery: store.readiness.recoveryScore,
                confidence: store.healthKitLive ? 0.8 : 0.4
            )
        )
        let plan = SleepStoryEngine.tonightPlan(plan: windDown, night: lastNight)
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("EVENING NARRATIVE")
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                Text(story)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(plan)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            Text("Wind-down \(coach.countdownLabel == "now" ? "is now" : "in \(coach.countdownLabel)") · lights out \(coach.bedtimeLabel)")
                .font(HomeType.label)
                .foregroundStyle(Color.aurora)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .aurora)
        .accessibilityElement(children: .combine)
    }
}

struct SleepWindDownRitual: View {
    let coach: SleepBedtimeCoach
    var onSounds: () -> Void
    @State private var dimmed = false
    @State private var parked = false
    @State private var previousBrightness: CGFloat?
    @ScaledMetric(relativeTo: .caption) private var stepBadgeSize: CGFloat = 28

    /// iOS 26 deprecated `UIScreen.main`. Brightness belongs to the scene
    /// that is actually showing this view.
    private static func activeScreen() -> UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active.screen
        }
        return scenes.first?.screen
    }

    private var phoneDetail: String {
        if parked {
            return "Wind-down sound is on. Charge it outside the bed."
        }
        if coach.phase == .overdue || coach.phase == .lightsOut {
            return "Charge it outside the bed. A short wind-down still counts."
        }
        return "Set it down when the sound starts. Bed is the next room, not the next tab."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("GET TO BED")
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                dimRow
                soundRow
                phoneRow
            }
        }
        .forgeContentCard(tint: .steel)
        .onDisappear {
            restoreBrightnessIfNeeded()
        }
    }

    private var dimRow: some View {
        Button {
            FDS.haptic(.press)
            if !dimmed {
                guard let screen = Self.activeScreen() else { return }
                previousBrightness = screen.brightness
                screen.brightness = min(screen.brightness, 0.18)
                dimmed = true
            } else if let previousBrightness, let screen = Self.activeScreen() {
                screen.brightness = previousBrightness
                dimmed = false
            }
        } label: {
            ritualRow(
                step: "1",
                title: dimmed ? "Room dimmed" : "Dim the room",
                detail: dimmed
                    ? "Brightness is down. Tap again to restore."
                    : SleepLifestyleCopy.dimRoomCue,
                done: dimmed
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(dimmed ? "Restores the screen brightness" : "Lowers the screen brightness")
    }

    private var soundRow: some View {
        Button(action: onSounds) {
            ritualRow(
                step: "2",
                title: "Start a sound",
                detail: "Café, brown noise, white noise, lo-fi — pick one, thirty minutes, then bed.",
                done: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the sound library")
    }

    private var phoneRow: some View {
        Button {
            FDS.haptic(.press)
            parked = true
            if !SleepWindDownPlayer.shared.isPlaying {
                SleepWindDownPlayer.shared.start(kind: .brown, minutes: 30)
            }
        } label: {
            ritualRow(
                step: "3",
                title: parked ? "Phone is parked" : "Phone stays here",
                detail: phoneDetail,
                done: parked
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts thirty minutes of brown noise if no sound is playing")
    }

    private func restoreBrightnessIfNeeded() {
        guard dimmed, let previousBrightness else { return }
        ForegroundScreenBrightness.set(previousBrightness)
        dimmed = false
    }

    private func stepBadge(step: String, done: Bool) -> some View {
        let badge = ForgeLayout.scaledCap(stepBadgeSize, base: 28)
        return ZStack {
            Circle()
                .fill(Color.steel.opacity(0.16))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.steel)
            } else {
                Text(step)
                    .font(HomeType.label)
                    .foregroundStyle(Color.steel)
                    .hudInArcText()
            }
        }
        .frame(width: badge, height: badge)
        .accessibilityHidden(true)
    }

    private func ritualRow(step: String, title: String, detail: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            stepBadge(step: step, done: done)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(detail)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityAddTraits(done ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

struct SleepTonightSoundDock: View {
    var onMore: () -> Void
    private let player = SleepWindDownPlayer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "WIND-DOWN SOUND") {
                ForgeTextLink(title: "Library", accent: .steel, action: onMore)
            }

            if player.isPlaying {
                playingContent
            } else {
                pickerContent
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private var playingContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: player.kind.icon, tint: player.kind.color)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(player.kind.displayName)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    SleepCountdownLabel(player: player)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                        .forgeWrapping()
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            ForgeSecondaryButton(title: "Stop", icon: "stop.fill", accent: .steel) {
                player.stop()
            }
        }
    }

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
                ForEach(SleepSoundKind.tonightPicks) { kind in
                    ForgeChipButton(label: kind.displayName, icon: kind.icon, energy: .steel) {
                        FDS.haptic(.primaryCTA)
                        player.start(kind: kind, minutes: 30)
                    }
                    .accessibilityLabel("Start \(kind.displayName)")
                    .accessibilityHint(kind.blurb)
                }
            }
            Text("Generated on this phone. Open Library for rain, ocean, fireplace, and more.")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }
}

/// Stage colors are a categorical data palette with no design token, so the
/// one literal is declared once here. Awake uses the miss steel, never red.
private enum SleepStagePalette {
    static let deep = Color.steel
    static let rem = Color.aurora
    static let light = Color(hex: "64748B")
    static let awake = HudChrome.miss
}

struct SleepLastNightStrip: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    private var night: SleepData? { SleepData.lastNight(in: store.sleepData) }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            if let night {
                if night.hasStages {
                    ForgeCardHeader(
                        "Last night",
                        meta: "\(night.efficiencyPercent)% efficient",
                        metaColor: .steel
                    )
                } else {
                    ForgeCardHeader("Last night")
                }
                headline(for: night)
                if night.hasStages {
                    SleepHypnogram(night: night, height: 54)
                    SleepStageLegend(night: night)
                } else {
                    Text("Sleep stages not recorded")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                if let flag = hkService.lastDepthResult?.headline {
                    Text(flag)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
            } else {
                ForgeCardHeader("Last night")
                ForgeEmptyNote(
                    title: "No night on file",
                    message: store.sleepSurface.lastNightEmptyOrStaleMessage,
                    systemImage: "moon.zzz.fill",
                    tint: .steel
                )
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private func headline(for night: SleepData) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeAdaptiveStack(spacing: FDS.Spacing.sm, alignment: .firstTextBaseline) {
                Text(EnergySchedule.durationLabel(night.totalHours))
                    .font(HomeType.heroScore)
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
                    .forgeSingleLine()
                    .layoutPriority(1)
                Text("asleep")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
            }
            Text("\(night.clock(night.onset)) → \(night.clock(night.wake))")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .monospacedDigit()
                .forgeWrapping()
        }
    }
}

struct SleepLastNightDetail: View {
    @EnvironmentObject var store: AppStore

    private var night: SleepData? { SleepData.lastNight(in: store.sleepData) }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Last night")
            if let night {
                detailContent(for: night)
            } else {
                emptyContent
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private func detailContent(for night: SleepData) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeAdaptiveStack(spacing: ForgeLayout.rowGap, alignment: .firstTextBaseline) {
                Text(EnergySchedule.durationLabel(night.totalHours))
                    .font(HomeType.metric)
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
                    .forgeSingleLine()
                    .layoutPriority(1)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: ForgeLayout.labelValueGap) {
                    Text("\(night.score)")
                        .font(HomeType.metric)
                        .foregroundStyle(HomeReadiness.color(night.score))
                        .monospacedDigit()
                        .forgeSingleLine()
                    Text("score")
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                }
                .accessibilityElement(children: .combine)
            }
            if night.hasStages {
                Text("\(night.clock(night.onset))  →  \(night.clock(night.wake))   ·   \(night.efficiencyPercent)% of time in bed was sleep")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                SleepHypnogram(night: night, height: 92)
                stageStats(for: night)
            } else {
                Text("\(night.clock(night.onset))  →  \(night.clock(night.wake))   ·   Sleep stages not recorded")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
        }
    }

    private func stageStats(for night: SleepData) -> some View {
        ForgeStatGrid(columns: 4) {
            ForgeStatTile(label: "Deep", value: "\(night.deepMinutes)m", energy: SleepStagePalette.deep, icon: "circle.fill")
            ForgeStatTile(label: "REM", value: "\(night.remMinutes)m", energy: SleepStagePalette.rem, icon: "circle.fill")
            ForgeStatTile(label: "Light", value: "\(night.lightMinutes)m", energy: SleepStagePalette.light, icon: "circle.fill")
            ForgeStatTile(label: "Awake", value: "\(night.awakeMinutes)m", energy: SleepStagePalette.awake, icon: "circle.fill")
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeEmptyNote(
                title: "No night on file",
                message: store.sleepSurface.lastNightEmptyOrStaleMessage,
                systemImage: "moon.zzz.fill",
                tint: .steel
            )
            SleepLifestyleCaption()
        }
    }
}

private extension SleepSurfacePresence {
    /// `lastNightEmptyMessage` is blank while the feed is live, but the newest
    /// night on file can still be older than yesterday — say so instead of nothing.
    var lastNightEmptyOrStaleMessage: String {
        lastNightEmptyMessage.isEmpty
            ? "No night recorded since yesterday. Last night will land here once it syncs."
            : lastNightEmptyMessage
    }
}

/// Pillow-style stage map: stacked bands from time-in-bed, not a hairline.
/// `SleepResearchHook.timeline` is the extension point when the brief lands.
struct SleepHypnogram: View {
    let night: SleepData
    var height: CGFloat = 64

    private static let barSpacing: CGFloat = 2
    private static let minBarWidth: CGFloat = 6

    private var bands: [(id: String, color: Color, minutes: Int, y: CGFloat)] {
        [
            ("awake", SleepStagePalette.awake, night.awakeMinutes, 0.08),
            ("rem", SleepStagePalette.rem, night.remMinutes, 0.30),
            ("light", SleepStagePalette.light, night.lightMinutes, 0.54),
            ("deep", SleepStagePalette.deep, night.deepMinutes, 0.78),
        ]
    }

    private var total: Int {
        max(1, night.deepMinutes + night.remMinutes + night.lightMinutes + night.awakeMinutes)
    }

    /// Bars share the inner width exactly: every non-empty band keeps a
    /// readable minimum and the rest is split by minutes, so the row never
    /// outgrows its track.
    private func barWidth(minutes: Int, innerWidth: CGFloat, activeCount: Int) -> CGFloat {
        guard minutes > 0 else { return 0 }
        let reserved = Self.minBarWidth * CGFloat(activeCount)
        let flexible = max(0, innerWidth - reserved)
        let share = CGFloat(minutes) / CGFloat(total)
        return Self.minBarWidth + flexible * share
    }

    var body: some View {
        GeometryReader { geo in
            let gaps = Self.barSpacing * CGFloat(max(0, bands.count - 1))
            let innerW = max(0, geo.size.width - FDS.Spacing.sm * 2 - gaps)
            let innerH = max(0, height - FDS.Spacing.sm * 2)
            let activeCount = bands.filter { $0.minutes > 0 }.count
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: FDS.Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                HStack(alignment: .bottom, spacing: Self.barSpacing) {
                    ForEach(bands, id: \.id) { band in
                        RoundedRectangle(cornerRadius: FDS.Radius.xs, style: .continuous)
                            .fill(band.color)
                            .frame(
                                width: barWidth(minutes: band.minutes, innerWidth: innerW, activeCount: activeCount),
                                height: innerH * (1 - band.y * 0.35)
                            )
                    }
                }
                .padding(FDS.Spacing.sm)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages. Deep \(night.deepMinutes) minutes, REM \(night.remMinutes), light \(night.lightMinutes), awake \(night.awakeMinutes).")
    }
}

struct SleepStageLegend: View {
    let night: SleepData

    var body: some View {
        ForgeFlowLayout(spacing: 8, lineSpacing: 8) {
            legend("Deep", night.deepMinutes, SleepStagePalette.deep)
            legend("REM", night.remMinutes, SleepStagePalette.rem)
            legend("Light", night.lightMinutes, SleepStagePalette.light)
            legend("Awake", night.awakeMinutes, SleepStagePalette.awake)
        }
    }

    private func legend(_ name: String, _ minutes: Int, _ color: Color) -> some View {
        HStack(spacing: FDS.Spacing.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text("\(name) \(minutes)m")
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SleepWeekRhythm: View {
    @EnvironmentObject var store: AppStore
    @ScaledMetric(relativeTo: .caption) private var weekPlotSize: CGFloat = 102

    private var nights: [SleepData] {
        Array(store.sleepData.prefix(7).reversed())
    }

    private var need: Double {
        EnergySchedule.make(from: store.sleepData)?.needHours ?? 8
    }

    /// Top of the plot in hours; never below the need line.
    private var scaleMax: Double {
        max(10, need)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(
                "This week",
                meta: "Need \(EnergySchedule.durationLabel(need))",
                metaColor: .steel
            )
            if nights.isEmpty {
                ForgeEmptyNote(title: "No night on file", systemImage: "moon.zzz.fill", tint: .steel)
            } else {
                chart
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private var chart: some View {
        let plot = ForgeLayout.scaledCap(weekPlotSize, base: 102)
        return VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            plotArea(height: plot)
            weekdayLabels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartSummary)
    }

    private func plotArea(height plot: CGFloat) -> some View {
        let needHeight = plot * CGFloat(need / scaleMax)
        return ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, needHeight)
            HStack(alignment: .bottom, spacing: FDS.Spacing.sm) {
                ForEach(nights) { night in
                    Capsule()
                        .fill(barColor(for: night))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(for: night, plot: plot))
                }
            }
        }
        .frame(height: plot, alignment: .bottom)
    }

    private var weekdayLabels: some View {
        HStack(spacing: FDS.Spacing.sm) {
            ForEach(nights) { night in
                Text(weekday(night.date))
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func barColor(for night: SleepData) -> Color {
        night.totalHours >= need - 0.4 ? Color.vitality.opacity(0.88) : HudChrome.miss.opacity(0.45)
    }

    private func barHeight(for night: SleepData, plot: CGFloat) -> CGFloat {
        let fraction = CGFloat(min(1, max(0, night.totalHours / scaleMax)))
        return min(plot, max(10, plot * fraction))
    }

    private var chartSummary: String {
        let perNight = nights
            .map { "\(fullWeekday($0.date)) \(EnergySchedule.durationLabel($0.totalHours))" }
            .joined(separator: ", ")
        let latest = nights.last.map { EnergySchedule.durationLabel($0.totalHours) } ?? "no data"
        return "This week. Latest night \(latest) asleep, need \(EnergySchedule.durationLabel(need)). \(perNight)."
    }

    private func weekday(_ value: String) -> String {
        formattedWeekday(value, template: "EEEEE")
    }

    private func fullWeekday(_ value: String) -> String {
        formattedWeekday(value, template: "EEEE")
    }

    private func formattedWeekday(_ value: String, template: String) -> String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: value) else { return "" }
        let out = DateFormatter()
        out.setLocalizedDateFormatFromTemplate(template)
        return out.string(from: date)
    }
}

/// iOS 27 deprecates `UIScreen.main`. Brightness belongs to the foreground window scene.
enum ForegroundScreenBrightness {
    static var current: CGFloat {
        screen?.brightness ?? 0.5
    }

    static func set(_ value: CGFloat) {
        screen?.brightness = value
    }

    private static var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return foreground?.screen
    }
}

