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

    private var picture: TrainingLoadModel.LoadPicture {
        TrainingLoadModel.picture(sessions: loadSessions(from: store.workoutHistory))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TRAINING LOAD")
                    .forgeSectionLabel()
                    .foregroundStyle(Color.ember)
                Spacer()
                if let acwr = picture.acwr {
                    acwrPill(ratio: acwr)
                } else {
                    Text("BUILDING BASELINE")
                        .font(FDS.TypeScale.label(10))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            strainChart

            if let verdict = picture.acwrVerdict, let acwr = picture.acwr {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(acwrColor(ratio: acwr).opacity(0.14))
                            .frame(width: 36, height: 36)
                        Image(systemName: acwrIcon(ratio: acwr))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(acwrColor(ratio: acwr))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "Load ratio %.2f", acwr))
                            .font(FDS.TypeScale.label(13))
                            .foregroundColor(.textPrimary)
                        Text(verdict)
                            .font(FDS.TypeScale.label(11))
                            .foregroundColor(.textTertiary)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Log 8+ sessions and the load ratio appears — it compares this week against your 4-week average, the way pro teams manage injury risk.")
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if picture.heavyStreak >= 2 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.warning)
                        .font(.system(size: 13))
                    Text("\(picture.heavyStreak) heavy days in a row — the forecast expects fatigue to compound.")
                        .font(FDS.TypeScale.label(12))
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Training load timeline. \(picture.acwrVerdict ?? "Building baseline.")")
    }

    // MARK: - Chart

    private var strainChart: some View {
        let maxStrain = max(10, picture.days.map(\.strain).max() ?? 10)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(picture.days) { day in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 64)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor(for: day.zone).gradient)
                            .frame(height: max(day.strain > 0 ? 6 : 0, 64 * CGFloat(day.strain / maxStrain)))
                    }
                    .frame(height: 64)
                    Text(dayLabel(for: day.date))
                        .font(FDS.TypeScale.label(8))
                        .foregroundColor(isToday(day.date) ? .ember : .textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func acwrPill(ratio: Double) -> some View {
        let (label, color): (String, Color) = switch ratio {
        case ..<0.8: ("DETRAINING", Color.warning)
        case 0.8..<1.3: ("SWEET SPOT", Color.success)
        case 1.3...1.5: ("AGGRESSIVE", Color.warning)
        default: ("DANGER ZONE", Color.danger)
        }
        return Text(label)
            .font(FDS.TypeScale.label(10))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func acwrColor(ratio: Double) -> Color {
        switch ratio {
        case 0.8..<1.3: return .success
        case ..<0.8, 1.3...1.5: return .warning
        default: return .danger
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
        case .rest: return Color.white.opacity(0.25)
        case .light: return .success
        case .moderate: return .ember
        case .heavy: return .danger
        }
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
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
