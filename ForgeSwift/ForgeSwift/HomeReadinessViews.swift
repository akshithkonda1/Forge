import SwiftUI

struct BreakdownCardView: View {
    let label: String
    let value: Int
    let inverted: Bool
    let index: Int
    @State private var appeared = false

    private var display: Int { inverted ? 100 - value : value }
    private var dot: Color { HomeReadiness.color(display) }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Text("\(display)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            Spacer()
        }
        .padding(12)
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
            withAnimation(FDS.Spring.hero.delay(0.05 * Double(index))) { appeared = true }
        }
    }
}

struct ReadinessInsightRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 15)).foregroundColor(color)
            }
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, 4)
    }
}

struct ReadinessRingView: View {
    let score: Int
    let size: CGFloat
    let strokeWidth: CGFloat
    var showLabel: Bool = true

    @State private var progress: CGFloat = 0
    @State private var glowPulse = false
    @State private var outerPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { HomeReadiness.color(score) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)

            if !reduceMotion {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: strokeWidth + 14, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 18)
                    .scaleEffect(outerPulse ? 1.02 : 0.99)
            }

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: strokeWidth + 6, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .blur(radius: 8)
                .opacity(glowPulse ? 0.55 : 0.85)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.6), color, color.opacity(0.85)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 14)

            if progress > 0.02 {
                Circle()
                    .fill(color)
                    .frame(width: strokeWidth * 0.85, height: strokeWidth * 0.85)
                    .shadow(color: color, radius: 6)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(-90 + Double(progress) * 360))
            }

            if showLabel {
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: size * 0.24, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.textPrimary, color], startPoint: .top, endPoint: .bottom)
                        )
                        .contentTransition(.numericText())
                    Text(HomeReadiness.label(score).uppercased())
                        .font(.system(size: size * 0.07, weight: .black))
                        .foregroundColor(color)
                        .tracking(1.6)
                    Text("Readiness")
                        .font(.system(size: size * 0.055, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            let anim = reduceMotion
                ? Animation.easeOut(duration: 0.2)
                : Animation.spring(response: 1.5, dampingFraction: 0.7).delay(0.35)
            withAnimation(anim) { progress = CGFloat(score) / 100 }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) { glowPulse = true }
                withAnimation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true)) { outerPulse = true }
            }
        }
        .onChange(of: score) { _, new in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) {
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.ember)
                    Text("\(store.currentStreak)-DAY STREAK")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.ember)
                        .tracking(2)
                }
                Spacer()
                Text("This week")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
            }

            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: 8) {
                        Text(day.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(day.isToday ? .ember : .textMuted)
                        ZStack {
                            Circle()
                                .fill(day.hasWorkout ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                                .frame(width: 34, height: 34)
                            if day.hasWorkout {
                                Circle().stroke(Color.ember.opacity(0.4), lineWidth: 1).frame(width: 34, height: 34)
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.ember)
                            } else if day.isToday {
                                Circle().stroke(Color.ember.opacity(0.6), lineWidth: 1.5).frame(width: 34, height: 34)
                                Circle().fill(Color.ember).frame(width: 6, height: 6)
                            } else {
                                Circle().fill(Color.white.opacity(0.08)).frame(width: 8, height: 8)
                            }
                        }
                        .scaleEffect(cellsAppeared ? 1 : 0.7)
                        .opacity(cellsAppeared ? 1 : 0)
                        .animation(FDS.Spring.hero.delay(0.08 + Double(i) * 0.05), value: cellsAppeared)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember)
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
        .accessibilityLabel("\(store.currentStreak) day streak this week")
    }
}
