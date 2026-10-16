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

// MARK: - Home readiness ring-field (data language, not the Nest mark)

/// Home-owned ring-field clock. Pose math stays `AriaRingFieldGeometry`
/// (the Home readiness data language). Do not borrow `AriaNestGeometry`
/// ticks or poses — Nest is the brand mark.
enum HomeRingField {
    /// Idle paint while Home is visible and the scene is active.
    /// Ceiling stays `AriaRingFieldGeometry` / nest 12 Hz — this field just
    /// does not spend that budget when the user is not looking.
    static let tickHz: Double = 5
    static let tickInterval: Double = 1.0 / 5.0
}

/// Kinetic 5-ellipse ring-field from `AriaRingFieldGeometry`.
/// Brand mark stays `AriaNest*` / `ARIAIdentityMark`. Today's hero is the
/// HUD progress ring (`HudProgressRing`) — this field is no longer mounted
/// on Home, so the 12 Hz TimelineView is idle unless a caller paints it.
struct HomeReadinessFieldView: View {
    let score: Int
    var size: CGFloat? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var scaledHeroField: CGFloat = HomeMetrics.heroFieldSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnscreen = true

    static func isFrozen(reduceMotion: Bool, minimal: Bool) -> Bool {
        HomeTrendMath.isFrozen(reduceMotion: reduceMotion, minimal: minimal)
    }

    private var frozen: Bool { Self.isFrozen(reduceMotion: reduceMotion, minimal: minimalAnimation) }
    private var paused: Bool { frozen || scenePhase != .active || !isOnscreen }
    private var clamped: Int { min(max(score, 0), 100) }
    private var resolvedSize: CGFloat {
        max(AriaRingFieldGeometry.heroMinimumSize, size ?? scaledHeroField)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: HomeRingField.tickInterval, paused: paused)) { timeline in
            let time = paused
                ? AriaRingFieldGeometry.stillPose
                : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Canvas { context, canvasSize in
                    HomeRingFieldCanvas.paint(
                        context: &context,
                        canvasSize: canvasSize,
                        time: time,
                        score: clamped,
                        reduceMotion: paused
                    )
                }
                VStack(spacing: 2) {
                    Text("\(clamped)")
                        .font(HomeType.heroScore)
                        .foregroundStyle(Color.textPrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(HomeReadiness.label(clamped).uppercased())
                        .font(HomeType.micro)
                        .foregroundColor(HomeReadiness.color(clamped))
                        .tracking(1.6)
                    Text("Readiness")
                        .font(HomeType.micro)
                        .foregroundColor(.textTertiary)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(width: resolvedSize, height: resolvedSize)
        .onAppear { isOnscreen = true }
        .onDisappear { isOnscreen = false }
        .onScrollVisibilityChange { isOnscreen = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeReadiness.voiceOverLabel(clamped))
    }
}

enum HomeRingFieldCanvas {
    static func paint(
        context: inout GraphicsContext,
        canvasSize: CGSize,
        time: Double,
        score: Int,
        reduceMotion: Bool
    ) {
        let s = min(canvasSize.width, canvasSize.height)
        guard s >= 2 else { return }
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let tint = HomeReadiness.color(score)
        let fill = Double(min(max(score, 0), 100)) / 100.0

        for index in AriaRingFieldGeometry.visibleRingIndices(size: s).reversed() {
            let pose = AriaRingFieldGeometry.ellipse(
                index: index,
                time: time,
                speaking: false,
                reduceMotion: reduceMotion
            )
            let line = AriaRingFieldGeometry.strokeWidth(size: s, index: index)
            let width = s * CGFloat(pose.rx)
            let height = s * CGFloat(pose.ry)
            var path = Path(ellipseIn: CGRect(
                x: -width / 2,
                y: -height / 2,
                width: width,
                height: height
            ))
            let transform = CGAffineTransform.identity
                .translatedBy(x: center.x, y: center.y)
                .rotated(by: CGFloat(pose.rotation))
            path = path.applying(transform)

            context.stroke(
                path,
                with: .color(tint.opacity(min(1, pose.opacity + 0.06))),
                lineWidth: line
            )
        }

        // Score lives in the geometry: outer arc sweep is score / 100.
        // Band cuts / hex live in `shared/readiness.json` via `HomeReadiness`.
        // This kinetic field is not mounted on Today — HUD chrome is.
        let outer = AriaRingFieldGeometry.ellipseCount - 1
        let sweepRadius = s * CGFloat(
            AriaRingFieldGeometry.radii[outer] * (1 + AriaRingFieldGeometry.eccentricity[outer])
        ) / 2
        let sweepWidth = max(2.4, AriaRingFieldGeometry.strokeWidth(size: s, index: outer) * 2.2)
        var track = Path()
        track.addArc(
            center: center,
            radius: sweepRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(270),
            clockwise: false
        )
        context.stroke(track, with: .color(tint.opacity(0.16)), lineWidth: sweepWidth)
        if fill > 0 {
            var arc = Path()
            arc.addArc(
                center: center,
                radius: sweepRadius,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 360 * fill),
                clockwise: false
            )
            context.stroke(arc, with: .color(tint.opacity(0.95)), lineWidth: sweepWidth)
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
                    .foregroundColor(.textMuted)
            }

            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: 8) {
                        Text(day.label)
                            .font(HomeType.micro)
                            .foregroundColor(day.isToday ? .ember : .textMuted)
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
                                    .stroke(HudChrome.miss.opacity(0.32), lineWidth: 1)
                                    .frame(width: 34, height: 34)
                                Circle()
                                    .fill(HudChrome.miss.opacity(0.22))
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
        .accessibilityLabel("This week. Checkmarks on days you trained. Open days stay open.")
    }
}

// MARK: - Glanceable vitals (compact rows — the ring-field is the only circle)

/// Sleep / Recovery / Load at a glance. Compact rows so the Today hero does
/// not stack the ring-field with three circular dials.
struct HomeVitalsRow: View {
    let sleep: Int
    let recovery: Int
    let load: Int
    var onSelect: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 2) {
            HomeContributorRow(title: "Sleep", value: sleep, color: .steel, onTap: onSelect)
            HomeContributorRow(
                title: "Recovery",
                value: recovery,
                color: HomeReadiness.color(recovery),
                onTap: onSelect
            )
            HomeContributorRow(title: "Load", value: load, color: .ember, onTap: onSelect)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep \(sleep), recovery \(recovery), load \(load)")
        .accessibilityHint("Shows how last night, bounce-back, and today's load sit under readiness")
    }
}

struct HomeContributorRow: View {
    let title: String
    let value: Int
    let color: Color
    var onTap: (() -> Void)? = nil

    private var clamped: Int { min(max(value, 0), 100) }

    var body: some View {
        Button {
            ForgeHaptics.play(.selection)
            onTap?()
        } label: {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(clamped)")
    }
}
