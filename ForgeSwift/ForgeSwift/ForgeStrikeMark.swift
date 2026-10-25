import SwiftUI
import ForgeCore

/// Procedural hammer-and-flame mark. Canvas + Shapes only — no PNG.
/// One-shot strike, then a still idle. Reduce Motion is the idle pose.
struct ForgeStrikeMark: View {
    var size: CGFloat = 160
    var labeled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: tick, paused: clockPaused)) { context in
            let elapsed = resolvedElapsed(at: context.date)
            Canvas { ctx, canvasSize in
                ForgeStrikeCanvas.paint(
                    context: &ctx,
                    canvasSize: canvasSize,
                    progress: ForgeStrikeMarkGeometry.normalizedProgress(elapsed: elapsed),
                    reduceMotion: reduceMotion || compact
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(labeled ? ForgeWelcomeCopy.markLabel : "")
        .accessibilityHidden(!labeled)
        .onAppear {
            startedAt = Date()
        }
    }

    private var compact: Bool {
        ForgeStrikeMarkGeometry.isCompact(size: Double(size))
    }

    private var clockPaused: Bool {
        reduceMotion || compact || resolvedElapsed(at: Date()) >= ForgeStrikeMarkGeometry.strikeDuration
    }

    private var tick: TimeInterval {
        ForgeStrikeMarkGeometry.tickInterval
    }

    private func resolvedElapsed(at date: Date) -> Double {
        if reduceMotion { return ForgeStrikeMarkGeometry.strikeDuration }
        guard let startedAt else { return 0 }
        return date.timeIntervalSince(startedAt)
    }
}

enum ForgeStrikeCanvas {
    static func paint(
        context: inout GraphicsContext,
        canvasSize: CGSize,
        progress: Double,
        reduceMotion: Bool
    ) {
        let side = min(canvasSize.width, canvasSize.height)
        guard side >= 2 else { return }
        let origin = CGPoint(
            x: (canvasSize.width - side) / 2,
            y: (canvasSize.height - side) / 2
        )
        context.translateBy(x: origin.x, y: origin.y)

        let pose = ForgeStrikeMarkGeometry.pose(progress: progress, reduceMotion: reduceMotion)
        let compact = ForgeStrikeMarkGeometry.isCompact(size: Double(side))
        let paper = Color(hex: ForgeStrikeMarkGeometry.paperHex)
        let paperShade = Color(hex: ForgeStrikeMarkGeometry.paperShadeHex)
        let ember = Color(hex: ForgeStrikeMarkGeometry.emberHex)
        let emberLight = Color(hex: ForgeStrikeMarkGeometry.emberLightHex)
        let emberDark = Color(hex: ForgeStrikeMarkGeometry.emberDarkHex)
        let amber = Color(hex: ForgeStrikeMarkGeometry.amberHex)
        let kernel = Color(hex: ForgeStrikeMarkGeometry.kernelHex)

        if compact {
            let tile = Path(
                roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                cornerRadius: side * 0.28,
                style: .continuous
            )
            context.fill(tile, with: .color(ember))
            context.stroke(tile, with: .color(Color.white.opacity(0.16)), lineWidth: 0.5)
        }

        let glyphSide = compact ? side * 0.80 : side
        if compact {
            context.translateBy(x: (side - glyphSide) / 2, y: (side - glyphSide) / 2)
        }

        if !compact {
            paintUnderglow(context: &context, side: glyphSide, ember: ember, flare: pose.flare)
        }

        paintFlame(
            context: &context,
            side: glyphSide,
            flare: pose.flare,
            compact: compact,
            paper: paper,
            ember: ember,
            emberLight: emberLight,
            emberDark: emberDark,
            amber: amber,
            kernel: kernel
        )

        if !compact {
            let glow = ForgeStrikeMarkGeometry.impactGlowOpacity(flare: pose.flare)
            if glow > 0.01 {
                let radius = glyphSide * CGFloat(ForgeStrikeMarkGeometry.impactGlowRadius(flare: pose.flare))
                let center = CGPoint(
                    x: glyphSide * CGFloat(ForgeStrikeMarkGeometry.strikeX),
                    y: glyphSide * CGFloat(ForgeStrikeMarkGeometry.strikeY)
                )
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [ember.opacity(glow), ember.opacity(0)]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }

        paintHammer(
            context: &context,
            side: glyphSide,
            angleDeg: pose.hammerAngleDeg,
            compact: compact,
            paper: paper,
            paperShade: paperShade
        )

        if !compact, !reduceMotion {
            for index in 0..<ForgeStrikeMarkGeometry.sparkCount {
                let spark = ForgeStrikeMarkGeometry.spark(
                    index: index,
                    progress: progress,
                    reduceMotion: false
                )
                guard spark.opacity > 0.01 else { continue }
                let radius = max(0.55, glyphSide * CGFloat(spark.radius))
                let rect = CGRect(
                    x: glyphSide * CGFloat(spark.x) - radius,
                    y: glyphSide * CGFloat(spark.y) - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(amber.opacity(spark.opacity)))
            }
        }
    }

    private static func paintUnderglow(
        context: inout GraphicsContext,
        side: CGFloat,
        ember: Color,
        flare: Double
    ) {
        let glow = 0.16 + 0.14 * flare
        let rx = side * 0.18
        let ry = side * 0.12
        let center = CGPoint(x: side * 0.40, y: side * 0.78)
        let rect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [ember.opacity(glow), ember.opacity(0)]),
                center: center,
                startRadius: 0,
                endRadius: rx
            )
        )
    }

    private static func paintFlame(
        context: inout GraphicsContext,
        side: CGFloat,
        flare: Double,
        compact: Bool,
        paper: Color,
        ember: Color,
        emberLight: Color,
        emberDark: Color,
        amber: Color,
        kernel: Color
    ) {
        let scale = ForgeStrikeMarkGeometry.flareScale(flare: flare)
        let origin = CGPoint(
            x: side * CGFloat(scale.originX),
            y: side * CGFloat(scale.originY)
        )
        context.drawLayer { ctx in
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.scaleBy(x: scale.x, y: scale.y)
            ctx.translateBy(x: -origin.x, y: -origin.y)

            for index in 0..<min(3, ForgeStrikeMarkGeometry.flameLayerCount) {
                let path = path(
                    ForgeStrikeMarkGeometry.flameCommands(index: index),
                    side: side
                )
                if compact {
                    ctx.fill(path, with: .color(paper))
                    continue
                }
                switch index {
                case 0:
                    ctx.fill(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [ember, emberDark]),
                            startPoint: CGPoint(x: side * 0.30, y: side * 0.14),
                            endPoint: CGPoint(x: side * 0.40, y: side * 0.86)
                        )
                    )
                case 1:
                    ctx.fill(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [emberLight, ember]),
                            startPoint: CGPoint(x: side * 0.34, y: side * 0.20),
                            endPoint: CGPoint(x: side * 0.42, y: side * 0.82)
                        )
                    )
                case 2:
                    ctx.fill(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [kernel, amber]),
                            startPoint: CGPoint(x: side * 0.38, y: side * 0.36),
                            endPoint: CGPoint(x: side * 0.42, y: side * 0.76)
                        )
                    )
                default:
                    ctx.fill(path, with: .color(kernel.opacity(0.7)))
                }
            }
        }
    }

    private static func paintHammer(
        context: inout GraphicsContext,
        side: CGFloat,
        angleDeg: Double,
        compact: Bool,
        paper: Color,
        paperShade: Color
    ) {
        let pivot = CGPoint(
            x: side * CGFloat(ForgeStrikeMarkGeometry.pivotX),
            y: side * CGFloat(ForgeStrikeMarkGeometry.pivotY)
        )
        let local = path(ForgeStrikeMarkGeometry.hammerCommands(), side: side)
        let highlight = path(ForgeStrikeMarkGeometry.hammerHighlightCommands(), side: side)
        context.drawLayer { ctx in
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: .degrees(angleDeg))
            if compact {
                ctx.fill(local, with: .color(paper))
            } else {
                ctx.fill(
                    local,
                    with: .linearGradient(
                        Gradient(colors: [paper, paperShade]),
                        startPoint: CGPoint(x: side * -0.24, y: side * -0.08),
                        endPoint: CGPoint(x: side * 0.36, y: side * 0.04)
                    )
                )
                ctx.fill(highlight, with: .color(Color.white.opacity(0.22)))
            }
        }
    }

    private static func path(_ commands: [ForgeStrikeMarkGeometry.Command], side: CGFloat) -> Path {
        var path = Path()
        path.fillRule = .evenOdd
        for command in commands {
            switch command {
            case .move(let x, let y):
                path.move(to: CGPoint(x: side * CGFloat(x), y: side * CGFloat(y)))
            case .line(let x, let y):
                path.addLine(to: CGPoint(x: side * CGFloat(x), y: side * CGFloat(y)))
            case .cubic(let cx1, let cy1, let cx2, let cy2, let x, let y):
                path.addCurve(
                    to: CGPoint(x: side * CGFloat(x), y: side * CGFloat(y)),
                    control1: CGPoint(x: side * CGFloat(cx1), y: side * CGFloat(cy1)),
                    control2: CGPoint(x: side * CGFloat(cx2), y: side * CGFloat(cy2))
                )
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

#Preview("Strike mark hero") {
    ZStack {
        Color.background.ignoresSafeArea()
        ForgeStrikeMark(size: 180)
    }
    .preferredColorScheme(.dark)
}

#Preview("Strike mark compact") {
    ZStack {
        Color.background.ignoresSafeArea()
        ForgeStrikeMark(size: 22, labeled: false)
    }
    .preferredColorScheme(.dark)
}
