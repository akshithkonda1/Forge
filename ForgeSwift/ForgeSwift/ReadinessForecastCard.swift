import SwiftUI
import ForgeCore

// ============================================================
// MARK: - Tomorrow's Readiness Forecast Card
// ============================================================

/// Nobody in the consumer space forecasts tomorrow's readiness — Oura,
/// Whoop, and Apple Health all report today's state. This card predicts
/// tomorrow morning from tonight's signals, names every driver, and tells
/// the person what to do about it.
///
/// The engine is transparent by design: each point of movement is attributed,
/// so the forecast can coach instead of just scoring.
struct ReadinessForecastCard: View {
    @EnvironmentObject var store: AppStore

    private var forecast: ReadinessForecastEngine.Forecast {
        store.predictiveCoachPicture().forecast
    }

    private var budgets: TomorrowBudgets.Snapshot {
        store.predictiveCoachPicture().budgets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TOMORROW'S READINESS")
                    .forgeSectionLabel()
                    .foregroundStyle(Color.ember)
                Spacer()
                confidencePill
            }

            HStack(spacing: 16) {
                scoreRing
                VStack(alignment: .leading, spacing: 6) {
                    Text(postureTitle)
                        .font(HomeType.status)
                        .foregroundColor(.textPrimary)
                    Text(forecast.recommendation)
                        .font(HomeType.body)
                        .foregroundColor(.textTertiary)
                        .lineLimit(3)
                    Text(budgets.headline)
                        .font(FDS.TypeScale.label(12))
                        .foregroundStyle(Color.ember)
                    Text(budgets.coachingLine)
                        .font(HomeType.body)
                        .foregroundColor(.textSecondary)
                        .lineLimit(3)
                }
            }

            if !forecast.drivers.isEmpty {
                Divider().background(Color.white.opacity(0.08))
                VStack(spacing: 10) {
                    ForEach(forecast.drivers.prefix(3)) { driver in
                        driverRow(driver)
                    }
                }
            }

            Button {
                FDS.haptic(.light)
                store.openChat(with: HomeInsightFlow.tomorrowPrompt(picture: store.predictiveCoachPicture()), voice: false)
            } label: {
                HStack {
                    Image(systemName: "message.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Ask ARIA about tomorrow")
                        .font(FDS.TypeScale.label(13))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.ember)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Color.ember.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tomorrow's readiness forecast: \(forecast.predictedScore). \(forecast.recommendation) \(budgets.headline). \(budgets.coachingLine)")
    }

    // MARK: - Pieces

    private var confidencePill: some View {
        let (label, color): (String, Color) = switch forecast.confidence {
        case .high: ("High confidence", Color.success)
        case .medium: ("Medium confidence", Color.warning)
        case .low: ("Early signal", Color.textTertiary)
        }
        return Text(label.uppercased())
            .font(FDS.TypeScale.label(10))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)
                .frame(width: 84, height: 84)
            Circle()
                .trim(from: 0, to: CGFloat(forecast.predictedScore) / 100)
                .stroke(postureColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(forecast.predictedScore)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("TOMORROW")
                    .font(FDS.TypeScale.label(8))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var postureTitle: String {
        switch forecast.posture {
        case .push: return "Green light"
        case .steady: return "Steady as planned"
        case .protect: return "Protect tomorrow"
        case .rest: return "Rest is the work"
        }
    }

    private var postureColor: Color {
        switch forecast.posture {
        case .push: return .success
        case .steady: return .ember
        case .protect: return .warning
        case .rest: return .danger
        }
    }

    private func driverRow(_ driver: ReadinessForecastEngine.Driver) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((driver.impact < 0 ? Color.danger : Color.success).opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: driver.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(driver.impact < 0 ? Color.danger : Color.success)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(driver.title)
                    .font(FDS.TypeScale.label(13))
                    .foregroundColor(.textPrimary)
                Text(driver.detail)
                    .font(FDS.TypeScale.label(11))
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            Text(driver.impact > 0 ? "+\(driver.impact)" : "\(driver.impact)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(driver.impact < 0 ? Color.danger : Color.success)
                .monospacedDigit()
        }
    }
}
