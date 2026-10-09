import SwiftUI
import ForgeCore

/// Deep habit companion card — the Lifestyle surface for ARIA's habit loop.
/// Shows cue → routine → cost + one breaker, not a checklist.
struct HabitLoopCard: View {
    let habit: DeepHabit
    var onTry: () -> Void
    var onSnooze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: habit.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ember)
                    .frame(width: 28, height: 28)
                    .background(Color.ember.opacity(0.12))
                    .clipShape(Circle())
                Text(habit.title)
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(Int(habit.confidence * 100))%")
                    .font(FDS.TypeScale.Dynamic.micro)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, FDS.Spacing.sm).padding(.vertical, FDS.Spacing.xs)
                    .forgeInsetTile(radius: FDS.Radius.xs)
            }

            // Loop
            VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                LoopRow(label: "Cue", text: habit.cue)
                LoopRow(label: "Routine", text: habit.routine)
                LoopRow(label: "Cost", text: habit.cost, color: .danger)
            }
            .padding(FDS.Spacing.md)
            .forgeInsetTile(radius: FDS.Radius.md)

            // Evidence — your numbers
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(.steel)
                Text(habit.evidence)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }

            // Breaker
            VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                Text(habit.breaker)
                    .font(FDS.TypeScale.Dynamic.caption)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: FDS.Spacing.md) {
                    Button(action: onTry) {
                        Text(habit.breakerAction)
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FDS.Spacing.md)
                            .background(Color.ember)
                            .cornerRadius(FDS.Radius.sm)
                    }
                    Button(action: onSnooze) {
                        Text("Not now")
                            .font(FDS.TypeScale.Dynamic.caption)
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, FDS.Spacing.md)
                            .forgeInsetTile(radius: FDS.Radius.sm)
                    }
                }
            }
            .padding(FDS.Spacing.md)
            .background(Color.ember.opacity(0.06))
            .cornerRadius(FDS.Radius.md)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.ember.opacity(0.15), lineWidth: 1))
        }
        .padding(FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .ember)
    }
}

private struct LoopRow: View {
    let label: String
    let text: String
    var color: Color = .textSecondary
    var body: some View {
        HStack(alignment: .top, spacing: FDS.Spacing.sm) {
            Text(label)
                .font(FDS.TypeScale.Dynamic.micro)
                .foregroundColor(.textTertiary)
                .frame(width: 56, alignment: .leading)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HabitLoopListCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @State private var pendingFeedback: TriedHabit? = HabitFeedbackStore.pendingFeedback()

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack {
                Text("Today's Loop")
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                if !vm.deepHabits.isEmpty {
                    Text("\(vm.deepHabits.count) live")
                        .font(FDS.TypeScale.Dynamic.micro)
                        .foregroundColor(.ember)
                        .padding(.horizontal, FDS.Spacing.sm).padding(.vertical, FDS.Spacing.xs)
                        .background(Color.ember.opacity(0.12))
                        .cornerRadius(FDS.Radius.xs)
                }
            }

            // Morning feedback — did it work? (appears day after you try)
            if let pending = pendingFeedback {
                VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                    Text("Did it work?")
                        .font(FDS.TypeScale.Dynamic.caption).foregroundColor(.ember)
                    Text("You tried \(pending.breaker) yesterday.")
                        .font(.system(size: 13)).foregroundColor(.textSecondary)
                    HStack(spacing: FDS.Spacing.md) {
                        Button {
                            HabitFeedbackStore.submitFeedback(habitId: pending.habitId, answer: "yeah")
                            if let habit = vm.deepHabits.first(where: { $0.id == pending.habitId }) {
                                AriaContextStore.shared.addInsight(HabitFeedbackStore.feedbackInsight(for: habit, answer: "yeah"))
                                AriaKnowledgeLedgerStore.file(HabitFeedbackStore.outcomeFact(for: habit, answer: "yeah"))
                            }
                            pendingFeedback = nil
                            FeedbackGenerator.light()
                        } label: {
                            Text("Yeah ✓").font(FDS.TypeScale.Dynamic.caption).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, FDS.Spacing.sm).background(Color.success).cornerRadius(FDS.Radius.sm)
                        }
                        Button {
                            HabitFeedbackStore.submitFeedback(habitId: pending.habitId, answer: "nah")
                            if let habit = vm.deepHabits.first(where: { $0.id == pending.habitId }) {
                                AriaContextStore.shared.addInsight(HabitFeedbackStore.feedbackInsight(for: habit, answer: "nah"))
                                AriaKnowledgeLedgerStore.file(HabitFeedbackStore.outcomeFact(for: habit, answer: "nah"))
                            }
                            pendingFeedback = nil
                            FeedbackGenerator.light()
                        } label: {
                            Text("Nah — too big").font(FDS.TypeScale.Dynamic.caption).foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity).padding(.vertical, FDS.Spacing.sm).forgeInsetTile(radius: FDS.Radius.sm)
                        }
                    }
                }
                .padding(FDS.Spacing.md).background(Color.success.opacity(0.06)).cornerRadius(FDS.Radius.md)
                .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.success.opacity(0.15), lineWidth: 1))
            }

            if vm.deepHabits.isEmpty {
                Text("No strong loop detected — your signals look balanced today. One small habit still compounds.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, FDS.Spacing.sm)
            } else {
                ForEach(vm.deepHabits) { habit in
                    HabitLoopCard(habit: habit, onTry: {
                        HabitFeedbackStore.markTried(habit)
                        AriaContextStore.shared.addInsight("Tried habit breaker: \(habit.id) — \(habit.breaker)")
                        AriaKnowledgeLedgerStore.file(HabitFeedbackStore.attemptFact(for: habit))
                        FeedbackGenerator.light()
                    }, onSnooze: {
                        FeedbackGenerator.light()
                    })
                }
            }
        }
        .padding(FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .ember)
        .onAppear {
            Task { await vm.syncIfNeeded() }
            pendingFeedback = HabitFeedbackStore.pendingFeedback()
        }
    }
}

private enum FeedbackGenerator {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// Convenience so LifestyleViewModel can be awaited from view
extension LifestyleViewModel {
    func syncIfNeeded() async {
        if deepHabits.isEmpty {
            await load()
        }
    }
}
