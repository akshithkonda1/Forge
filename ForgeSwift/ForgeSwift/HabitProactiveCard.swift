import SwiftUI
import ForgeCore

/// Home proactive habit breaker — the companion nudge that lives where ARIA lives.
/// Shows the top DeepHabit's breaker, not a generic "you're run down".
struct HabitProactiveCard: View {
    let habit: DeepHabit
    var onTap: () -> Void
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: FDS.Spacing.lg) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: habit.category.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.ember)
                }
                VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                    HStack(spacing: FDS.Spacing.sm) {
                        Text("HABIT")
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundColor(.ember).tracking(0.8)
                        Text(habit.title)
                            .font(FDS.TypeScale.Dynamic.micro)
                            .foregroundColor(.textTertiary)
                    }
                    Text(habit.breaker)
                        .font(FDS.TypeScale.Dynamic.body)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                    Text("Try → \(habit.breakerAction) · tap to talk")
                        .font(FDS.TypeScale.Dynamic.micro)
                        .foregroundColor(.ember)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            .padding(FDS.Spacing.lg)
            .forgeGlassCard(accent: .ember)
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 8)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { appeared = true } }
    }
}
