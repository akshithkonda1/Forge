import SwiftUI
import ForgeCore

// MARK: - WeekView
//
// What you actually did this week. The watch could start a workout and log a
// practice and then had nothing to say about either — every backward-looking
// question meant reaching for the phone, which is the wrong way round for the
// device that recorded it.
//
// Counts and totals only, no scoring. A week with two sessions in it is not a
// failed week, and a surface that grades one is a surface people stop opening.

struct WeekView: View {
    @Environment(WatchHealthKitManager.self) private var health
    @Environment(MindfulnessSessionManager.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeDS.Spacing.md) {
                readinessTrend
                totals
                nights
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("This week")
    }

    // MARK: Readiness

    private var scores: [Int] {
        // Sleep quality per night is the readiness input the watch actually
        // keeps a week of; overall readiness is only computed for today.
        health.recentNights.prefix(7).compactMap { night in
            let inputs = ReadinessInputs(
                sleepMinutes: night.totalMinutes,
                deepSleepMinutes: night.deepMinutes,
                remSleepMinutes: night.remMinutes
            )
            let score = ReadinessCalculator.score(from: inputs)
            return score.confidence > 0 ? score.sleepQuality : nil
        }
    }

    private var readinessTrend: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            Text("Sleep quality")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ForgePalette.textSecondary)

            if scores.count >= 2 {
                Sparkline(values: scores.reversed().map(Double.init))
                    .frame(height: 34)
                    .accessibilityElement()
                    .accessibilityLabel(trendAccessibility)
            } else {
                Text("A couple more nights and a trend appears here.")
                    .font(.system(size: 11))
                    .foregroundStyle(ForgePalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ForgeDS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.lg).fill(ForgePalette.surface))
    }

    private var trendAccessibility: String {
        guard let latest = scores.first, scores.count >= 2 else { return "Not enough nights yet." }
        let average = scores.reduce(0, +) / scores.count
        let direction = latest > average + 3 ? "above" : latest < average - 3 ? "below" : "close to"
        return "Sleep quality \(latest) last night, \(direction) your \(scores.count)-night average of \(average)."
    }

    // MARK: Totals

    private var totals: some View {
        HStack(spacing: ForgeDS.Spacing.sm) {
            tile(
                value: "\(session.recentSessions.filter(\.completed).count)",
                label: "resets",
                tint: ForgePalette.jade
            )
            tile(
                value: "\(Int(health.mindfulMinutesToday.rounded()))",
                label: "mindful min\ntoday",
                tint: ForgePalette.violet
            )
            tile(
                value: health.hoursSinceLastWorkout.map { hours in
                    hours < 24 ? "\(Int(hours))h" : "\(Int(hours / 24))d"
                } ?? "–",
                label: "since\ntraining",
                tint: ForgePalette.ember
            )
        }
    }

    private func tile(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(ForgeType.metric(18))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(ForgePalette.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ForgeDS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.md).fill(ForgePalette.surface))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.replacingOccurrences(of: "\n", with: " "))")
    }

    // MARK: Nights

    private var nights: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            Text("Nights")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ForgePalette.textSecondary)

            if health.recentNights.isEmpty {
                Text("No sleep recorded yet. Wear your watch overnight and this fills in.")
                    .font(.system(size: 11))
                    .foregroundStyle(ForgePalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(health.recentNights.prefix(7).enumerated()), id: \.offset) { _, night in
                    HStack {
                        Text(night.start.map(Self.dayLabel) ?? "—")
                            .font(.system(size: 11))
                            .foregroundStyle(ForgePalette.textSecondary)
                            .frame(width: 34, alignment: .leading)
                        Text(night.durationLabel)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(ForgePalette.textPrimary)
                        Spacer(minLength: 0)
                        Text("\(Int(night.deepMinutes.rounded()))m deep")
                            .font(.system(size: 10))
                            .foregroundStyle(ForgePalette.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(ForgeDS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.lg).fill(ForgePalette.surface))
    }

    private static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Sparkline

/// A line, not a chart. Swift Charts is available but a 7-point trend on a
/// 41mm screen needs one stroke and a dot, and Canvas draws that in well under
/// the frame budget the breathing session already competes for.
private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2 else { return }
            let lowest = values.min() ?? 0
            let highest = values.max() ?? 1
            let span = max(1, highest - lowest)

            func point(_ index: Int) -> CGPoint {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let normalized = (values[index] - lowest) / span
                // Inset so the extremes are not clipped by the stroke width.
                let y = size.height * (1 - CGFloat(normalized)) * 0.86 + size.height * 0.07
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            path.move(to: point(0))
            for index in 1..<values.count { path.addLine(to: point(index)) }
            context.stroke(
                path,
                with: .color(ForgePalette.steel),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            let last = point(values.count - 1)
            context.fill(
                Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)),
                with: .color(ForgePalette.steelLight)
            )
        }
        .drawingGroup()
    }
}
