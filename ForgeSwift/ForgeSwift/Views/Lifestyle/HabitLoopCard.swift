import SwiftUI
import ForgeCore

/// Deep habit companion card — the Lifestyle surface for ARIA's habit loop.
/// Shows cue → routine → cost + one breaker, not a checklist.
struct HabitLoopCard: View {
    let habit: DeepHabit
    var onTry: () -> Void
    var onSnooze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: habit.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ember)
                    .frame(width: 28, height: 28)
                    .background(Color.ember.opacity(0.12))
                    .clipShape(Circle())
                Text(habit.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(Int(habit.confidence * 100))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.surfaceElevated)
                    .cornerRadius(6)
            }

            // Loop
            VStack(alignment: .leading, spacing: 6) {
                LoopRow(label: "Cue", text: habit.cue)
                LoopRow(label: "Routine", text: habit.routine)
                LoopRow(label: "Cost", text: habit.cost, color: .danger)
            }
            .padding(12)
            .background(Color.surfaceElevated)
            .cornerRadius(12)

            // Evidence — your numbers
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(.steel)
                Text(habit.evidence)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }

            // Breaker
            VStack(alignment: .leading, spacing: 10) {
                Text(habit.breaker)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(action: onTry) {
                        Text(habit.breakerAction)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.ember)
                            .cornerRadius(10)
                    }
                    Button(action: onSnooze) {
                        Text("Not now")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.surfaceElevated)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(12)
            .background(Color.ember.opacity(0.06))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ember.opacity(0.15), lineWidth: 1))
        }
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.borderColor.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

private struct LoopRow: View {
    let label: String
    let text: String
    var color: Color = .textSecondary
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Loop")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                if !vm.deepHabits.isEmpty {
                    Text("\(vm.deepHabits.count) live")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.ember)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.ember.opacity(0.12))
                        .cornerRadius(6)
                }
            }

            // Morning feedback — did it work? (appears day after you try)
            if let pending = pendingFeedback {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Did it work?")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.ember)
                    Text("You tried \(pending.breaker) yesterday.")
                        .font(.system(size: 13)).foregroundColor(.textSecondary)
                    HStack(spacing: 10) {
                        Button {
                            HabitFeedbackStore.submitFeedback(habitId: pending.habitId, answer: "yeah")
                            if let habit = vm.deepHabits.first(where: { $0.id == pending.habitId }) {
                                AriaContextStore.shared.addInsight(HabitFeedbackStore.feedbackInsight(for: habit, answer: "yeah"))
                            }
                            pendingFeedback = nil
                            FeedbackGenerator.light()
                        } label: {
                            Text("Yeah ✓").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 9).background(Color.success).cornerRadius(9)
                        }
                        Button {
                            HabitFeedbackStore.submitFeedback(habitId: pending.habitId, answer: "nah")
                            if let habit = vm.deepHabits.first(where: { $0.id == pending.habitId }) {
                                AriaContextStore.shared.addInsight(HabitFeedbackStore.feedbackInsight(for: habit, answer: "nah"))
                            }
                            pendingFeedback = nil
                            FeedbackGenerator.light()
                        } label: {
                            Text("Nah — too big").font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity).padding(.vertical, 9).background(Color.surfaceElevated).cornerRadius(9)
                        }
                    }
                }
                .padding(12).background(Color.success.opacity(0.06)).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.success.opacity(0.15), lineWidth: 1))
            }

            if vm.deepHabits.isEmpty {
                Text("No strong loop detected — your signals look balanced today. One small habit still compounds.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(vm.deepHabits) { habit in
                    HabitLoopCard(habit: habit, onTry: {
                        HabitFeedbackStore.markTried(habit)
                        AriaContextStore.shared.addInsight("Tried habit breaker: \(habit.id) — \(habit.breaker)")
                        FeedbackGenerator.light()
                    }, onSnooze: {
                        FeedbackGenerator.light()
                    })
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.borderColor.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.03), radius: 8, y: 4)
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
