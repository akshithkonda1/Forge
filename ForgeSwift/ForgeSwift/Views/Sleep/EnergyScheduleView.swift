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
        debtLevel == .clear ? "Square on sleep" : String(format: "%.1fh short stretch", debtHours)
    }

    var debtDetail: String {
        let need = String(format: "%.1f", needHours)
        switch debtLevel {
        case .clear:
            return "Against a \(need)h need, over \(nightsUsed) nights. Nothing extra to add tonight."
        case .mild:
            return "Against a \(need)h need, over \(nightsUsed) nights. About 25 extra minutes a night is enough."
        case .heavy:
            return "Against a \(need)h need, over \(nightsUsed) nights. A short stretch — keep the extra minutes small."
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

    /// A schedule hour (may exceed 24, e.g. 25.5 for 1:30 AM the next day) as
    /// a formatted clock time. Shared so any card quoting a real time from
    /// this schedule — not just `EnergyScheduleCard`'s own chart — renders it
    /// identically rather than reimplementing the wraparound.
    static func clockLabel(_ hour: Double, calendar: Calendar = .current) -> String {
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
        let nights: [CircadianRhythm.Night] = SleepCircadianBridge.nights(from: history)

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
        case .eveningPeak:     return "sunset"
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

    /// Plot height scales a little with Dynamic Type, capped so the chart
    /// never swallows the screen at accessibility sizes.
    @ScaledMetric(relativeTo: .caption) private var plotHeightSize: CGFloat = 132

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Cheap identity for the night history — enough to notice a new night, a
    /// re-score, or a HealthKit refresh, without hashing fourteen structs on
    /// every render pass.
    private var historyFingerprint: String {
        let latest = store.sleepData.first
        return "\(store.sleepData.count)|\(latest?.date ?? "")|\(latest?.totalHours ?? 0)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header
            if let schedule = schedule {
                debtBlock(schedule)
                Divider().background(Color.white.opacity(0.08))
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
        .forgeContentCard(tint: .steel)
        .animation(reduceMotion ? nil : ForgeMotion.snappy, value: schedule?.debtHours)
        .forgeHaptic(.selection, trigger: scrubWindow)
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
        ForgeCardHeader("Today's energy", tint: .steel)
    }

    // ------------------------------------------------------------
    // MARK: Debt
    // ------------------------------------------------------------

    private func debtTint(_ level: EnergySchedule.DebtLevel) -> Color {
        switch level {
        case .clear: return .vitality
        case .mild:  return .amber
        case .heavy: return ForgeProgressChrome.miss
        }
    }

    private func debtIcon(_ level: EnergySchedule.DebtLevel) -> String {
        switch level {
        case .clear: return "checkmark.seal.fill"
        case .mild: return "moon.zzz.fill"
        case .heavy: return "exclamationmark.triangle.fill"
        }
    }

    private func debtAction(_ level: EnergySchedule.DebtLevel) -> String {
        switch level {
        case .clear: return "You're square. Keep the window steady tonight."
        case .mild: return "One steady week clears it — protect the last hour before bed."
        case .heavy: return "Skip the late scroll. Bank an extra 45 min the next 3 nights."
        }
    }

    private func debtBlock(_ schedule: EnergySchedule) -> some View {
        let tint = debtTint(schedule.debtLevel)
        return VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: debtIcon(schedule.debtLevel), tint: tint)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(schedule.debtHeadline)
                        .font(HomeType.metric)
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                        .lineLimit(2)
                        .minimumScaleFactor(ForgeLayout.valueMinScale)
                        .layoutPriority(1)
                    Text(schedule.debtDetail)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                Spacer(minLength: 0)
            }
            // Actionable next step — the one thing to do tonight, not a number to stare at.
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(debtAction(schedule.debtLevel))
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeWell()
            .background(
                RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // ------------------------------------------------------------
    // MARK: Chart
    // ------------------------------------------------------------

    private func chart(_ schedule: EnergySchedule) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Subtle horizontal grid — 3 lines so the curve has a reference without a y-axis to read.
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { i in
                            Rectangle().fill(Color.white.opacity(0.12))
                                .frame(height: 1)
                            if i < 2 { Spacer() }
                        }
                    }
                    sleepShade(schedule, size: geo.size)
                    areaPath(schedule, size: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [Color.steel.opacity(0.30), Color.steel.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(drawProgress)
                    linePath(schedule, size: geo.size)
                        .trim(from: 0, to: drawProgress)
                        .stroke(
                            Color.steel,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                    marker(schedule, size: geo.size)
                        .opacity(drawProgress)
                }
                .contentShape(Rectangle())
                .gesture(scrubGesture(schedule, width: geo.size.width))
            }
            .frame(height: ForgeLayout.scaledCap(plotHeightSize, base: 132))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chartDescription(schedule))

            axis(schedule)
            HStack(alignment: .top, spacing: ForgeLayout.chipGap) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
                Text("Drag the curve — or tap a time — to see that moment")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
                Spacer(minLength: 0)
            }
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
                if reduceMotion {
                    scrubOffset = nil
                } else {
                    withAnimation(ForgeMotion.smooth) {
                        scrubOffset = nil
                    }
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
            .fill(Color.steel.opacity(0.10))
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
        .animation(reduceMotion ? nil : ForgeMotion.snappy, value: scrubbing)
    }

    /// Four ticks across the waking day, labelled in clock time. The axis starts
    /// at habitual wake rather than midnight, so it reads as the user's day.
    private func axis(_ schedule: EnergySchedule) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(stride(from: 0.0, to: 24.0, by: 6.0)), id: \.self) { offset in
                Text(clockLabel(schedule.phase.wakeHour + offset))
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        return VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                Image(systemName: point.window.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(point.window.tint)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    focusTitleRow(point.window, hour: point.hour, scrubbing: scrubbing)
                    Text(point.window.guidance)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                Spacer(minLength: 0)
            }

            if !scrubbing, let upcoming = schedule.upcoming {
                HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    nextLine(upcoming.window, startsInHours: upcoming.startsInHours)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .animation(reduceMotion ? nil : ForgeMotion.snappy, value: point.window)
        .animation(reduceMotion ? nil : ForgeMotion.snappy, value: scrubbing)
        .accessibilityElement(children: .combine)
    }

    private func focusTitleRow(_ window: CircadianRhythm.Window, hour: Double, scrubbing: Bool) -> some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.chipGap, alignment: .firstTextBaseline) {
            Text(window.title)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            // Only stamped while scrubbing. At rest the block is
            // about now, and labelling that with a clock time would
            // invite reading it as a scheduled event.
            if scrubbing {
                Text(clockLabel(hour))
                    .font(HomeType.micro)
                    .foregroundStyle(window.tint)
                    .lineLimit(1)
                    .padding(.horizontal, FDS.Spacing.sm)
                    .padding(.vertical, FDS.Spacing.xs)
                    .background(window.tint.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(window.tint.opacity(0.28), lineWidth: 0.8))
                    .forgeTransition(.scale.combined(with: .opacity))
            }
        }
    }

    /// One Text so the label and the relative time wrap as a unit.
    private func nextLine(_ window: CircadianRhythm.Window, startsInHours: Double) -> some View {
        let relative = Text(relativeLabel(startsInHours)).foregroundStyle(window.tint)
        return Text("Next: \(window.title) \(relative)")
            .font(HomeType.body)
            .foregroundStyle(Color.textSecondary)
            .forgeWrapping()
    }

    // ------------------------------------------------------------
    // MARK: Evening
    // ------------------------------------------------------------

    private func eveningBlock(_ schedule: EnergySchedule) -> some View {
        ForgeStatGrid(columns: 2) {
            ForgeStatTile(label: "Dim the lights",
                          value: clockLabel(schedule.melatoninHour),
                          energy: .steel,
                          icon: "moon.stars.fill")
            ForgeStatTile(label: "Body expects bed",
                          value: clockLabel(schedule.phase.onsetHour),
                          energy: .steel,
                          icon: "bed.double.fill")
        }
    }

    // ------------------------------------------------------------
    // MARK: Hedges and empty state
    // ------------------------------------------------------------

    private func hedge(_ schedule: EnergySchedule) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: "exclamationmark.triangle.fill", tint: .amber)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Rough read — bedtimes moved around")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(schedule.unreliableNote)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .background(
            RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
                .fill(Color.amber.opacity(0.08))
        )
    }

    /// Shown until there are enough nights with real bedtimes to place a phase.
    /// Inventing a schedule from three nights would be worse than waiting: the
    /// failure mode is telling someone their slump is at 4am.
    private var learningState: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeEmptyNote(
                title: "Still learning your rhythm",
                message: "Once there are about five nights with bedtimes recorded, this becomes your short stretch and an hour-by-hour read on the day ahead. Log in-bed windows on Tonight, or connect Apple Health.",
                systemImage: "waveform.path.ecg",
                tint: .steel
            )
            ForgeChip(label: "About \(EnergySchedule.minimumNights) nights", energy: .steel)
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.steel)
                    .accessibilityHidden(true)
                Text("Tip: Tonight → I'm in bed builds the fastest signal")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeWell()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // ------------------------------------------------------------
    // MARK: Formatting
    // ------------------------------------------------------------

    private func clockLabel(_ hour: Double, calendar: Calendar = .current) -> String {
        EnergySchedule.clockLabel(hour, calendar: calendar)
    }

    private func relativeLabel(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        if minutes < 60 { return "in \(max(1, minutes)) min" }
        let wholeHours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "in \(wholeHours)h" : "in \(wholeHours)h \(remainder)m"
    }
}
