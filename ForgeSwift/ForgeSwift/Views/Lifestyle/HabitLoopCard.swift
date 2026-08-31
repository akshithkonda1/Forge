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
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
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
    @State private var triedIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "forge.habits.tried") ?? [])

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

            if vm.deepHabits.isEmpty {
                Text("No strong loop detected — your signals look balanced today. One small habit still compounds.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(vm.deepHabits) { habit in
                    HabitLoopCard(habit: habit, onTry: {
                        var tried = UserDefaults.standard.stringArray(forKey: "forge.habits.tried") ?? []
                        if !tried.contains(habit.id) { tried.append(habit.id) }
                        UserDefaults.standard.set(tried, forKey: "forge.habits.tried")
                        triedIds.insert(habit.id)
                        // Feedback into ARIA context
                        Task {
                            AriaContextStore.shared.addInsight("Tried habit breaker: \(habit.id) — \(habit.breaker)")
                        }
                        FeedbackGenerator.light()
                    }, onSnooze: {
                        FeedbackGenerator.light()
                    })
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
        .onAppear {
            Task { await vm.syncIfNeeded() }
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
