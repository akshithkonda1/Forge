import SwiftUI

// MARK: - Readiness Ring

struct ReadinessRing: View {
    let score: Int
    var size: CGFloat = 180
    var strokeWidth: CGFloat = 14
    var showLabel = true

    var body: some View {
        ReadinessRingView(score: score, size: size, strokeWidth: strokeWidth, showLabel: showLabel)
    }
}

struct ReadinessRingView: View {
    let score: Int
    var size: CGFloat = 180
    var strokeWidth: CGFloat = 14
    var showLabel = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double { Double(min(max(score, 0), 100)) / 100.0 }
    private var color: Color { readinessColor(for: score) }

    var body: some View {
        ZStack {
            if score >= 70 && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let bloom = score / 8 + (score / 5 - score / 8) * (0.5 + 0.5 * sin(t * 2 * .pi / 3))
                    Circle()
                        .stroke(color.opacity(0.25), lineWidth: strokeWidth + 4)
                        .blur(radius: CGFloat(bloom))
                        .frame(width: size, height: size)
                }
            }

            Circle()
                .stroke(Color.forgeBorder, lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.4), radius: 8)
                .animation(FDS.Spring.hero, value: progress)

            if showLabel {
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(readinessLabel(for: score))
                        .font(.system(size: size * 0.08, weight: .semibold))
                        .foregroundColor(color)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Metric Pill

struct MetricPill: View {
    let iconName: String
    let label: String
    let value: String
    var trend: TrendDirection = .neutral

    enum TrendDirection { case up, down, neutral }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

            if trend != .neutral {
                Image(systemName: trend == .up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 8))
                    .foregroundColor(trend == .up ? .forgeSuccess : .forgeDanger)
            }

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.forgeSurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.forgeBorder, lineWidth: 1))
    }
}

// MARK: - Ember Button

struct EmberButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient.emberGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .ember.opacity(0.35), radius: 16, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Header

struct GlassHeader<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .background(Color.forgeBackground.opacity(0.8))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.forgeBorder),
                alignment: .bottom
            )
    }
}

// MARK: - Section Label

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(.textTertiary)
    }
}

// MARK: - Coaching Badge

struct CoachingBadge: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.ember.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "cpu")
                        .font(.system(size: 14))
                        .foregroundColor(.ember)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Color.ember).frame(width: 6, height: 6)
                    Text("Forge AI")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.ember)
                }
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(3)
            }
        }
        .padding(14)
        .background(Color.forgeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.forgeBorder, lineWidth: 1)
        )
        .overlay(
            Rectangle()
                .fill(Color.ember)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1)),
            alignment: .leading
        )
    }
}

// MARK: - Sparkline Chart

struct SparklineChart: View {
    let values: [Double]
    var color: Color = .ember
    var height: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 1
            let range = maxVal - minVal == 0 ? 1 : maxVal - minVal

            let points: [CGPoint] = values.enumerated().map { i, val in
                let x = CGFloat(i) / CGFloat(max(values.count - 1, 1)) * w
                let y = h - ((val - minVal) / range) * (h - 8) - 4
                return CGPoint(x: x, y: y)
            }

            // Area fill
            Path { path in
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.x, y: h))
                path.addLine(to: first)
                for pt in points.dropFirst() { path.addLine(to: pt) }
                path.addLine(to: CGPoint(x: points.last!.x, y: h))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.3), color.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )

            // Line
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for pt in points.dropFirst() { path.addLine(to: pt) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // End dot
            if let last = points.last {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .position(last)
            }
        }
        .frame(height: height)
    }
}
