import SwiftUI
import ForgeCore

// ============================================================
// MARK: - Tomorrow's Readiness Forecast Card
// ============================================================

/// Tomorrow morning, tonight. Home (At Home) and Lifestyle share this plate
/// so the forecast is one world-class surface — not a stub in either place.
///
/// Lifestyle coach only: posture and drivers, never a diagnosis.
struct ReadinessForecastCard: View {
    @EnvironmentObject var store: AppStore
    var compact: Bool = false

    private var picture: PredictiveCoach.Picture {
        store.predictiveCoachPicture()
    }

    var body: some View {
        let forecast = picture.forecast
        let budgets = picture.budgets
        let energy = postureColor(forecast.posture)
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            HStack {
                Text("TOMORROW'S READINESS")
                    .forgeSectionLabel()
                    .foregroundStyle(HudChrome.plate)
                Spacer()
                confidencePill(forecast.confidence)
            }

            HStack(spacing: compact ? 12 : 16) {
                HudProgressRing(
                    progress: forecast.predictedScore,
                    energy: energy,
                    size: compact ? HudChrome.compactRingSize : 108,
                    stroke: compact ? HudChrome.compactStroke : 7
                ) {
                    VStack(spacing: 0) {
                        Text("\(forecast.predictedScore)")
                            .font(compact ? HomeType.metric : HomeType.heroScore)
                            .foregroundColor(.textPrimary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text("TOMORROW")
                            .font(FDS.TypeScale.label(8))
                            .foregroundColor(HudChrome.plate)
                            .tracking(0.8)
                            .hudInArcText()
                    }
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(postureTitle(forecast.posture))
                        .font(HomeType.status)
                        .foregroundColor(.textPrimary)
                    Text(forecast.recommendation)
                        .font(HomeType.body)
                        .foregroundColor(.textTertiary)
                        .lineLimit(compact ? 2 : 3)
                    Text(budgets.headline)
                        .font(FDS.TypeScale.label(12))
                        .foregroundStyle(energy)
                    if !compact {
                        Text(budgets.coachingLine)
                            .font(HomeType.body)
                            .foregroundColor(.textSecondary)
                            .lineLimit(3)
                    }
                }
            }

            if !forecast.drivers.isEmpty {
                Divider().background(Color.white.opacity(0.08))
                VStack(spacing: 10) {
                    ForEach(forecast.drivers.prefix(compact ? 2 : 3)) { driver in
                        driverRow(driver)
                    }
                }
            }

            Button {
                FDS.haptic(.light)
                store.openChat(with: HomeInsightFlow.tomorrowPrompt(picture: picture), voice: false)
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
                .foregroundStyle(HudChrome.plate)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(HudChrome.plate.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .hudPlate(energy: energy, compact: compact)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tomorrow's readiness forecast: \(forecast.predictedScore). \(forecast.recommendation) \(budgets.headline). \(budgets.coachingLine)")
    }

    private func confidencePill(_ confidence: ReadinessForecastEngine.Confidence) -> some View {
        let (label, color): (String, Color) = switch confidence {
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

    private func postureTitle(_ posture: ReadinessForecastEngine.Posture) -> String {
        switch posture {
        case .push: return "Green light"
        case .steady: return "Steady as planned"
        case .protect: return "Protect tomorrow"
        case .rest: return "Rest is the work"
        }
    }

    private func postureColor(_ posture: ReadinessForecastEngine.Posture) -> Color {
        switch posture {
        case .push: return .success
        case .steady: return HudChrome.plate
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
