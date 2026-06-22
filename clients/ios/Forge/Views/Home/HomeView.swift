import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ARIAGreetingCard()
                ReadinessSection()
                if store.todayWorkout != nil {
                    TodayPlanCard()
                }
                QuickStats()
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 100)
        }
        .background(Color.forgeBackground)
    }
}

// MARK: - ARIA Greeting Card

struct ARIAGreetingCard: View {
    @EnvironmentObject var store: AppStore
    @State private var visibleCount = 0
    @State private var typewriterTask: Task<Void, Never>?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting = hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening"
        let name = store.userProfile.name
        let r = store.readiness
        let m = store.dailyMetrics
        let deepFormatted = formatDeepSleep(m.deepSleep)

        var parts = ["\(timeGreeting) \(name)."]

        if r.sleepQuality >= 80 {
            parts.append("Your deep sleep was solid last night — \(deepFormatted).")
        } else {
            parts.append("Deep sleep came in at \(deepFormatted) — room to improve.")
        }

        parts.append("HRV is at \(m.hrv)ms\(m.hrv >= 50 ? " — looking strong." : ".")")

        if let w = store.todayWorkout {
            if r.overall >= 80 {
                parts.append("You're primed for a heavy session. Ready to hit \(w.name)?")
            } else if r.overall >= 60 {
                parts.append("I've adjusted \(w.name) to match your recovery.")
            } else {
                parts.append("Recovery is lower today. Consider going lighter on \(w.name).")
            }
        }

        return parts.joined(separator: " ")
    }

    private func formatDeepSleep(_ minutes: Int) -> String {
        let hrs = minutes / 60
        let mins = minutes % 60
        return hrs > 0 ? "\(hrs)hr \(mins)min" : "\(mins)min"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.ember)
                .frame(width: 36, height: 36)
                .overlay(
                    Text("F")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("Forge AI Trainer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ember)

                Text(String(greeting.prefix(min(visibleCount, 120))))
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineSpacing(4)

                Button {
                    withAnimation(FDS.Spring.page) { store.activeTab = .chat }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 12))
                        Text("Chat with Forge")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.ember)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color.forgeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            Rectangle()
                .fill(Color.ember)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1)),
            alignment: .leading
        )
        .onAppear {
            typewriterTask?.cancel()
            visibleCount = 0
            let text = greeting
            typewriterTask = Task {
                let limit = min(text.count, 120)
                for index in 0...limit {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: 28_000_000)
                    if Task.isCancelled { return }
                    await MainActor.run { visibleCount = index }
                }
            }
        }
        .onDisappear {
            typewriterTask?.cancel()
            typewriterTask = nil
        }
    }
}

// MARK: - Readiness Section

struct ReadinessSection: View {
    @EnvironmentObject var store: AppStore

    private var breakdownItems: [(label: String, value: Int, inverted: Bool)] {
        let r = store.readiness
        return [
            ("Sleep Quality", r.sleepQuality, false),
            ("Recovery", r.recoveryScore, false),
            ("Stress", r.stressLevel, true),
            ("Energy Bank", r.energyBank, false),
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            SectionLabel(text: "Readiness Score")
                .frame(maxWidth: .infinity, alignment: .leading)

            ReadinessRing(score: store.readiness.overall, size: 180, strokeWidth: 14)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(breakdownItems, id: \.label) { item in
                    let displayVal = item.inverted ? 100 - item.value : item.value
                    HStack(spacing: 8) {
                        Circle()
                            .fill(readinessColor(for: displayVal))
                            .frame(width: 8, height: 8)

                        Text(item.label)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)

                        Spacer()

                        Text("\(displayVal)%")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(10)
                    .background(Color.forgeSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .forgeCard()
    }
}

// MARK: - Today's Plan Card

struct TodayPlanCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if let workout = store.todayWorkout {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Today's Plan")

                Text(workout.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                // Info pills
                HStack(spacing: 8) {
                    infoPill(icon: "dumbbell.fill", text: workout.type.label)
                    infoPill(icon: "clock", text: "~\(workout.duration) min")
                    infoPill(icon: "bolt.fill", text: workout.intensity.rawValue.capitalized)
                }

                // Exercise preview
                VStack(spacing: 8) {
                    ForEach(Array(workout.exercises.prefix(3).enumerated()), id: \.element.id) { i, ex in
                        HStack {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.textTertiary)
                                .frame(width: 24, height: 24)
                                .background(Color.forgeSurfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            Text(ex.name)
                                .font(.system(size: 14))
                                .foregroundColor(.white)

                            Spacer()

                            Text("\(ex.sets) × \(ex.reps)")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                    }

                    if workout.exercises.count > 3 {
                        Text("+\(workout.exercises.count - 3) more exercises")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .padding(.leading, 36)
                    }
                }
                .padding(.vertical, 4)

                EmberButton(title: "Start Workout", icon: "chevron.right") {
                    store.startWorkout()
                    withAnimation(FDS.Spring.page) { store.activeTab = .workout }
                }

                Button {
                    withAnimation(FDS.Spring.page) { store.activeTab = .chat }
                } label: {
                    Text("Change Plan")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .forgeCard()
        }
    }

    private func infoPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.forgeSurfaceElevated)
        .clipShape(Capsule())
    }
}

// MARK: - Quick Stats

struct QuickStats: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Today's Metrics")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    MetricPill(iconName: "figure.walk", label: "Steps",
                               value: formatNumber(store.dailyMetrics.steps), trend: .up)
                    MetricPill(iconName: "flame.fill", label: "Calories",
                               value: "\(store.dailyMetrics.activeCalories) cal", trend: .up)
                    MetricPill(iconName: "waveform.path.ecg", label: "HRV",
                               value: "\(store.dailyMetrics.hrv) ms", trend: .up)
                    MetricPill(iconName: "heart.fill", label: "Resting HR",
                               value: "\(store.dailyMetrics.restingHR) bpm", trend: .down)
                }
            }
        }
    }

    private func formatNumber(_ num: Int) -> String {
        num >= 1000 ? String(format: "%.1fk", Double(num) / 1000.0) : "\(num)"
    }
}
