import SwiftUI
import ForgeCore

// ============================================================
// MARK: - Training Load Timeline
// ============================================================

/// The acute:chronic workload ratio (ACWR) is the best-validated load
/// signal in sports science — pro teams use it to keep athletes in the
/// 0.8–1.3 sweet spot and out of the >1.5 danger zone. No consumer app
/// shows it. This view brings it to the person it actually belongs to.
///
/// 14 days of strain bars, the 7-day trend, and a plain-language verdict
/// on where this week's load sits against the month.
struct LoadTimelineView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    private var picture: TrainingLoadModel.LoadPicture {
        TrainingLoadModel.picture(sessions: loadSessions(from: store.workoutHistory))
    }

    var body: some View {
        content(for: picture)
    }

    private func content(for pic: TrainingLoadModel.LoadPicture) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header(for: pic)

            strainChart(for: pic)

            if let verdict = pic.acwrVerdict, let acwr = pic.acwr {
                verdictRow(acwr: acwr, verdict: verdict)
            } else {
                Text("Log 8+ sessions and the load ratio appears — it compares this week against your 4-week average, the way pro teams manage injury risk.")
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeWell()
            }

            if pic.heavyStreak >= 2 {
                HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.amber)
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text("\(pic.heavyStreak) heavy days in a row — the forecast expects fatigue to compound.")
                        .font(HomeType.body)
                        .foregroundColor(.textSecondary)
                        .forgeWrapping()
                }
            }
        }
        .forgeContentCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary(for: pic))
    }

    private func header(for pic: TrainingLoadModel.LoadPicture) -> some View {
        ForgeCardHeader(title: "Training Load", tint: .ember) {
            if let acwr = pic.acwr {
                acwrPill(ratio: acwr)
            } else {
                ForgeCardMeta(text: "Building baseline")
            }
        }
    }

    private func verdictRow(acwr: Double, verdict: String) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: acwrIcon(ratio: acwr), tint: acwrColor(ratio: acwr))
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text("Load ratio")
                    .font(HomeType.micro)
                    .foregroundColor(.textTertiary)
                Text(String(format: "%.2f×", acwr))
                    .font(HomeType.metric)
                    .foregroundColor(.textPrimary)
                    .forgeSingleLine()
                    .contentTransition(.numericText())
                Text(verdict)
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .forgeWrapping()
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private func accessibilitySummary(for pic: TrainingLoadModel.LoadPicture) -> String {
        var parts = ["Training load timeline."]
        if let acwr = pic.acwr {
            parts.append(String(format: "Load ratio %.2f.", acwr))
        }
        parts.append(pic.acwrVerdict ?? "Building baseline.")
        if pic.heavyStreak >= 2 {
            parts.append("\(pic.heavyStreak) heavy days in a row.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Chart

    private func strainChart(for pic: TrainingLoadModel.LoadPicture) -> some View {
        let maxStrain = max(10, pic.days.map(\.strain).max() ?? 10)
        let showsLabels = !typeSize.isAccessibilitySize
        return HStack(alignment: .bottom, spacing: FDS.Spacing.xs) {
            ForEach(pic.days) { day in
                VStack(spacing: FDS.Spacing.xs) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: FDS.Radius.xs, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 64)
                        RoundedRectangle(cornerRadius: FDS.Radius.xs, style: .continuous)
                            .fill(barColor(for: day.zone).gradient)
                            .frame(height: max(day.strain > 0 ? 6 : 0, 64 * CGFloat(day.strain / maxStrain)))
                    }
                    .frame(height: 64)
                    if showsLabels {
                        Text(dayLabel(for: day.date))
                            .font(HomeType.micro)
                            .foregroundColor(isToday(day.date) ? .ember : .textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    private func acwrPill(ratio: Double) -> some View {
        ForgeVibeChip(label: acwrLabel(ratio: ratio), energy: acwrColor(ratio: ratio))
    }

    private func acwrLabel(ratio: Double) -> String {
        switch ratio {
        case ..<0.8: return "DETRAINING"
        case 0.8..<1.3: return "SWEET SPOT"
        case 1.3...1.5: return "AGGRESSIVE"
        default: return "DANGER ZONE"
        }
    }

    private func acwrColor(ratio: Double) -> Color {
        switch ratio {
        case ..<0.8: return .steel
        case 0.8..<1.3: return .vitality
        case 1.3...1.5: return .amber
        default: return ForgeProgressChrome.miss
        }
    }

    private func acwrIcon(ratio: Double) -> String {
        switch ratio {
        case 0.8..<1.3: return "checkmark.circle.fill"
        case ..<0.8: return "arrow.down.circle.fill"
        case 1.3...1.5: return "exclamationmark.circle.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private func barColor(for zone: TrainingLoadModel.Zone) -> Color {
        switch zone {
        case .rest: return Color.steel.opacity(0.4)
        case .light: return .amber
        case .moderate: return .ember
        case .heavy: return .emberDark
        }
    }

    private func dayLabel(for date: Date) -> String {
        Self.weekdayFormatter.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func loadSessions(from history: [WorkoutHistory]) -> [TrainingLoadModel.Session] {
        history.compactMap { entry in
            guard let date = WorkoutHistoryWindow.parseDate(entry.date) else { return nil }
            let level: Int = switch entry.intensity {
            case .low: 1
            case .moderate: 2
            case .high: 3
            case .max: 4
            }
            return TrainingLoadModel.Session(
                date: date,
                durationMinutes: entry.duration,
                intensityLevel: level
            )
        }
    }
}
