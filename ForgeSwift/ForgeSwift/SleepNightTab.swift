import SwiftUI
import UIKit
import ForgeCore

struct SleepDayTab: View {
    @EnvironmentObject var store: AppStore

    private var isInitialLoading: Bool {
        store.dataLoadState == .loading && store.sleepData.isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                if isInitialLoading {
                    ForgeSkeletonBlock(height: 88, cornerRadius: 16)
                    ForgeSkeletonBlock(height: 160, cornerRadius: 16)
                    ForgeSkeletonBlock(height: 120, cornerRadius: 16)
                } else if store.sleepData.isEmpty {
                    ForgeEmptyStateCard(
                        icon: "moon.zzz.fill",
                        title: "Connect Apple Health to unlock sleep",
                        message: "Forge reads last night's stages from Apple Health. Once a night lands, ARIA can explain recovery and bedtime.",
                        accent: Color(hex: "6366F1"),
                        cta: store.healthKitLive ? "Ask ARIA about tonight" : "Reconnect Apple Health",
                        action: {
                            if store.healthKitLive {
                                store.openChat(with: "How did I sleep last night, and what should I change tonight?", voice: false)
                            } else {
                                Task { await store.reconnectHealthKit() }
                            }
                        }
                    )
                } else {
                    EnergyScheduleCard()
                    SleepLastNightStrip()
                    AISleepPredictionCard()
                    AISmartRecommendationsView()
                    SleepStreakCard()
                    SleepWeekRhythm()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
    }
}

struct SleepNightTab: View {
    @EnvironmentObject var store: AppStore
    @Binding var showPersonalization: Bool
    @State private var showSounds = false

    private var coach: SleepBedtimeCoach {
        SleepBedtimeCoach.make(from: store.sleepData)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                SleepTonightHero(coach: coach)
                SleepEveningStoryCard(store: store, coach: coach)
                SleepWindDownRitual(coach: coach, onSounds: { showSounds = true })
                SleepTonightSoundDock(onMore: { showSounds = true })
                Button {
                    store.openChat(with: coach.ariaPrompt, voice: false)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.ember)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask ARIA to get you to bed")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.textPrimary)
                            Text(coach.phase == .dayplan
                                 ? "A short landing plan for tonight"
                                 : "No score. Just the next step.")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.ember)
                    }
                    .padding(16)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.ember.opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                AISleepEnvironmentView()
                SleepLastNightDetail()
                ChronotypeBadge(onTap: { showPersonalization = true })
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
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

struct SleepTonightHero: View {
    let coach: SleepBedtimeCoach

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let live = coach.advancing(now: context.date)
            VStack(alignment: .leading, spacing: 14) {
                Text("TONIGHT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(.textTertiary)
                Text(live.headline)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(live.bedtimeLabel)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.aurora)
                        .monospacedDigit()
                    Text(live.countdownLabel == "now" ? "lights out" : "in \(live.countdownLabel)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                Text(live.cue)
                    .font(.system(size: 14))
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
        guard let night = store.sleepData.first else { return nil }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("EVENING NARRATIVE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.textTertiary)
            Text(story)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(plan)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Wind-down \(coach.countdownLabel == "now" ? "is now" : "in \(coach.countdownLabel)") · lights out \(coach.bedtimeLabel)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.aurora)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            Text("GET TO BED")
                .font(.system(size: 11, weight: .semibold))
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
                        : "Lights and screens down. Melatonin does not argue with a bright kitchen."
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
                           ? "Charge it outside the bed. The next scroll is not worth tomorrow."
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
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.aurora)
                .frame(width: 28, height: 28)
                .background(Color.aurora.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SleepTonightSoundDock: View {
    var onMore: () -> Void
    private let player = SleepWindDownPlayer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WIND-DOWN SOUND")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(.textTertiary)
                Spacer()
                Button("Library", action: onMore)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.aurora)
            }

            if player.isPlaying {
                HStack(spacing: 12) {
                    Image(systemName: player.kind.icon)
                        .foregroundStyle(player.kind.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.kind.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(player.remainingLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .monospacedDigit()
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
                .padding(16)
                .background(Color.aurora.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SleepSoundKind.tonightPicks) { kind in
                            Button {
                                FDS.haptic(.medium)
                                player.start(kind: kind, minutes: 30)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: kind.icon)
                                    Text(kind.displayName)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
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
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
        }
    }
}

struct SleepLastNightStrip: View {
    @EnvironmentObject var store: AppStore

    private var night: SleepData? { store.sleepData.first }

    var body: some View {
        if let night {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Last night")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textTertiary)
                    Spacer()
                    Text("\(night.efficiencyPercent)% efficient")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.aurora)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(EnergySchedule.durationLabel(night.totalHours))
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                    Text("asleep")
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("\(night.clock(night.onset)) → \(night.clock(night.wake))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .monospacedDigit()
                }
                SleepHypnogram(night: night, height: 54)
                SleepStageLegend(night: night)
            }
        } else {
            Text("Last night will show duration, stages, and efficiency once Apple Health is connected.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
        }
    }
}

struct SleepLastNightDetail: View {
    @EnvironmentObject var store: AppStore

    private var night: SleepData? { store.sleepData.first }

    var body: some View {
        if let night {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last night")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
                HStack(alignment: .firstTextBaseline) {
                    Text(EnergySchedule.durationLabel(night.totalHours))
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(night.score)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                        Text("score")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                }
                Text("\(night.clock(night.onset))  →  \(night.clock(night.wake))   ·   \(night.efficiencyPercent)% of time in bed was sleep")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                SleepHypnogram(night: night, height: 92)
                HStack(spacing: 0) {
                    nightStat("Deep", "\(night.deepMinutes)m", Color.steel)
                    nightStat("REM", "\(night.remMinutes)m", Color.aurora)
                    nightStat("Light", "\(night.lightMinutes)m", Color(hex: "64748B"))
                    nightStat("Awake", "\(night.awakeMinutes)m", Color.danger.opacity(0.8))
                }
                .padding(.top, 4)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No night on file")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Connect Apple Health and last night will land here — stages, efficiency, and the energy day it built.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private func nightStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pillow-style stage map: stacked bands from time-in-bed, not a hairline.
struct SleepHypnogram: View {
    let night: SleepData
    var height: CGFloat = 64

    private var bands: [(id: String, color: Color, minutes: Int, y: CGFloat)] {
        [
            ("awake", Color.danger.opacity(0.75), night.awakeMinutes, 0.08),
            ("rem", Color.aurora, night.remMinutes, 0.30),
            ("light", Color(hex: "64748B"), night.lightMinutes, 0.54),
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
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(bands, id: \.id) { band in
                        let share = CGFloat(band.minutes) / CGFloat(total)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(band.color)
                            .frame(
                                width: max(band.minutes > 0 ? 6 : 0, w * share - 2),
                                height: height * (1 - band.y * 0.35)
                            )
                    }
                }
                .padding(6)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Sleep stages. Deep \(night.deepMinutes) minutes, REM \(night.remMinutes), light \(night.lightMinutes), awake \(night.awakeMinutes).")
    }
}

struct SleepStageLegend: View {
    let night: SleepData

    var body: some View {
        HStack(spacing: 12) {
            legend("Deep", night.deepMinutes, Color.steel)
            legend("REM", night.remMinutes, Color.aurora)
            legend("Light", night.lightMinutes, Color(hex: "64748B"))
            legend("Awake", night.awakeMinutes, Color.danger.opacity(0.75))
        }
    }

    private func legend(_ name: String, _ minutes: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(minutes)m")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textTertiary)
                .monospacedDigit()
        }
    }
}

struct SleepWeekRhythm: View {
    @EnvironmentObject var store: AppStore

    private var nights: [SleepData] {
        Array(store.sleepData.prefix(7).reversed())
    }

    private var need: Double {
        EnergySchedule.make(from: store.sleepData)?.needHours ?? 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textTertiary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(nights) { night in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(night.totalHours >= need - 0.4 ? Color.ember.opacity(0.88) : Color.aurora.opacity(0.28))
                            .frame(height: max(10, CGFloat(night.totalHours / 10) * 78))
                        Text(weekday(night.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(weekday(night.date)), \(EnergySchedule.durationLabel(night.totalHours))")
                }
            }
            .frame(height: 102, alignment: .bottom)
        }
    }

    private func weekday(_ value: String) -> String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: value) else { return "" }
        let out = DateFormatter()
        out.setLocalizedDateFormatFromTemplate("EEEEE")
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

