import WidgetKit
import SwiftUI
import ForgeCore
import ActivityKit

// MARK: - CycleFertileWindowLiveActivity
//
// Lock Screen banner + Dynamic Island for cycle fertile window tracking.
// Active during fertileWindow and ovulation phases; shows phase, day,
// fertile score, and ovulation countdown.

struct CycleFertileWindowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CycleLiveActivityAttributes.self) { context in
            LockScreenCycleView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Forge Cycle", systemImage: phaseIcon(state.phase))
                        .font(ForgeFont.sans(13, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let day = state.dayInCycle {
                        Text("Day \(day)")
                            .font(ForgeFont.sans(15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        if state.isActiveFertileWindow {
                            Label("Fertile window open", systemImage: "waveform.path.ecg")
                                .font(ForgeFont.sans(12))
                                .foregroundStyle(Color.orange)
                        }
                        if let score = state.fertileScore {
                            Text("Fertile Score: \(score)/100")
                                .font(ForgeFont.sans(12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } compactLeading: {
                Image(systemName: phaseIcon(state.phase))
                    .foregroundStyle(Color.orange)
            } compactTrailing: {
                if let days = state.daysUntilOvulation {
                    Text("\(days)d")
                        .font(ForgeFont.sans(12, weight: .semibold))
                } else if state.isActiveFertileWindow {
                    Text("Fertile")
                        .font(ForgeFont.sans(12, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }
            } minimal: {
                Image(systemName: phaseIcon(state.phase))
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private func phaseIcon(_ phase: String) -> String {
        switch phase {
        case "menstruation": return "drop.fill"
        case "follicular":   return "leaf.fill"
        case "fertileWindow": return "waveform.path.ecg"
        case "ovulation":    return "circle.circle"
        case "luteal":       return "moon.fill"
        default:             return "circle.dashed"
        }
    }
}

private struct LockScreenCycleView: View {
    let state: CycleLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: phaseIcon(state.phase))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(phaseLabel(state.phase))
                    .font(ForgeFont.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                if state.isActiveFertileWindow {
                    Text("Fertile window open")
                        .font(ForgeFont.sans(12))
                        .foregroundStyle(Color.orange.opacity(0.9))
                } else if let days = state.daysUntilOvulation {
                    Text("Ovulation in ~\(days) day\(days == 1 ? "" : "s")")
                        .font(ForgeFont.sans(12))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()

            if let day = state.dayInCycle {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Day \(day)")
                        .font(ForgeFont.sans(22, weight: .bold))
                        .foregroundStyle(.white)
                    if let score = state.fertileScore {
                        Text("\(score)/100")
                            .font(ForgeFont.sans(12, weight: .medium))
                            .foregroundStyle(Color.orange)
                    }
                }
            }
        }
        .padding(14)
    }

    private func phaseIcon(_ phase: String) -> String {
        switch phase {
        case "menstruation":  return "drop.fill"
        case "follicular":    return "leaf.fill"
        case "fertileWindow": return "waveform.path.ecg"
        case "ovulation":     return "circle.circle"
        case "luteal":        return "moon.fill"
        default:              return "circle.dashed"
        }
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "menstruation":  return "Menstruation"
        case "follicular":    return "Follicular Phase"
        case "fertileWindow": return "Fertile Window"
        case "ovulation":     return "Ovulation"
        case "luteal":        return "Luteal Phase"
        default:              return "Tracking cycle"
        }
    }
}
