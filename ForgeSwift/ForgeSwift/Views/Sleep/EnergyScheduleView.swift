import SwiftUI
import Combine
import ForgeCore

// ============================================================
// MARK: - Schedule assembly
// ============================================================

/// Everything the energy card draws, computed in one pass so the view body is a
/// pure function of a value rather than a pile of repeated recomputation.
struct EnergySchedule {

    /// One sample of the curve, positioned by hours since habitual wake.
    ///
    /// The chart reads left-to-right as the user's own day — grogginess, peak,
    /// dip, second wind, then the night. That is not the same thing as a
    /// midnight-anchored calendar day, and it is considerably easier to
    /// recognise yourself in.
    struct Sample {
        let sinceWake: Double
        let clockHour: Double
        let energy: Double
    }

    enum DebtLevel {
        case clear, mild, heavy
    }

    let phase: CircadianRhythm.Phase
    let needHours: Double
    let debtHours: Double
    let nightsUsed: Int
    let samples: [Sample]
    let nowHour: Double
    let currentEnergy: Double
    let currentWindow: CircadianRhythm.Window
    let upcoming: (window: CircadianRhythm.Window, startsInHours: Double)?
    /// Vertical bounds the chart is drawn against. See `plotted(_:)`.
    let energyFloor: Double
    let energySpan: Double

    /// Fewer nights than this and the estimate is guesswork wearing a chart.
    /// Matches the threshold `CircadianRhythm.sleepNeedHours` uses before it
    /// will commit to anything beyond the population default.
    static let minimumNights = 5

    /// Below this, bedtimes vary so much that there is no single phase to
    /// report. Saying so is the correct output — see `unreliableNote`.
    static let minimumConfidence = 0.35

    // ------------------------------------------------------------
    // MARK: Derived
    // ------------------------------------------------------------

    var isReliable: Bool { phase.confidence >= Self.minimumConfidence }
    var nowSinceWake: Double { CircadianRhythm.normalizedHour(nowHour - phase.wakeHour) }
    var awakeSpan: Double { CircadianRhythm.normalizedHour(phase.onsetHour - phase.wakeHour) }
    var melatoninHour: Double { CircadianRhythm.melatoninOnsetHour(phase: phase) }

    /// Where a sample sits vertically, 0 at the bottom of the plot.
    ///
    /// The curve never spans the full 0–1 range — a real day runs somewhere
    /// around 0.25 to 0.8 — so the chart is scaled to the day's own span.
    /// It shows shape and timing, which is what it is for. It is not a gauge,
    /// and nothing in the card invites reading an absolute number off it.
    func plotted(_ energy: Double) -> Double {
        guard energySpan > 0 else { return 0.5 }
        return min(1, max(0, (energy - energyFloor) / energySpan))
    }

    var debtLevel: DebtLevel {
        if debtHours < 2 { return .clear }
        if debtHours < 8 { return .mild }
        return .heavy
    }

    var debtHeadline: String {
        debtLevel == .clear ? "Square on sleep" : String(format: "%.1f hours of sleep debt", debtHours)
    }

    var debtDetail: String {
        let need = String(format: "%.1f", needHours)
        switch debtLevel {
        case .clear:
            return "Against a \(need)h need, over \(nightsUsed) nights. Nothing to pay back."
        case .mild:
            return "Against a \(need)h need, over \(nightsUsed) nights. An extra half hour a night clears it inside a week."
        case .heavy:
            return "Against a \(need)h need, over \(nightsUsed) nights. More than one long lie-in will pay this down."
        }
    }

    /// Shown instead of a confident schedule when the nights disagree.
    var unreliableNote: String {
        "Your bedtimes have moved around a lot lately, so this schedule is a rough read rather than a firm one."
    }

    /// Sleep duration as "7h 12m". Minutes are rounded so 7.996 never becomes 7h 60m.
    static func durationLabel(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // ------------------------------------------------------------
    // MARK: Build
    // ------------------------------------------------------------

    static func make(from history: [SleepData],
                     now: Date = Date(),
                     calendar: Calendar = .current) -> EnergySchedule? {
        // History arrives newest-first from HealthKit, and every rolling window
        // in the engine is a `suffix(...)`. Handing it the array in arrival
        // order would silently analyse the *oldest* fortnight — a schedule
        // that was right for whoever the user was last month.
        let nights: [CircadianRhythm.Night] = history
            .compactMap { entry -> CircadianRhythm.Night? in
                guard let onset = entry.onset, let wake = entry.wake, wake > onset else { return nil }
                return CircadianRhythm.Night(onset: onset, wake: wake, asleepHours: entry.totalHours)
            }
            .sorted { $0.wake < $1.wake }

        guard nights.count >= minimumNights,
              let phase = CircadianRhythm.phase(from: nights, calendar: calendar) else { return nil }

        let need = CircadianRhythm.sleepNeedHours(from: nights)
        let debt = CircadianRhythm.sleepDebtHours(nights: nights, need: need)
        let nowHour = CircadianRhythm.hourOfDay(now, calendar: calendar)

        let samples = CircadianRhythm
            .curve(phase: phase, sleepDebtHours: debt, sleepNeedHours: need, samplesPerHour: 6)
            .map { point in
                Sample(sinceWake: CircadianRhythm.normalizedHour(point.hour - phase.wakeHour),
                       clockHour: point.hour,
                       energy: point.energy)
            }
            .sorted { $0.sinceWake < $1.sinceWake }

        let values = samples.map(\.energy)
        let low = (values.min() ?? 0) - 0.04
        let high = (values.max() ?? 1) + 0.04

        return EnergySchedule(
            phase: phase,
            needHours: need,
            debtHours: debt,
            nightsUsed: nights.count,
            samples: samples,
            nowHour: nowHour,
            currentEnergy: CircadianRhythm.energy(
                atHour: nowHour,
                phase: phase,
                hoursAwake: CircadianRhythm.hoursAwake(atHour: nowHour, phase: phase),
                sleepDebtHours: debt,
                sleepNeedHours: need
            ),
            currentWindow: CircadianRhythm.window(atHour: nowHour, phase: phase),
            upcoming: CircadianRhythm.nextWindow(afterHour: nowHour, phase: phase),
            energyFloor: low,
            energySpan: max(0.0001, high - low)
        )
    }
}

// ============================================================
// MARK: - Window presentation
// ============================================================

extension CircadianRhythm.Window {
    var symbolName: String {
        switch self {
        case .sleep:           return "moon.zzz.fill"
        case .grogginess:      return "cloud.fog.fill"
        case .morningPeak:     return "sun.max.fill"
        case .afternoonDip:    return "arrow.down.right.circle.fill"
        case .eveningPeak:     return "sparkles"
        case .melatoninWindow: return "moon.stars.fill"
        case .windingDown:     return "sunset.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sleep:           return .indigo
        case .grogginess:      return .textSecondary
        case .morningPeak:     return .amber
        case .afternoonDip:    return .steel
        case .eveningPeak:     return .ember
        case .melatoninWindow: return .aurora
        case .windingDown:     return .steelLight
        }
    }
}

// ============================================================
// MARK: - Card
// ============================================================

/// Sleep debt and the shape of the day ahead — the two things a night of sleep
/// data can actually tell you that a duration cannot.
struct EnergyScheduleCard: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// "Right now" has to keep being now while the screen is open, and a stale
    /// marker on a live chart is worse than no marker.
    @State private var now = Date()

    /// Held rather than recomputed per render.
    ///
    /// `body` re-runs whenever `AppStore` publishes anything at all — it is one
    /// large observable shared by every tab — and rebuilding a 144-sample curve
    /// on each of those is work nobody asked for. Refreshed on the three things
    /// that can actually change it: appearing, the minute turning over, and new
    /// night data arriving.
    @State private var schedule: EnergySchedule?

    /// Drives the curve drawing itself in rather than appearing all at once.
    @State private var drawProgress: CGFloat = 0

    /// Hours since wake currently under the finger, or nil when not scrubbing.
    @State private var scrubOffset: Double?
    /// Only used to fire one haptic per window crossed, rather than per pixel.
    @State private var scrubWindow: CircadianRhythm.Window?

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Cheap identity for the night history — enough to notice a new night, a
    /// re-score, or a HealthKit refresh, without hashing fourteen structs on
    /// every render pass.
    private var historyFingerprint: String {
        let latest = store.sleepData.first
        return "\(store.sleepData.count)|\(latest?.date ?? "")|\(latest?.totalHours ?? 0)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let schedule = schedule {
                debtBlock(schedule)
                chart(schedule)
                if !schedule.isReliable {
                    hedge(schedule)
                }
                focusBlock(schedule)
                eveningBlock(schedule)
            } else {
                learningState
            }
        }
        .padding(18)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .animation(.snappy(duration: 0.32), value: schedule?.debtHours)
        .sensoryFeedback(.selection, trigger: scrubWindow)
        .onAppear {
            refresh(at: now)
            guard drawProgress == 0 else { return }
            if reduceMotion {
                drawProgress = 1
            } else {
                withAnimation(.easeOut(duration: 0.9).delay(0.15)) { drawProgress = 1 }
            }
        }
        .onReceive(tick) { instant in
            now = instant
            refresh(at: instant)
        }
        .onChange(of: historyFingerprint) { _, _ in refresh(at: now) }
    }

    /// Takes the instant explicitly rather than reading `now`, so the minute
    /// tick cannot depend on when a `@State` write becomes visible to a read in
    /// the same closure.
    private func refresh(at instant: Date) {
        schedule = EnergySchedule.make(from: store.sleepData, now: instant)
    }

    // ------------------------------------------------------------
    // MARK: Header
    // ------------------------------------------------------------

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.aurora)
            Text("Today's energy")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            Spacer()
        }
    }

    // ------------------------------------------------------------
    // MARK: Debt
    // ------------------------------------------------------------

    private func debtTint(_ level: EnergySchedule.DebtLevel) -> Color {
        switch level {
        case .clear: return .vitality
        case .mild:  return .amber
        case .heavy: return .alert
        }
    }

    private func debtBlock(_ schedule: EnergySchedule) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(schedule.debtHeadline)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(debtTint(schedule.debtLevel))
                // The figure moves by tenths as nights land; rolling the digits
                // reads as the same number updating rather than a new one.
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(schedule.debtDetail)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // ------------------------------------------------------------
    // MARK: Chart
    // ------------------------------------------------------------

    private func chart(_ schedule: EnergySchedule) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    sleepShade(schedule, size: geo.size)
                    areaPath(schedule, size: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [Color.aurora.opacity(0.34), Color.aurora.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(drawProgress)
                    linePath(schedule, size: geo.size)
                        .trim(from: 0, to: drawProgress)
                        .stroke(
                            LinearGradient(
                                colors: [.amber, .aurora, .steel],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                    marker(schedule, size: geo.size)
                        .opacity(drawProgress)
                }
                .contentShape(Rectangle())
                .gesture(scrubGesture(schedule, width: geo.size.width))
            }
            .frame(height: 126)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chartDescription(schedule))

            axis(schedule)
        }
    }

    // ------------------------------------------------------------
    // MARK: Scrubbing
    // ------------------------------------------------------------

    /// What the detail block is describing: wherever the finger is, or now.
    private func focus(_ schedule: EnergySchedule) -> (offset: Double,
                                                       hour: Double,
                                                       energy: Double,
                                                       window: CircadianRhythm.Window) {
        guard let offset = scrubOffset else {
            return (schedule.nowSinceWake, schedule.nowHour,
                    schedule.currentEnergy, schedule.currentWindow)
        }
        let hour = CircadianRhythm.normalizedHour(schedule.phase.wakeHour + offset)
        let energy = CircadianRhythm.energy(
            atHour: hour,
            phase: schedule.phase,
            hoursAwake: CircadianRhythm.hoursAwake(atHour: hour, phase: schedule.phase),
            sleepDebtHours: schedule.debtHours,
            sleepNeedHours: schedule.needHours
        )
        return (offset, hour, energy, CircadianRhythm.window(atHour: hour, phase: schedule.phase))
    }

    /// Drag anywhere on the curve to read the day at that hour.
    ///
    /// `minimumDistance: 0` so a tap works as well as a drag — the common
    /// gesture is a thumb landing on "about lunchtime", not a careful sweep.
    private func scrubGesture(_ schedule: EnergySchedule, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fraction = Double(value.location.x / max(1, width))
                let offset = min(24, max(0, fraction * 24))
                scrubOffset = offset
                // One haptic per window boundary crossed. Firing per pixel
                // would buzz continuously across a swipe.
                let window = CircadianRhythm.window(
                    atHour: CircadianRhythm.normalizedHour(schedule.phase.wakeHour + offset),
                    phase: schedule.phase
                )
                if window != scrubWindow { scrubWindow = window }
            }
            .onEnded { _ in
                scrubWindow = nil
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    scrubOffset = nil
                }
            }
    }

    private func x(_ sinceWake: Double, _ width: CGFloat) -> CGFloat {
        width * CGFloat(min(24, max(0, sinceWake)) / 24)
    }

    private func y(_ schedule: EnergySchedule, _ energy: Double, _ height: CGFloat) -> CGFloat {
        height * CGFloat(1 - schedule.plotted(energy))
    }

    private func linePath(_ schedule: EnergySchedule, size: CGSize) -> Path {
        var path = Path()
        for (index, sample) in schedule.samples.enumerated() {
            let point = CGPoint(x: x(sample.sinceWake, size.width),
                                y: y(schedule, sample.energy, size.height))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func areaPath(_ schedule: EnergySchedule, size: CGSize) -> Path {
        var path = linePath(schedule, size: size)
        guard let first = schedule.samples.first, let last = schedule.samples.last else { return path }
        path.addLine(to: CGPoint(x: x(last.sinceWake, size.width), y: size.height))
        path.addLine(to: CGPoint(x: x(first.sinceWake, size.width), y: size.height))
        path.closeSubpath()
        return path
    }

    /// The stretch the body expects to be asleep, shaded so the waking day is
    /// visibly the part of the chart that is about choices.
    private func sleepShade(_ schedule: EnergySchedule, size: CGSize) -> some View {
        let start = x(schedule.awakeSpan, size.width)
        return Rectangle()
            .fill(Color.indigo.opacity(0.12))
            .frame(width: max(0, size.width - start), height: size.height)
            .offset(x: start)
    }

    /// The readout line: on "now" at rest, following the finger while scrubbing.
    private func marker(_ schedule: EnergySchedule, size: CGSize) -> some View {
        let point = focus(schedule)
        let scrubbing = scrubOffset != nil
        let position = x(point.offset, size.width)
        let markerY = y(schedule, point.energy, size.height)
        let tint: Color = scrubbing ? point.window.tint : .textPrimary
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(tint.opacity(scrubbing ? 0.55 : 0.35))
                .frame(width: 1, height: size.height)
                .offset(x: position)
            Circle()
                .fill(tint)
                .frame(width: scrubbing ? 11 : 8, height: scrubbing ? 11 : 8)
                .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                .offset(x: position - (scrubbing ? 5.5 : 4),
                        y: markerY - (scrubbing ? 5.5 : 4))
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: scrubbing)
    }

    /// Four ticks across the waking day, labelled in clock time. The axis starts
    /// at habitual wake rather than midnight, so it reads as the user's day.
    private func axis(_ schedule: EnergySchedule) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(stride(from: 0.0, to: 24.0, by: 6.0)), id: \.self) { offset in
                Text(clockLabel(schedule.phase.wakeHour + offset))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: offset == 0 ? .leading : .center)
            }
        }
    }

    private func chartDescription(_ schedule: EnergySchedule) -> String {
        let peak = schedule.samples.max { $0.energy < $1.energy }
        let trough = schedule.samples
            .filter { $0.sinceWake > 2 && $0.sinceWake < schedule.awakeSpan - 2 }
            .min { $0.energy < $1.energy }
        var parts = ["Predicted energy across the day."]
        if let peak { parts.append("Highest around \(clockLabel(peak.clockHour)).") }
        if let trough { parts.append("Lowest around \(clockLabel(trough.clockHour)).") }
        parts.append("Right now: \(schedule.currentWindow.title).")
        return parts.joined(separator: " ")
    }

    // ------------------------------------------------------------
    // MARK: Right now / next
    // ------------------------------------------------------------

    private func focusBlock(_ schedule: EnergySchedule) -> some View {
        let point = focus(schedule)
        let scrubbing = scrubOffset != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: point.window.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(point.window.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(point.window.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        // Only stamped while scrubbing. At rest the block is
                        // about now, and labelling that with a clock time would
                        // invite reading it as a scheduled event.
                        if scrubbing {
                            Text(clockLabel(point.hour))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(point.window.tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(point.window.tint.opacity(0.14))
                                .clipShape(Capsule())
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Text(point.window.guidance)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !scrubbing, let upcoming = schedule.upcoming {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 22)
                    Text("Next: \(upcoming.window.title)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Text(relativeLabel(upcoming.startsInHours))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(upcoming.window.tint)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
        .animation(.snappy(duration: 0.22), value: point.window)
        .animation(.snappy(duration: 0.22), value: scrubbing)
        .accessibilityElement(children: .combine)
    }

    // ------------------------------------------------------------
    // MARK: Evening
    // ------------------------------------------------------------

    private func eveningBlock(_ schedule: EnergySchedule) -> some View {
        HStack(spacing: 0) {
            eveningStat(icon: "moon.stars.fill",
                        tint: .aurora,
                        label: "Dim the lights",
                        value: clockLabel(schedule.melatoninHour))
            Rectangle()
                .fill(Color.borderColor.opacity(0.5))
                .frame(width: 1, height: 30)
            eveningStat(icon: "bed.double.fill",
                        tint: .indigo,
                        label: "Body expects bed",
                        value: clockLabel(schedule.phase.onsetHour))
        }
    }

    private func eveningStat(icon: String, tint: Color, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // ------------------------------------------------------------
    // MARK: Hedges and empty state
    // ------------------------------------------------------------

    private func hedge(_ schedule: EnergySchedule) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.warning)
            Text(schedule.unreliableNote)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.warning.opacity(0.08))
        .cornerRadius(10)
    }

    /// Shown until there are enough nights with real bedtimes to place a phase.
    /// Inventing a schedule from three nights would be worse than waiting: the
    /// failure mode is telling someone their slump is at 4am.
    private var learningState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Still learning your rhythm")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("Once there are about five nights with bedtimes recorded, this becomes your sleep debt and an hour-by-hour read on the day ahead.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // ------------------------------------------------------------
    // MARK: Formatting
    // ------------------------------------------------------------

    private func clockLabel(_ hour: Double, calendar: Calendar = .current) -> String {
        let normalized = CircadianRhythm.normalizedHour(hour)
        var whole = Int(normalized)
        var minute = Int(((normalized - Double(whole)) * 60).rounded())
        // Rounding 7.996 gives 60 minutes, which is 08:00 and not 07:60.
        if minute >= 60 {
            minute = 0
            whole = (whole + 1) % 24
        }
        guard let date = calendar.date(bySettingHour: whole, minute: minute, second: 0, of: Date()) else {
            return String(format: "%02d:%02d", whole, minute)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func relativeLabel(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        if minutes < 60 { return "in \(max(1, minutes)) min" }
        let wholeHours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "in \(wholeHours)h" : "in \(wholeHours)h \(remainder)m"
    }
}
