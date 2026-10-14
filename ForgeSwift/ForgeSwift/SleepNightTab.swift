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
            VStack(alignment: .leading, spacing: FDS.Spacing.xl) {
                if isInitialLoading {
                    ForgeSkeletonBlock(height: 88, cornerRadius: FDS.Radius.lg)
                    ForgeSkeletonBlock(height: 160, cornerRadius: FDS.Radius.lg)
                    ForgeSkeletonBlock(height: 120, cornerRadius: FDS.Radius.lg)
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
                    SleepMorningSummaryCard()
                    SleepFeelingCheckIn()
                    SleepDebtMeterCard()
                    EnergyScheduleCard()
                    SleepLastNightStrip()
                    AISleepPredictionCard()
                    AISmartRecommendationsView()
                    SleepStreakCard()
                    SleepLifestyleCaption()
                }
            }
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.top, FDS.Spacing.md)
            .padding(.bottom, 120)
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: FDS.Spacing.xl) {
                SleepSourceStrip(presence: store.sleepSurface)
                SleepTonightHero(coach: coach)
                SleepInBedCard()
                SleepEveningStoryCard(store: store, coach: coach)
                SleepWindDownRitual(coach: coach, onSounds: { showSounds = true })
                SleepTonightSoundDock(onMore: { showSounds = true })
                Button {
                    store.openChat(with: coach.ariaPrompt, voice: false)
                } label: {
                    HStack(spacing: FDS.Spacing.md) {
                        ARIAIdentityMark(state: .idle, mood: .energized, size: 22, amplitude: 0.24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask ARIA to get you to bed")
                                .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                                .foregroundColor(.textPrimary)
                            Text(coach.phase == .dayplan
                                 ? "A short landing plan for tonight"
                                 : "No score. Just the next step.")
                                .font(ForgeType.caption)
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(ForgeType.caption)
                            .foregroundColor(.ember)
                    }
                    .padding(FDS.Spacing.lg)
                    .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .ember)
                }
                .buttonStyle(.plain)

                AISleepEnvironmentView()
                SleepLastNightDetail()
                ChronotypeBadge(onTap: { showPersonalization = true })
            }
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.top, FDS.Spacing.md)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showSounds) {
            NavigationStack {
                SleepSoundsTab()
                    .navigationTitle("Sounds")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSounds = false }
                        }
                    }
            }
        }
    }
}

struct SleepInBedFact: View {
    let window: InBedWindow

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text("Last in-bed window")
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundColor(.textTertiary)
            Text("\(window.start.formatted(date: .omitted, time: .shortened)) → \(window.end.formatted(date: .omitted, time: .shortened)) · \(EnergySchedule.durationLabel(window.hours))")
                .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                .foregroundColor(.textPrimary)
            Text("In-bed is not a sleep score. Stages land when Apple Watch or iPhone records the night.")
                .font(ForgeType.caption)
                .foregroundColor(.textTertiary)
        }
        .padding(FDS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .aurora)
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
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            Text("IN BED")
                .font(FDS.TypeScale.Dynamic.micro)
                .tracking(1.2)
                .foregroundColor(.textTertiary)

            if let start = hkService.inBedStartedAt {
                TimelineView(.animation(minimumInterval: 30, paused: scenePhase != .active)) { context in
                    let hours = context.date.timeIntervalSince(start) / 3600
                    VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                        Text("In bed since \(start.formatted(date: .omitted, time: .shortened))")
                            .font(FDS.TypeScale.Dynamic.headline)
                            .foregroundColor(.textPrimary)
                        Text("\(EnergySchedule.durationLabel(hours)) so far. Tap I'm up to write this window to Apple Health.")
                            .font(ForgeType.body)
                            .foregroundColor(.textSecondary)
                    }
                }
                HStack(spacing: FDS.Spacing.md) {
                    Button {
                        Task {
                            writeFailed = false
                            let ok = await hkService.endInBed()
                            writeFailed = !ok
                            if ok {
                                await hkService.refreshFromAppleHealth(into: store)
                            }
                        }
                    } label: {
                        Text("I'm up")
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FDS.Spacing.md)
                            .background(Color.aurora)
                            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        hkService.cancelInBed()
                    } label: {
                        Text("Cancel")
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FDS.Spacing.md)
                            .forgeInsetTile(radius: FDS.Radius.md)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Log the window you were actually in bed. Apple Health still owns stages.")
                    .font(ForgeType.body)
                    .foregroundColor(.textSecondary)
                HStack(spacing: FDS.Spacing.md) {
                    Button {
                        hkService.beginInBed()
                        writeFailed = false
                    } label: {
                        Text("I'm in bed")
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FDS.Spacing.md)
                            .background(Color.aurora)
                            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        logEnd = Date()
                        logStart = Calendar.current.date(byAdding: .hour, value: -8, to: logEnd) ?? logEnd
                        showLogSheet = true
                    } label: {
                        Text("Log a window")
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                            .foregroundColor(.aurora)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FDS.Spacing.md)
                            .background(Color.aurora.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if let window = hkService.lastInBedWindow {
                    SleepInBedFact(window: window)
                }
            }

            if writeFailed {
                Text("Connect Apple Health to save this window. The clock stays until it writes.")
                    .font(ForgeType.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(FDS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .aurora)
        .sheet(isPresented: $showLogSheet) {
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
}

struct SleepTonightHero: View {
    let coach: SleepBedtimeCoach
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 30, paused: scenePhase != .active)) { context in
            let live = coach.advancing(now: context.date)
            VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
                Text("TONIGHT")
                    .font(FDS.TypeScale.Dynamic.micro)
                    .tracking(1.2)
                    .foregroundColor(.textTertiary)
                Text(live.headline)
                    .font(ForgeType.display)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                    Text(live.bedtimeLabel)
                        .font(FDS.TypeScale.Dynamic.title)
                        .foregroundColor(.aurora)
                        .monospacedDigit()
                    Text(live.countdownLabel == "now" ? "lights out" : "in \(live.countdownLabel)")
                        .font(FDS.TypeScale.Dynamic.body)
                        .foregroundColor(.textSecondary)
                }
                Text(live.cue)
                    .font(ForgeType.body)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            Text("EVENING NARRATIVE")
                .font(FDS.TypeScale.Dynamic.micro)
                .tracking(1.2)
                .foregroundColor(.textTertiary)
            Text(story)
                .font(FDS.TypeScale.Dynamic.body)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(plan)
                .font(ForgeType.body)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Wind-down \(coach.countdownLabel == "now" ? "is now" : "in \(coach.countdownLabel)") · lights out \(coach.bedtimeLabel)")
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundColor(.aurora)
        }
        .padding(FDS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .aurora)
        .accessibilityElement(children: .combine)
    }
}

struct SleepWindDownRitual: View {
    let coach: SleepBedtimeCoach
    var onSounds: () -> Void
    @State private var dimmed = false
    @State private var parked = false
    @State private var previousBrightness: CGFloat?

    /// iOS 26 deprecated `UIScreen.main`. Brightness belongs to the scene
    /// that is actually showing this view.
    private static func activeScreen() -> UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active.screen
        }
        return scenes.first?.screen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            Text("GET TO BED")
                .font(FDS.TypeScale.Dynamic.micro)
                .tracking(1.2)
                .foregroundStyle(Color.textTertiary)
            Button {
                FDS.haptic(.light)
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
                        : SleepLifestyleCopy.dimRoomCue
                )
            }
            .buttonStyle(.plain)
            Button(action: onSounds) {
                ritualRow(
                    step: "2",
                    title: "Start a sound",
                    detail: "Café, brown noise, white noise, lo-fi — pick one, thirty minutes, then bed."
                )
            }
            .buttonStyle(.plain)
            Button {
                FDS.haptic(.medium)
                parked = true
                if !SleepWindDownPlayer.shared.isPlaying {
                    SleepWindDownPlayer.shared.start(kind: .brown, minutes: 30)
                }
            } label: {
                ritualRow(
                    step: "3",
                    title: parked ? "Phone is parked" : "Phone stays here",
                    detail: parked
                        ? "Wind-down sound is on. Charge it outside the bed."
                        : (coach.phase == .overdue || coach.phase == .lightsOut
                           ? "Charge it outside the bed. A short wind-down still counts."
                           : "Set it down when the sound starts. Bed is the next room, not the next tab.")
                )
            }
            .buttonStyle(.plain)
        }
        .onDisappear {
            restoreBrightnessIfNeeded()
        }
    }

    private func restoreBrightnessIfNeeded() {
        guard dimmed, let previousBrightness else { return }
        ForegroundScreenBrightness.set(previousBrightness)
        dimmed = false
    }

    private func ritualRow(step: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: FDS.Spacing.md) {
            Text(step)
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(Color.aurora)
                .frame(width: 28, height: 28)
                .background(Color.aurora.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(ForgeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FDS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .aurora)
    }
}

struct SleepTonightSoundDock: View {
    var onMore: () -> Void
    private let player = SleepWindDownPlayer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack {
                Text("WIND-DOWN SOUND")
                    .font(FDS.TypeScale.Dynamic.micro)
                    .tracking(1.2)
                    .foregroundColor(.textTertiary)
                Spacer()
                Button("Library", action: onMore)
                    .font(ForgeType.caption)
                    .foregroundColor(.aurora)
            }

            if player.isPlaying {
                HStack(spacing: FDS.Spacing.md) {
                    Image(systemName: player.kind.icon)
                        .foregroundStyle(player.kind.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.kind.displayName)
                            .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        SleepCountdownLabel(player: player)
                            .font(ForgeType.caption)
                            .foregroundColor(.textTertiary)
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
                .padding(FDS.Spacing.lg)
                .background(Color.aurora.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FDS.Spacing.sm) {
                        ForEach(SleepSoundKind.tonightPicks) { kind in
                            Button {
                                FDS.haptic(.medium)
                                player.start(kind: kind, minutes: 30)
                            } label: {
                                HStack(spacing: FDS.Spacing.sm) {
                                    Image(systemName: kind.icon)
                                    Text(kind.displayName)
                                        .font(FDS.TypeScale.Dynamic.caption)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, FDS.Spacing.md)
                                .padding(.vertical, FDS.Spacing.md)
                                .background(kind.color.opacity(0.85))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start \(kind.displayName)")
                            .accessibilityHint(kind.blurb)
                        }
                    }
                }

                Text("Generated on this phone. Open Library for rain, ocean, fireplace, and more.")
                    .font(ForgeType.caption)
                    .foregroundColor(.textTertiary)
            }
        }
    }
}

struct SleepLastNightStrip: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    private var night: SleepData? { SleepData.lastNight(in: store.sleepData) }

    var body: some View {
        if let night {
            VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
                HStack {
                    Text("Last night")
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.textTertiary)
                    Spacer()
                    if night.hasStages {
                        Text("\(night.efficiencyPercent)% efficient")
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(.aurora)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.md) {
                    Text(EnergySchedule.durationLabel(night.totalHours))
                        .font(ForgeType.heroScore)
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                    Text("asleep")
                        .font(ForgeType.body)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("\(night.clock(night.onset)) → \(night.clock(night.wake))")
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.textTertiary)
                        .monospacedDigit()
                }
                if night.hasStages {
                    SleepHypnogram(night: night, height: 54)
                    SleepStageLegend(night: night)
                } else {
                    Text("Sleep stages not recorded")
                        .font(ForgeType.caption)
                        .foregroundColor(.textSecondary)
                }
                if let flag = hkService.lastDepthResult?.headline {
                    Text(flag)
                        .font(ForgeType.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        } else {
            Text(store.sleepSurface.lastNightEmptyOrStaleMessage)
                .font(ForgeType.body)
                .foregroundColor(.textSecondary)
        }
    }
}

struct SleepLastNightDetail: View {
    @EnvironmentObject var store: AppStore

    private var night: SleepData? { SleepData.lastNight(in: store.sleepData) }

    var body: some View {
        if let night {
            VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
                Text("Last night")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundColor(.textTertiary)
                HStack(alignment: .firstTextBaseline) {
                    Text(EnergySchedule.durationLabel(night.totalHours))
                        .font(ForgeType.heroScore)
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if store.sleepData.count >= SleepCalibrationState.readyNights {
                            Text("\(night.score)")
                                .font(ForgeType.display)
                                .foregroundColor(.textPrimary)
                            Text("score")
                                .font(ForgeType.micro)
                                .foregroundColor(.textTertiary)
                        } else {
                            Text(SleepCalibrationState.from(scoredNights: store.sleepData.count).caption)
                                .font(ForgeType.caption)
                                .foregroundColor(.steel)
                            Text("no score yet")
                                .font(ForgeType.micro)
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
                if night.hasStages {
                    Text("\(night.clock(night.onset))  →  \(night.clock(night.wake))   ·   \(night.efficiencyPercent)% of time in bed was sleep")
                        .font(ForgeType.body)
                        .foregroundColor(.textSecondary)
                    SleepHypnogram(night: night, height: 92)
                    HStack(spacing: 0) {
                        nightStat("Deep", "\(night.deepMinutes)m", Color.steel)
                        nightStat("REM", "\(night.remMinutes)m", Color.aurora)
                        nightStat("Light", "\(night.lightMinutes)m", SleepHud.lightStage)
                        nightStat("Awake", "\(night.awakeMinutes)m", HudChrome.miss)
                    }
                    .padding(.top, FDS.Spacing.xs)
                } else {
                    Text("\(night.clock(night.onset))  →  \(night.clock(night.wake))   ·   Sleep stages not recorded")
                        .font(ForgeType.body)
                        .foregroundColor(.textSecondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                Text("No night on file")
                    .font(FDS.TypeScale.Dynamic.title)
                    .foregroundColor(.textPrimary)
                Text(store.sleepSurface.lastNightEmptyOrStaleMessage)
                    .font(ForgeType.body)
                    .foregroundColor(.textSecondary)
                SleepLifestyleCaption()
            }
        }
    }

    private func nightStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(value)
                .font(FDS.TypeScale.Dynamic.headline)
                .foregroundColor(.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(ForgeType.micro)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var bands: [(id: String, color: Color, minutes: Int, y: CGFloat)] {
        [
            ("awake", HudChrome.miss, night.awakeMinutes, 0.08),
            ("rem", Color.aurora, night.remMinutes, 0.30),
            ("light", SleepHud.lightStage, night.lightMinutes, 0.54),
            ("deep", Color.steel, night.deepMinutes, 0.78),
        ]
    }

    private var total: Int {
        max(1, night.deepMinutes + night.remMinutes + night.lightMinutes + night.awakeMinutes)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: FDS.Radius.sm)
                    .fill(Color.white.opacity(0.04))
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(bands, id: \.id) { band in
                        let share = CGFloat(band.minutes) / CGFloat(total)
                        RoundedRectangle(cornerRadius: FDS.Radius.xs)
                            .fill(band.color)
                            .frame(
                                width: max(band.minutes > 0 ? 6 : 0, w * share - 2),
                                height: height * (1 - band.y * 0.35)
                            )
                    }
                }
                .padding(FDS.Spacing.sm)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Sleep stages. Deep \(night.deepMinutes) minutes, REM \(night.remMinutes), light \(night.lightMinutes), awake \(night.awakeMinutes)."
        )
    }
}

struct SleepStageLegend: View {
    let night: SleepData

    var body: some View {
        HStack(spacing: FDS.Spacing.md) {
            legend("Deep", night.deepMinutes, Color.steel)
            legend("REM", night.remMinutes, Color.aurora)
            legend("Light", night.lightMinutes, SleepHud.lightStage)
            legend("Awake", night.awakeMinutes, HudChrome.miss)
        }
    }

    private func legend(_ name: String, _ minutes: Int, _ color: Color) -> some View {
        HStack(spacing: FDS.Spacing.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(minutes)m")
                .font(FDS.TypeScale.Dynamic.micro)
                .foregroundColor(.textTertiary)
                .monospacedDigit()
        }
    }
}

struct SleepDebtMeterCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    private var meter: SleepDebtMeter.Result {
        let need = hkService.estimatedSleepNeed(from: store.sleepData)
        let byDate = Dictionary(uniqueKeysWithValues: store.sleepData.map { ($0.date, $0.totalHours) })
        let hours = Array(store.sleepData.map(\.totalHours).reversed())
        return SleepDebtMeter.make(
            nightsByDate: byDate,
            needHours: need,
            asleepHoursOldestFirst: hours
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            ForgeSectionHeader(title: "14-day stretch", subtitle: meter.headline)
            HStack(alignment: .bottom, spacing: FDS.Spacing.sm) {
                ForEach(meter.days) { day in
                    VStack(spacing: FDS.Spacing.sm) {
                        Capsule()
                            .fill(day.missed ? HudChrome.miss.opacity(0.72) : Color.ember.opacity(0.88))
                            .frame(height: max(10, CGFloat(day.fill) * 78))
                        Text(day.weekday)
                            .font(ForgeType.micro)
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(day.hours.map {
                        "\(day.weekday), \(SleepDebtMeter.hoursLabel($0))\(day.missed ? ", short of your need" : "")"
                    } ?? "\(day.weekday), no night on file")
                }
            }
            .frame(height: 102, alignment: .bottom)
            Text(meter.detail)
                .font(ForgeType.caption)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FDS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: HudChrome.miss)
        .accessibilityElement(children: .combine)
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

