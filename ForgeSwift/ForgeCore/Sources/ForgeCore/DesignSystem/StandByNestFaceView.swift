import SwiftUI

// MARK: - StandBy nest face (shared)
//
// Rendered from two places: the real WidgetKit StandBy widget
// (`ForgeWidgetExtension/StandByNestWidget.swift`) and the in-app
// customization screen's live preview. Both must show pixel-identical
// output, so the view lives once here rather than being duplicated —
// the same reasoning `HomeWidgetSnapshot` itself is documented with
// ("same struct on both ends of the App Group").
//
// This is ForgeCore's first `View`. Everything else here is deliberately
// UI-framework-light (see the package header comment), but duplicating this
// Canvas-based rendering across the widget extension and app targets would
// be exactly the kind of drift this codebase avoids elsewhere — ForgeCore
// already depends on SwiftUI for `Color(forgeHex:)`, so this does not add a
// new framework dependency, only a new use of one already present.
//
// No WidgetKit import: this view takes `nightMode` as an explicit parameter
// instead of reading `\.widgetRenderingMode` itself, so it has zero
// WidgetKit dependency and works unmodified inside the plain app target.
public struct StandByNestFaceView: View {
    public var snapshot: HomeWidgetSnapshot
    public var date: Date
    public var metrics: [StandByMetricKind]
    public var nightMode: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        snapshot: HomeWidgetSnapshot,
        date: Date,
        metrics: [StandByMetricKind],
        nightMode: Bool = false
    ) {
        self.snapshot = snapshot
        self.date = date
        self.metrics = metrics
        self.nightMode = nightMode
    }

    private var band: ReadinessBand { ReadinessBand(score: snapshot.readiness) }

    private var frozen: Bool {
        !AriaNestGeometry.StandBy.shouldAnimate(reduceMotion: reduceMotion, nightMode: nightMode)
    }

    private var clockColor: Color {
        Color(forgeHex: AriaNestGeometry.StandBy.clockHex)
    }

    private var hydrationPercent: Int {
        Int((snapshot.hydrationFraction * 100).rounded())
    }

    private var sleepText: String {
        let hours = String(format: "%.1fh", snapshot.sleepHours)
        guard let score = snapshot.sleepScore else { return hours }
        return "\(hours) · \(score)"
    }

    private func text(for metric: StandByMetricKind) -> String {
        switch metric {
        case .sleep:     return sleepText
        case .hydration: return "\(hydrationPercent)% of goal"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(snapshot.readiness)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(clockColor)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text(snapshot.readinessLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.4)
                        .foregroundStyle(nightMode ? clockColor.opacity(0.85) : band.color)
                }
                Spacer(minLength: 4)
                AriaNestMarkStandBy(size: 22, frozen: frozen, nightMode: nightMode)
            }

            ForEach(metrics) { metric in
                statRow(icon: metric.systemImage, text: text(for: metric))
            }

            Spacer(minLength: 0)

            Text(date, format: Self.timeFormat)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(clockColor.opacity(nightMode ? 0.85 : 0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Forge StandBy.", "Readiness \(snapshot.readiness), \(snapshot.readinessLabel)."]
        for metric in metrics {
            parts.append("\(metric.title) \(text(for: metric)).")
        }
        parts.append(date.formatted(Self.timeFormat) + ".")
        return parts.joined(separator: " ")
    }

    private func statRow(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(clockColor.opacity(nightMode ? 0.9 : 0.78))
    }

    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)
}

/// Idle nest only. Same geometry as Watch `AriaNestMarkWatch`. Still-pose when
/// Reduce Motion or vibrant (low-light) StandBy. Tick ≤ 12 Hz otherwise.
struct AriaNestMarkStandBy: View {
    var size: CGFloat
    var frozen: Bool
    var nightMode: Bool

    var body: some View {
        let interval = AriaNestGeometry.StandBy.tickInterval(
            reduceMotion: frozen,
            nightMode: nightMode
        )
        TimelineView(.animation(minimumInterval: interval, paused: frozen)) { timeline in
            let time = frozen
                ? AriaNestGeometry.stillPose
                : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                paint(context: &context, canvasSize: canvasSize, time: time)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func paint(context: inout GraphicsContext, canvasSize: CGSize, time: Double) {
        let s = min(canvasSize.width, canvasSize.height)
        guard s >= 2 else { return }
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let orange = Color(forgeHex: AriaNestGeometry.forgeOrangeHex)
        let pearl = Color(forgeHex: AriaNestGeometry.pearlHex)
        let pearlHot = Color(forgeHex: AriaNestGeometry.pearlHotHex)
        let metalCool = Color(forgeHex: AriaNestGeometry.metalCoolHex)

        if !nightMode {
            let washR = s * 0.42
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - washR,
                    y: center.y - washR,
                    width: washR * 2,
                    height: washR * 2
                )),
                with: .radialGradient(
                    Gradient(colors: [
                        pearlHot.opacity(0.14),
                        orange.opacity(0.04),
                        .clear
                    ]),
                    center: center,
                    startRadius: 1,
                    endRadius: washR
                )
            )
        }

        for index in AriaNestGeometry.visibleRingIndices(size: Double(s)).reversed() {
            let pose = AriaNestGeometry.livingHex(
                index: index,
                time: time,
                presence: .idle,
                amplitude: AriaNestGeometry.StandBy.idleAmplitude,
                reduceMotion: frozen
            )
            let stroke = Color(forgeHex: AriaNestGeometry.ringHex(at: index))
            let path = nestPath(
                center: center,
                width: s * pose.rx,
                height: s * pose.ry,
                rotation: pose.rotation,
                wavePhase: pose.wavePhase,
                waveAmp: pose.waveAmp
            )
            let opacity = nightMode ? min(1, pose.opacity + 0.12) : pose.opacity
            context.stroke(
                path,
                with: .color(stroke.opacity(min(1, opacity))),
                lineWidth: CGFloat(AriaNestGeometry.strokeWidth(size: Double(s), index: index))
            )
        }

        let core = AriaNestGeometry.orbCore(
            time: time,
            presence: .idle,
            amplitude: AriaNestGeometry.StandBy.idleAmplitude,
            reduceMotion: frozen
        )
        let diameter = s * core.diameter
        let body = CGRect(
            x: center.x - diameter * core.sx / 2,
            y: center.y - diameter * core.sy / 2,
            width: diameter * core.sx,
            height: diameter * core.sy
        )
        context.fill(
            Path(ellipseIn: body),
            with: .radialGradient(
                Gradient(colors: [
                    pearlHot.opacity(0.96),
                    metalCool.opacity(0.88),
                    pearl.opacity(0.7)
                ]),
                center: CGPoint(x: center.x - diameter * 0.12, y: center.y - diameter * 0.14),
                startRadius: 0,
                endRadius: diameter * 0.55
            )
        )
    }

    private func nestPath(
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        rotation: Double,
        wavePhase: Double,
        waveAmp: Double
    ) -> Path {
        let points = AriaNestGeometry.nestRingPoints(
            roundness: AriaNestGeometry.cornerRoundness,
            wavePhase: wavePhase,
            waveAmp: waveAmp
        )
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        var path = Path()
        for (i, point) in points.enumerated() {
            let x = CGFloat(point.x) * width * 0.5
            let y = CGFloat(point.y) * height * 0.5
            let mapped = CGPoint(
                x: center.x + x * cosR - y * sinR,
                y: center.y + x * sinR + y * cosR
            )
            if i == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        path.closeSubpath()
        return path
    }
}
