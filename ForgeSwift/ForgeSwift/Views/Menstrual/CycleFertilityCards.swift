import SwiftUI
import ForgeCore

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
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                    Text("FERTILE SCORE")
                        .font(FDS.TypeScale.Dynamic.caption)
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.xs) {
                        Text("\(score)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(band.color)
                        Text("/ 100")
                            .font(FDS.TypeScale.Dynamic.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: FDS.Spacing.sm) {
                    Text(band.label)
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundStyle(band.color)
                    Text(phase.label)
                        .font(FDS.TypeScale.Dynamic.caption)
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
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(.secondary)

            Button(action: onAskARIA) {
                Label {
                    Text("Ask ARIA about this score")
                } icon: {
                    ARIAIdentityMark(state: .idle, mood: .energized, size: 14, amplitude: 0.22)
                }
                    .font(FDS.TypeScale.Dynamic.caption)
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
    var lifestyleGoal: CycleLifestyleGoal = .none
    var periodTrainingStyle: CyclePeriodTrainingStyle = .easy
    let onUpdate: (CycleGoal) -> Void
    var onLifestyle: (CycleLifestyleGoal) -> Void = { _ in }
    var onPeriodStyle: (CyclePeriodTrainingStyle) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            Text("Your cycle goal")
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: FDS.Spacing.sm) {
                ForEach(CycleGoal.allCases) { g in
                    Button {
                        onUpdate(g)
                    } label: {
                        VStack(spacing: FDS.Spacing.xs) {
                            Image(systemName: g.icon)
                                .font(.title3)
                            Text(g.label)
                                .font(FDS.TypeScale.Dynamic.caption)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FDS.Spacing.md)
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
            Text("What ARIA should design training around")
                .font(FDS.TypeScale.Dynamic.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: FDS.Spacing.sm) {
                ForEach(Array(CycleLifestyleGoal.allCases.filter { $0 != .none }) + [.none], id: \.self) { g in
                    Button {
                        onLifestyle(g)
                    } label: {
                        VStack(spacing: FDS.Spacing.xs) {
                            Image(systemName: g.icon)
                                .font(.caption)
                            Text(g == .none ? "Ask me" : g.label)
                                .font(FDS.TypeScale.Dynamic.micro)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FDS.Spacing.md)
                        .background(lifestyleGoal == g ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                        .foregroundStyle(lifestyleGoal == g ? Color.ember : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
            if lifestyleGoal != .none {
                Text("While you’re on your period")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: FDS.Spacing.sm) {
                    ForEach(CyclePeriodTrainingStyle.allCases) { style in
                        Button {
                            onPeriodStyle(style)
                        } label: {
                            Text(style.label)
                                .font(FDS.TypeScale.Dynamic.micro)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, FDS.Spacing.md)
                                .background(periodTrainingStyle == style ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                                .foregroundStyle(periodTrainingStyle == style ? Color.ember : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(periodTrainingStyle.runningCopy)
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if goal == .intimacy {
                Text("Healthy sex, safe sex, positions, period sex, partner tips — on this iPhone. Forge is not a contraceptive.")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack {
                Image(systemName: "hourglass")
                    .foregroundStyle(Color.ember)
                Text("Two-Week Wait")
                    .font(FDS.TypeScale.Dynamic.body)
                    .fontWeight(.semibold)
            }
            Text("Day \(daysElapsed) of your two-week wait")
                .font(FDS.TypeScale.Dynamic.body)
            Text("\(max(0, 14 - daysElapsed)) days until you can test")
                .font(FDS.TypeScale.Dynamic.caption)
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
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                Text("HEALTH CONDITION")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundColor(.textSecondary)
                Text("Personalises cycle predictions and ARIA coaching")
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundColor(.textTertiary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(CycleCondition.allCases) { c in
                    Button {
                        condition = c
                    } label: {
                        VStack(spacing: FDS.Spacing.xs) {
                            Image(systemName: c.icon)
                                .font(.title3)
                            Text(c.label)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FDS.Spacing.md)
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
