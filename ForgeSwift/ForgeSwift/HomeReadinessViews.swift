import SwiftUI
import ForgeCore

struct BreakdownCardView: View {
    let label: String
    /// nil when the pillar was not measured; shows "—" instead of a fallback score.
    let value: Int?
    let inverted: Bool
    let index: Int
    @State private var appeared = false

    private var display: Int? { value.map { inverted ? 100 - $0 : $0 } }
    private var dot: Color { display.map { HomeReadiness.color($0) } ?? .textTertiary }

    var body: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Circle().fill(dot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(HomeType.micro)
                    .foregroundColor(.textTertiary)
                Text(display.map { "\($0)" } ?? "—")
                    .font(HomeType.metric)
                    .foregroundColor(.textPrimary)
            }
            Spacer()
        }
        .padding(FDS.Spacing.md)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .fill(Color.surfaceElevated.opacity(0.9))
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(Color.borderHairline, lineWidth: 1)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(ForgeMotion.gentle.delay(0.05 * Double(index))) { appeared = true }
        }
    }
}

struct ReadinessInsightRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: FDS.Spacing.md) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 15)).foregroundColor(color)
            }
            Text(title)
                .font(HomeType.status)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(HomeType.label)
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, FDS.Spacing.xs)
    }
}

struct ReadinessRingView: View {
    let score: Int
    let size: CGFloat
    let strokeWidth: CGFloat
    var showLabel: Bool = true

    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { HomeReadiness.color(score) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)

            // Solid band color; the arc length is the data. No blur halos.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))

            if progress > 0.02 {
                Circle()
                    .fill(color)
                    .frame(width: strokeWidth * 0.85, height: strokeWidth * 0.85)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(-90 + Double(progress) * 360))
            }

            if showLabel {
                VStack(spacing: FDS.Spacing.xs) {
                    Text("\(score)")
                        .font(ForgeFont.sans(size * 0.26, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .contentTransition(.numericText(value: Double(score)))
                        .forgeAnimation(ForgeMotion.smooth, value: score)
                    Text(HomeReadiness.label(score).uppercased())
                        .font(ForgeFont.sans(size * 0.07, weight: .semibold))
                        .foregroundColor(color)
                        .tracking(1.6)
                    Text("Readiness")
                        .font(ForgeFont.sans(size * 0.055, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        // Without its label the ring is decoration beside a name or a score.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeReadiness.voiceOverLabel(score))
        .accessibilityHidden(!showLabel)
        .onAppear {
            // The arc sweeps in once; under Reduce Motion it is simply there.
            if reduceMotion {
                progress = CGFloat(score) / 100
            } else {
                withAnimation(ForgeMotion.sweep.delay(0.2)) { progress = CGFloat(score) / 100 }
            }
        }
        .onChange(of: score) { _, new in
            withAnimation(ForgeMotion.resolved(ForgeMotion.sweep, reduceMotion: reduceMotion)) {
                progress = CGFloat(new) / 100
            }
        }
    }
}

struct StreakCalendarSection: View {
    @EnvironmentObject var store: AppStore
    /// Drives only the per-cell stagger; the card's own entrance is handled by
    /// `.homeEntrance`, so the two no longer share a flag.
    @State private var cellsAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var weekDays: [(label: String, hasWorkout: Bool, isToday: Bool)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<7).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let f = DateFormatter()
            f.dateFormat = "EEE"
            let label = f.string(from: date)
            let isToday = offset == 0
            let hasWorkout = store.workoutHistory.contains { history in
                if let historyDate = ISO8601DateFormatter().date(from: history.date) {
                    return cal.isDate(historyDate, inSameDayAs: date)
                }
                if let historyDate = DateFormatter.cachedYMD.date(from: history.date) {
                    return cal.isDate(historyDate, inSameDayAs: date)
                }
                return false
            }
            return (label, hasWorkout, isToday)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack {
                HStack(spacing: FDS.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.ember)
                    Text("THIS WEEK")
                        .font(HomeType.micro)
                        .foregroundColor(.ember)
                        .tracking(2)
                }
                Spacer()
                Text("Days you trained. Open days stay open.")
                    .font(HomeType.micro)
                    .foregroundColor(.textTertiary)
            }

            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: FDS.Spacing.sm) {
                        Text(day.label)
                            .font(HomeType.micro)
                            .foregroundColor(day.isToday ? .ember : .textTertiary)
                        ZStack {
                            Circle()
                                .fill(day.hasWorkout ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                                .frame(width: 34, height: 34)
                            if day.hasWorkout {
                                Circle().stroke(Color.ember.opacity(0.4), lineWidth: 1).frame(width: 34, height: 34)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.ember)
                            } else if day.isToday {
                                Circle().stroke(Color.ember.opacity(0.6), lineWidth: 1.5).frame(width: 34, height: 34)
                                Circle().fill(Color.ember).frame(width: 6, height: 6)
                            } else {
                                Circle()
                                    .stroke(ForgeProgressChrome.miss.opacity(0.32), lineWidth: 1)
                                    .frame(width: 34, height: 34)
                                Circle()
                                    .fill(ForgeProgressChrome.miss.opacity(0.22))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .scaleEffect(cellsAppeared || reduceMotion ? 1 : 0.7)
                        .opacity(cellsAppeared || reduceMotion ? 1 : 0)
                        .animation(
                            reduceMotion ? nil : ForgeMotion.gentle.delay(0.08 + Double(i) * 0.05),
                            value: cellsAppeared
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .forgeContentCard()
        // Card fade and per-cell stagger used to run off the same `appeared`
        // flag, so the 0.08–0.38 cell cascade raced the card's own 0.32 fade.
        // The card now enters via the shared modifier and `cellsAppeared` drives
        // only the cells, so the two are independent by construction.
        .onAppear {
            guard !cellsAppeared else { return }
            cellsAppeared = true
        }
        .homeEntrance(delay: 0.32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week. Checkmarks on days you trained. Open days stay open.")
    }
}

// MARK: - Glanceable vitals

/// Sleep / Readiness / Load at a glance. Compact rows so the Today hero does
/// not stack the progress ring with three circular dials.
struct HomeVitalsRow: View {
    let sleep: Int
    let recovery: Int
    let load: Int
    var onSelect: (() -> Void)? = nil

    var body: some View {
        // One control for the three facts — they all open the same strip —
        // so the tap area is the whole vitals block (≥ 44 pt) without
        // stretching each compact row.
        Button {
            ForgeHaptics.play(.selection)
            onSelect?()
        } label: {
            VStack(spacing: 2) {
                HomeContributorRow(title: "Sleep", value: sleep, color: .steel)
                HomeContributorRow(
                    title: "Recovery",
                    value: recovery,
                    color: HomeReadiness.color(recovery)
                )
                HomeContributorRow(title: "Load", value: load, color: .ember)
            }
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep \(sleep), recovery \(recovery), load \(load)")
        .accessibilityHint("Shows how last night, bounce-back, and today's load sit under readiness")
    }
}

struct HomeContributorRow: View {
    let title: String
    let value: Int
    let color: Color

    private var clamped: Int { min(max(value, 0), 100) }

    var body: some View {
        HStack(spacing: FDS.Spacing.sm) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(color)
                .frame(width: 2, height: 16)
            Text(title)
                .font(HomeType.label)
                .foregroundColor(.textSecondary)
            Spacer(minLength: 8)
            Text("\(clamped)")
                .font(HomeType.metric)
                .foregroundColor(.textPrimary)
                .contentTransition(.numericText())
        }
        .padding(.vertical, FDS.Spacing.xs)
        .accessibilityLabel("\(title) \(clamped)")
    }
}
