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
        debtLevel == .clear ? "Square" : Self.durationLabel(debtHours)
    }

    var debtCaption: String {
        debtLevel == .clear ? "No sleep debt" : "Sleep debt"
    }

    var debtDetail: String {
        let need = Self.durationLabel(needHours)
        switch debtLevel {
        case .clear:
            return "Need \(need) · \(nightsUsed) nights. Nothing to pay back."
        case .mild:
            return "Need \(need) · \(nightsUsed) nights. An extra half hour a night clears it this week."
        case .heavy:
            return "Need \(need) · \(nightsUsed) nights. More than one long morning will pay this down."
        }
    }

    /// Training read — Forge, not RISE. Energy is for the session, not a mood ring.
    var forgeRead: String {
        switch currentWindow {
        case .morningPeak, .eveningPeak:
            return "A good window to train if readiness agrees."
        case .afternoonDip, .grogginess:
            return "Keep the session easy, or push it later."
        case .melatoninWindow, .windingDown, .sleep:
            return "The work is over. Protect the night."
        }
    }

    static func durationLabel(_ hours: Double) -> String {
        let total = max(0, Int((hours * 60).rounded()))
        let h = total / 60
        let m = total % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// Shown instead of a confident schedule when the nights disagree.
    var unreliableNote: String {
        "Your bedtimes have moved around a lot lately, so this schedule is a rough read rather than a firm one."
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

    /// Ribbon colour — warmer peaks, cooler night. RISE’s map, Forge’s palette.
    var ribbon: Color {
        switch self {
        case .sleep:           return Color(hex: "312E81")
        case .grogginess:      return Color(hex: "64748B")
        case .morningPeak:     return Color(hex: "FFB84D")
        case .afternoonDip:    return Color(hex: "5B8DEF")
        case .eveningPeak:     return Color(hex: "FF6B2B")
        case .melatoninWindow: return Color(hex: "A78BFA")
        case .windingDown:     return Color(hex: "818CF8")
        }
    }
}

// ============================================================
// MARK: - Card
// ============================================================

/// Sleep debt and the shape of the day — RISE’s energy map, drawn in Forge.
/// Sits on the page, not in a card. The curve is the product.
struct EnergyScheduleCard: View {
    @EnvironmentObject var store: AppStore

    /// "Right now" has to keep being now while the screen is open, and a stale
    /// marker on a live chart is worse than no marker.
    @State private var now = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var schedule: EnergySchedule? {
        EnergySchedule.make(from: store.sleepData, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let schedule = schedule {
                debtBlock(schedule)
                chart(schedule)
                if !schedule.isReliable {
                    hedge(schedule)
                }
                nowBlock(schedule)
                eveningBlock(schedule)
            } else {
                learningState
            }
        }
        .onReceive(tick) { now = $0 }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(schedule.debtCaption.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .tracking(1.4)
            Text(schedule.debtHeadline)
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(debtTint(schedule.debtLevel))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 2)
            Text(schedule.debtDetail)
                .font(.system(size: 14))
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
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    sleepShade(schedule, size: geo.size)
                    areaPath(schedule, size: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.ember.opacity(0.22),
                                    Color.aurora.opacity(0.10),
                                    Color.indigo.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    ribbon(schedule, size: geo.size)
                    nowMarker(schedule, size: geo.size)
                }
            }
            .frame(height: 196)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chartDescription(schedule))

            axis(schedule)
        }
    }

    /// Phase-coloured stroke — peaks run warm, night runs indigo.
    private func ribbon(_ schedule: EnergySchedule, size: CGSize) -> some View {
        Canvas { context, size in
            guard schedule.samples.count > 1 else { return }
            for index in 1..<schedule.samples.count {
                let previous = schedule.samples[index - 1]
                let sample = schedule.samples[index]
                var segment = Path()
                segment.move(to: CGPoint(
                    x: x(previous.sinceWake, size.width),
                    y: y(schedule, previous.energy, size.height)
                ))
                segment.addLine(to: CGPoint(
                    x: x(sample.sinceWake, size.width),
                    y: y(schedule, sample.energy, size.height)
                ))
                let window = CircadianRhythm.window(atHour: previous.clockHour, phase: schedule.phase)
                context.stroke(
                    segment,
                    with: .color(window.ribbon),
                    style: StrokeStyle(lineWidth: 2.75, lineCap: .round, lineJoin: .round)
                )
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

    private func nowMarker(_ schedule: EnergySchedule, size: CGSize) -> some View {
        let position = x(schedule.nowSinceWake, size.width)
        let markerY = y(schedule, schedule.currentEnergy, size.height)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.textPrimary.opacity(0.55))
                .frame(width: 1, height: size.height)
                .offset(x: position)
            Text("NOW")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.textPrimary)
                .offset(x: position > size.width - 36 ? position - 32 : position + 6, y: 0)
            Circle()
                .fill(Color.textPrimary)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.background, lineWidth: 2.5))
                .offset(x: position - 4.5, y: markerY - 4.5)
        }
    }

    /// Four ticks across the waking day, labelled in clock time. The axis starts
    /// at habitual wake rather than midnight, so it reads as the user's day.
    private func axis(_ schedule: EnergySchedule) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(stride(from: 0.0, to: 24.0, by: 6.0)), id: \.self) { offset in
                Text(clockLabel(schedule.phase.wakeHour + offset))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: offset == 0 ? .leading : (offset == 18 ? .trailing : .center))
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

    private func nowBlock(_ schedule: EnergySchedule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(schedule.currentWindow.ribbon)
                    .frame(width: 8, height: 8)
                    .offset(y: -1)
                Text(schedule.currentWindow.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer(minLength: 0)
                if let upcoming = schedule.upcoming {
                    Text("\(upcoming.window.title) \(relativeLabel(upcoming.startsInHours))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.trailing)
                }
            }
            Text(schedule.currentWindow.guidance)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(schedule.forgeRead)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.ember)
        }
        .accessibilityElement(children: .combine)
    }

    // ------------------------------------------------------------
    // MARK: Evening
    // ------------------------------------------------------------

    private func eveningBlock(_ schedule: EnergySchedule) -> some View {
        HStack(alignment: .top, spacing: 0) {
            eveningStat(label: "Dim lights", value: clockLabel(schedule.melatoninHour))
            eveningStat(label: "In bed", value: clockLabel(schedule.phase.onsetHour))
            eveningStat(label: "Wake", value: clockLabel(schedule.phase.wakeHour))
        }
        .padding(.top, 4)
    }

    private func eveningStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Learning your rhythm")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("Five nights with real bedtimes and this becomes sleep debt plus an hour-by-hour read on the day ahead. Until then we won’t invent a schedule.")
                .font(.system(size: 15))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
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
