import SwiftUI
import ForgeCore

// MARK: - ReadinessRing
//
// Glanceable readiness score ring. Mirrors the iOS readiness ring bands
// (Theme+Readiness.swift) via ForgeCore's ReadinessBand. Designed to stay
// legible in the always-on dimmed state: the ring survives, decoration
// fades.

struct ReadinessRing<Center: View>: View {
    let score: Int?
    /// Below ~0.4 the score renders as an estimate (hollow ring cap + "~").
    var confidence: Double = 1.0
    var lineWidth: CGFloat = 9
    @ViewBuilder var center: () -> Center

    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var band: ReadinessBand? { score.map(ReadinessBand.init(score:)) }
    private var isEstimate: Bool { confidence < 0.4 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ForgePalette.surfaceElevated, lineWidth: lineWidth)

            if let score, let band {
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [band.color.opacity(0.55), band.color],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            dash: isEstimate ? [lineWidth * 1.3, lineWidth * 0.9] : []
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .opacity(luminanceReduced ? 0.55 : 1)
                    .animation(reduceMotion ? nil : ForgeDS.Spring.hero, value: score)
            }

            center()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Opens today's recommended reset.")
    }

    private var accessibilityValueText: String {
        guard let score, let band else {
            return "Not enough data yet. Wear your watch a little longer and Forge will catch up."
        }
        let prefix = isEstimate ? "Roughly " : ""
        return "\(prefix)\(score) out of 100. \(band.label)."
    }
}
