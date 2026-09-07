import SwiftUI
import WatchKit
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

    @State private var highlightedNight: Int?
    @State private var crownOffset: Double = 0
    @FocusState private var crownFocused: Bool

    private var readinessTrend: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            HStack {
                Text("Sleep quality")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ForgePalette.textSecondary)
                Spacer(minLength: 0)
                if let idx = highlightedNight, scores.indices.contains(idx) {
                    Text("\(scores.reversed()[idx])")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(ForgePalette.steelLight)
                        .contentTransition(.numericText())
                }
                Image(systemName: "digitalcrown.horizontal.arrow.counterclockwise.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(ForgePalette.textTertiary.opacity(crownFocused ? 0.9 : 0.35))
            }

            if scores.count >= 2 {
                Sparkline(values: scores.reversed().map(Double.init), highlightedIndex: highlightedNight)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Tap cycles highlight.
                        if let current = highlightedNight {
                            let next = current + 1
                            highlightedNight = next < scores.count ? next : nil
                        } else {
                            highlightedNight = 0
                        }
                        WKInterfaceDevice.current().play(.click)
                    }
                    .focusable(true)
                    .focused($crownFocused)
                    .digitalCrownRotation(
                        $crownOffset,
                        from: 0,
                        through: Double(max(0, scores.count - 1)),
                        by: 1,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                    .onChange(of: crownOffset) { _, newValue in
                        let idx = min(max(0, Int(newValue.rounded())), scores.count - 1)
                        highlightedNight = idx
                    }
                    .onAppear {
                        crownFocused = true
                        crownOffset = Double(scores.count - 1)
                    }
                    .accessibilityElement()
                    .accessibilityLabel(trendAccessibility)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            let next = min(scores.count - 1, (highlightedNight ?? -1) + 1)
                            highlightedNight = next
                            crownOffset = Double(next)
                        case .decrement:
                            if let cur = highlightedNight, cur > 0 {
                                highlightedNight = cur - 1
                                crownOffset = Double(cur - 1)
                            } else {
                                highlightedNight = nil
                            }
                        @unknown default: break
                        }
                    }
                HStack(spacing: 4) {
                    Text(highlightedNight != nil ? "Crown to scrub · tap to pin" : "Tap or crown to inspect")
                        .font(.system(size: 8))
                        .foregroundStyle(ForgePalette.textTertiary.opacity(0.5))
                    Spacer(minLength: 0)
                }
            } else {
                Text("A couple more nights and a trend appears here.")
                    .font(.system(size: 11))
                    .foregroundStyle(ForgePalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ForgeDS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.lg).fill(ForgePalette.surface))
        .animation(.easeInOut(duration: 0.2), value: highlightedNight)
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

    @State private var tappedTile: String?

    private func tile(value: String, label: String, tint: Color) -> some View {
        let isTapped = tappedTile == label
        return VStack(spacing: 1) {
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
        .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.md).fill(isTapped ? tint.opacity(0.18) : ForgePalette.surface))
        .scaleEffect(isTapped ? 0.97 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: tappedTile)
        .contentShape(Rectangle())
        .onTapGesture {
            WKInterfaceDevice.current().play(.click)
            tappedTile = label
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                tappedTile = nil
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.replacingOccurrences(of: "\n", with: " "))")
        .accessibilityAddTraits(.isButton)
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
    var highlightedIndex: Int? = nil

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

            // Highlighted dot with outer ring.
            if let idx = highlightedIndex, values.indices.contains(idx) {
                let p = point(idx)
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                    with: .color(ForgePalette.steel.opacity(0.25))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                    with: .color(ForgePalette.steelLight)
                )
            } else {
                let last = point(values.count - 1)
                context.fill(
                    Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)),
                    with: .color(ForgePalette.steelLight)
                )
            }
        }
        .drawingGroup()
    }
}
