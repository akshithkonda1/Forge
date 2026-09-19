import SwiftUI
import WidgetKit
import ForgeCore

// MARK: - StandBy nest face
//
// Public Apple surface: WidgetKit `WidgetFamily.systemSmall`.
// iPhone StandBy (MagSafe / landscape nightstand) and CarPlay both take the
// small system family and scale it. There is no dedicated StandBy family and
// no MagSafe private API. Low light uses `WidgetRenderingMode.vibrant`.
//
// Face is `AriaNestGeometry` (B+E nest) + clock / wordmark. Not fire splash,
// not Home `AriaRingFieldGeometry` data chrome.

struct StandByNestEntry: TimelineEntry {
    let date: Date
}

struct StandByNestProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandByNestEntry {
        StandByNestEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (StandByNestEntry) -> Void) {
        completion(StandByNestEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StandByNestEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let entries = (0..<20).compactMap { offset -> StandByNestEntry? in
            calendar.date(byAdding: .minute, value: offset, to: now)
                .map(StandByNestEntry.init(date:))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct StandByNestWidgetView: View {
    var entry: StandByNestEntry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var nightMode: Bool { renderingMode == .vibrant }

    private var frozen: Bool {
        !AriaNestGeometry.StandBy.shouldAnimate(
            reduceMotion: reduceMotion,
            nightMode: nightMode
        )
    }

    private var nestSize: CGFloat {
        showsBackground ? 64 : 78
    }

    private var clockColor: Color {
        Color(forgeHex: AriaNestGeometry.StandBy.clockHex)
    }

    var body: some View {
        VStack(spacing: 6) {
            AriaNestMarkStandBy(
                size: nestSize,
                frozen: frozen,
                nightMode: nightMode
            )
            Text(entry.date, format: Self.timeFormat)
                .font(.system(size: 34, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(clockColor)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(entry.date, format: Self.dateFormat)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(clockColor.opacity(nightMode ? 0.92 : 0.70))
            Text("FORGE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(2.6)
                .foregroundStyle(clockColor.opacity(nightMode ? 0.78 : 0.52))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forge StandBy, \(entry.date.formatted(Self.timeFormat))")
    }

    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)
    private static let dateFormat = Date.FormatStyle()
        .weekday(.abbreviated)
        .month(.abbreviated)
        .day()
}

/// Idle nest only. Same geometry as Watch `AriaNestMarkWatch`. Still-pose when
/// Reduce Motion or vibrant (low-light) StandBy. Tick ≤ 12 Hz otherwise.
private struct AriaNestMarkStandBy: View {
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

struct StandByNestWidget: Widget {
    let kind = AriaNestGeometry.StandBy.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StandByNestProvider()) { entry in
            StandByNestWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(forgeHex: AriaNestGeometry.StandBy.nightstandBackgroundHex)
                }
                .widgetURL(ForgeWidgetLink.standBy)
        }
        .configurationDisplayName("StandBy")
        .description("Nest face for MagSafe landscape StandBy. Clock, quiet nightstand, Reduce Motion aware.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

#Preview("StandBy nest", as: .systemSmall) {
    StandByNestWidget()
} timeline: {
    StandByNestEntry(date: .now)
}
