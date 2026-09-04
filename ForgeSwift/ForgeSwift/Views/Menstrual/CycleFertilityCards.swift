import SwiftUI

struct FertileScoreCard: View {
    let score: Int
    let phase: MenstrualPhase
    let onAskARIA: () -> Void

    private var band: (label: String, color: Color) {
        switch score {
        case 75...: return ("Peak window", Color(hex: "F472B6"))
        case 45..<75: return ("Elevated", Color.ember)
        case 20..<45: return ("Rising / fading", Color.steel)
        default: return ("Low likelihood", Color.textTertiary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FERTILE SCORE")
                        .font(FDS.TypeScale.label(11))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(score)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(band.color)
                        Text("/ 100")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(band.label)
                        .font(FDS.TypeScale.label(12))
                        .foregroundStyle(band.color)
                    Text(phase.label)
                        .font(FDS.TypeScale.body(12))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.steel, Color.ember, Color(hex: "F472B6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * CGFloat(score) / 100.0))
                }
            }
            .frame(height: 8)

            Text("Multi-signal confidence from ovulation method, cycle history, and phase proximity. Lifestyle timing only — not contraception.")
                .font(FDS.TypeScale.body(12))
                .foregroundStyle(.secondary)

            Button(action: onAskARIA) {
                Label("Ask ARIA about this score", systemImage: "sparkles")
                    .font(FDS.TypeScale.label(13))
            }
            .buttonStyle(.bordered)
            .tint(band.color)
        }
        .padding()
        .forgeGlassCard(accent: band.color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fertile score \(score) out of 100, \(band.label)")
    }
}

struct CycleGoalSelectorCard: View {
    let goal: CycleGoal
    let onUpdate: (CycleGoal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your cycle goal")
                .font(FDS.TypeScale.body(12))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(CycleGoal.allCases) { g in
                    Button {
                        onUpdate(g)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: g.icon)
                                .font(.title3)
                            Text(g.label)
                                .font(FDS.TypeScale.body(11))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(goal == g ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                        .foregroundStyle(goal == g ? Color.ember : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: FDS.Radius.sm)
                                .strokeBorder(goal == g ? Color.ember : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            if goal == .avoidPregnancy {
                Label("FAM requires consistent tracking — not a substitute for medical contraception.", systemImage: "exclamationmark.triangle.fill")
                    .font(FDS.TypeScale.body(11))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .padding()
        .forgeGlassCard(accent: .ember)
    }
}

struct TWWSectionCard: View {
    let daysElapsed: Int
    let onAskARIA: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color.ember)
                Text("Two-Week Wait")
                    .font(FDS.TypeScale.body(15))
                    .fontWeight(.semibold)
            }
            Text("Day \(daysElapsed) of your two-week wait")
                .font(FDS.TypeScale.body(14))
            Text("\(max(0, 14 - daysElapsed)) days until you can test")
                .font(FDS.TypeScale.body(12))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(min(daysElapsed, 14)), total: 14.0)
                .tint(Color.ember)
            Button("Ask ARIA about the two-week wait") {
                onAskARIA()
            }
            .buttonStyle(.bordered)
            .tint(Color.ember)
        }
        .padding()
        .forgeGlassCard(accent: .ember)
    }
}

struct CycleConditionSelectorCard: View {
    @Binding var condition: CycleCondition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HEALTH CONDITION")
                    .font(FDS.TypeScale.label(12))
                    .foregroundColor(.textSecondary)
                Text("Personalises cycle predictions and ARIA coaching")
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textTertiary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(CycleCondition.allCases) { c in
                    Button {
                        condition = c
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: c.icon)
                                .font(.title3)
                            Text(c.label)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(condition == c ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                        .foregroundStyle(condition == c ? Color.ember : Color.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: FDS.Radius.sm)
                                .strokeBorder(condition == c ? Color.ember : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .forgeGlassCard(accent: .ember)
    }
}
