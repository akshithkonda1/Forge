import SwiftUI
import ForgeCore

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
                    .font(HomeType.micro)
                    .foregroundColor(.textTertiary)
                Text("\(display)")
                    .font(HomeType.metric)
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
                .font(HomeType.status)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(HomeType.label)
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
                ? Animation.easeOut(duration: 0.15)
                : FDS.Spring.sweep.delay(0.2)
            withAnimation(anim) { progress = CGFloat(score) / 100 }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) { glowPulse = true }
                withAnimation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true)) { outerPulse = true }
            }
        }
        .onChange(of: score) { _, new in
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : FDS.Spring.sweep) {
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
    static let tickHz: Double = 12
    static let tickInterval: Double = 1.0 / 12.0
}

/// Kinetic 5-ellipse ring-field from `AriaRingFieldGeometry`.
/// Brand mark stays `AriaNest*` / `ARIAIdentityMark`. This field is Home
/// readiness chrome only. Hero size (≥90) paints all five ellipses.
struct HomeReadinessFieldView: View {
    let score: Int
    var size: CGFloat? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var scaledHeroField: CGFloat = HomeMetrics.heroFieldSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation

    static func isFrozen(reduceMotion: Bool, minimal: Bool) -> Bool {
        reduceMotion || minimal
    }

    private var frozen: Bool { Self.isFrozen(reduceMotion: reduceMotion, minimal: minimalAnimation) }
    private var clamped: Int { min(max(score, 0), 100) }
    private var resolvedSize: CGFloat {
        max(AriaRingFieldGeometry.heroMinimumSize, size ?? scaledHeroField)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: HomeRingField.tickInterval, paused: frozen)) { timeline in
            let time = frozen
                ? AriaRingFieldGeometry.stillPose
                : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Canvas { context, canvasSize in
                    HomeRingFieldCanvas.paint(
                        context: &context,
                        canvasSize: canvasSize,
                        time: time,
                        score: clamped,
                        reduceMotion: frozen
                    )
                }
                VStack(spacing: 2) {
                    Text("\(clamped)")
                        .font(HomeType.heroScore)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.textPrimary, HomeReadiness.color(clamped)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
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

        let haloR = s * 0.24
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - haloR, y: center.y - haloR,
                width: haloR * 2, height: haloR * 2
            )),
            with: .radialGradient(
                Gradient(colors: [
                    tint.opacity(0.10 + 0.10 * fill),
                    .clear
                ]),
                center: center,
                startRadius: s * 0.02,
                endRadius: haloR
            )
        )

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
                with: .color(tint.opacity(pose.opacity * 0.32)),
                lineWidth: max(2.2, line * 2.0)
            )
            context.stroke(
                path,
                with: .color(tint.opacity(min(1, pose.opacity + 0.06))),
                lineWidth: line
            )
        }

        // Score lives in the geometry: outer arc sweep is score / 100.
        // TODO: Lex `shared/readiness.json` will own band thresholds, colors,
        // and this sweep. Until then reuse `HomeReadiness` cuts (85 / 70 / 50)
        // via `HomeReadiness.color` — do not invent a third palette.
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.ember)
                    Text("THIS WEEK")
                        .font(HomeType.micro)
                        .foregroundColor(.ember)
                        .tracking(2)
                }
                Spacer()
                Text("Days you trained")
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
                                Circle().fill(Color.white.opacity(0.08)).frame(width: 8, height: 8)
                            }
                        }
                        .scaleEffect(cellsAppeared || reduceMotion ? 1 : 0.7)
                        .opacity(cellsAppeared || reduceMotion ? 1 : 0)
                        .animation(
                            reduceMotion ? nil : FDS.Spring.hero.delay(0.08 + Double(i) * 0.05),
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
        .accessibilityLabel("This week. Checkmarks on days you trained.")
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
            FDS.selectionHaptic()
            onTap?()
        } label: {
            HStack(spacing: 10) {
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
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(clamped)")
    }
}
