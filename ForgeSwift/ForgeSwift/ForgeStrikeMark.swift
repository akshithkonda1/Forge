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
        let ember = Color(hex: ForgeStrikeMarkGeometry.emberHex)
        let emberDark = Color(hex: ForgeStrikeMarkGeometry.emberDarkHex)
        let amber = Color(hex: ForgeStrikeMarkGeometry.amberHex)

        if compact {
            let tile = Path(
                roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                cornerRadius: side * 0.28,
                style: .continuous
            )
            context.fill(tile, with: .color(ember))
            context.stroke(tile, with: .color(Color.white.opacity(0.16)), lineWidth: 0.5)
        }

        let glyphSide = compact ? side * 0.78 : side
        if compact {
            context.translateBy(x: (side - glyphSide) / 2, y: (side - glyphSide) / 2)
        }

        paintFlame(
            context: &context,
            side: glyphSide,
            flare: pose.flare,
            compact: compact,
            paper: paper,
            ember: ember,
            emberDark: emberDark,
            amber: amber
        )

        if !compact {
            let glow = ForgeStrikeMarkGeometry.impactGlowOpacity(flare: pose.flare)
            if glow > 0.01 {
                let radius = glyphSide * CGFloat(ForgeStrikeMarkGeometry.impactGlowRadius(flare: pose.flare))
                let rect = CGRect(
                    x: glyphSide * 0.41 - radius,
                    y: glyphSide * 0.64 - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(ember.opacity(glow)))
            }
        }

        paintHammer(
            context: &context,
            side: glyphSide,
            angleDeg: pose.hammerAngleDeg,
            compact: compact,
            paper: paper,
            ember: ember
        )

        if !compact, !reduceMotion {
            for index in 0..<ForgeStrikeMarkGeometry.sparkCount {
                let spark = ForgeStrikeMarkGeometry.spark(
                    index: index,
                    progress: progress,
                    reduceMotion: false
                )
                guard spark.opacity > 0.01 else { continue }
                let radius = max(0.6, glyphSide * CGFloat(spark.radius))
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

    private static func paintFlame(
        context: inout GraphicsContext,
        side: CGFloat,
        flare: Double,
        compact: Bool,
        paper: Color,
        ember: Color,
        emberDark: Color,
        amber: Color
    ) {
        let fills: [Color] = compact
            ? [paper, paper, paper]
            : [emberDark, ember, amber]
        for index in 0..<3 {
            let path = path(
                ForgeStrikeMarkGeometry.flameCommands(index: index, flare: flare),
                side: side
            )
            context.fill(path, with: .color(fills[index]))
        }
    }

    private static func paintHammer(
        context: inout GraphicsContext,
        side: CGFloat,
        angleDeg: Double,
        compact: Bool,
        paper: Color,
        ember: Color
    ) {
        let pivot = CGPoint(
            x: side * CGFloat(ForgeStrikeMarkGeometry.pivotX),
            y: side * CGFloat(ForgeStrikeMarkGeometry.pivotY)
        )
        let local = path(ForgeStrikeMarkGeometry.hammerCommands(), side: side)
        context.drawLayer { ctx in
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: .degrees(angleDeg))
            ctx.fill(local, with: .color(paper))
            if !compact {
                ctx.stroke(
                    local,
                    with: .color(Color.white.opacity(0.16)),
                    lineWidth: max(0.6, side * 0.006)
                )
            }
        }
    }

    private static func path(_ commands: [ForgeStrikeMarkGeometry.Command], side: CGFloat) -> Path {
        var path = Path()
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
