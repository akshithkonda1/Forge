import SwiftUI

// MARK: - Home Tab (mirrors home-page.tsx)

struct HomeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                AIGreetingView()
                ReadinessSectionView()
                if let workout = store.todayWorkout {
                    TodayPlanCardView(workout: workout)
                }
                QuickStatsView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 32)
        }
        .background(Color.background.ignoresSafeArea())
    }
}

// MARK: - AI Greeting (mirrors ai-greeting.tsx)

struct AIGreetingView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting = hour < 12 ? "Morning" : hour < 17 ? "Afternoon" : "Evening"
        let deep = store.dailyMetrics.deepSleep
        let hrs = deep / 60; let mins = deep % 60
        let deepStr = hrs > 0 ? "\(hrs)hr \(mins)min" : "\(mins)min"
        var parts: [String] = []
        parts.append("\(timeGreeting) \(store.userProfile.name).")
        if store.readiness.sleepQuality >= 80 {
            parts.append("Your deep sleep was solid last night — \(deepStr).")
        } else if store.readiness.sleepQuality >= 60 {
            parts.append("Deep sleep came in at \(deepStr) — decent, but room to improve.")
        } else {
            parts.append("Only \(deepStr) of deep sleep last night. Let's keep that in mind.")
        }
        if store.dailyMetrics.hrv >= 50 {
            parts.append("HRV is looking strong at \(store.dailyMetrics.hrv)ms.")
        } else if store.dailyMetrics.hrv >= 35 {
            parts.append("HRV is at \(store.dailyMetrics.hrv)ms — moderate range.")
        } else {
            parts.append("HRV is low at \(store.dailyMetrics.hrv)ms — recovery might be lagging.")
        }
        let label = readinessLabel(store.readiness.overall).lowercased()
        if let name = store.todayWorkout?.name {
            if store.readiness.overall >= 80 {
                parts.append("You're \(label) for a heavy session today. Ready to hit \(name)?")
            } else if store.readiness.overall >= 60 {
                parts.append("You're in \(label) shape. I've adjusted \(name) to match your recovery.")
            } else {
                parts.append("Recovery is lower today. I'd suggest going lighter on \(name) or swapping for mobility.")
            }
        }
        return parts.joined(separator: " ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                Circle().fill(Color.ember).frame(width: 36, height: 36)
                Text("F").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Forge AI Trainer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ember)

                Text(greeting)
                    .font(.system(size: 14))
                    .foregroundColor(.textPrimary)
                    .lineSpacing(4)

                Button(action: { store.activeTab = .chat }) {
                    Label("Chat with Forge", systemImage: "message.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ember)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(
            Rectangle().fill(Color.ember).frame(width: 2),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(appear ? 1 : 0)
        .offset(x: appear ? 0 : -20)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appear = true } }
    }
}

// MARK: - Readiness Section (mirrors readiness-section.tsx)

struct ReadinessSectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            // Label
            HStack {
                Text("READINESS SCORE")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .tracking(1.2)
                Spacer()
            }
            .padding(.bottom, 20)

            // Ring
            ReadinessRingView(score: store.readiness.overall, size: 180, strokeWidth: 14)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)

            // Breakdown grid
            let items: [(String, Int, Bool)] = [
                ("Sleep Quality", store.readiness.sleepQuality, false),
                ("Recovery",      store.readiness.recoveryScore, false),
                ("Stress",        store.readiness.stressLevel,   true),
                ("Energy Bank",   store.readiness.energyBank,    false),
            ]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    BreakdownCardView(label: item.0, value: item.1, inverted: item.2, index: idx)
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 20)
        .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.1)) { appear = true } }
    }
}

struct BreakdownCardView: View {
    let label: String
    let value: Int
    let inverted: Bool
    let index: Int
    @State private var appear = false

    var displayValue: Int { inverted ? 100 - value : value }
    var displayStr: String { inverted ? "\(100 - value)%" : "\(value)%" }
    var dotColor: Color { readinessColor(displayValue) }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(displayStr)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .onAppear { withAnimation(.easeOut(duration: 0.3).delay(0.6 + Double(index) * 0.1)) { appear = true } }
    }
}

// MARK: - Readiness Ring (mirrors readiness-ring.tsx)

struct ReadinessRingView: View {
    let score: Int
    let size: CGFloat
    let strokeWidth: CGFloat
    var showLabel: Bool = true

    @State private var progress: CGFloat = 0

    var scoreColor: Color { readinessColor(score) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.borderColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: scoreColor.opacity(0.35), radius: 8, x: 0, y: 0)
                .animation(.spring(response: 1.2, dampingFraction: 0.75).delay(0.3), value: progress)

            VStack(spacing: 4) {
                Text("\(score)")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                if showLabel {
                    Text(readinessLabel(score))
                        .font(.system(size: size * 0.085, weight: .medium))
                        .foregroundColor(scoreColor)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { progress = CGFloat(score) / 100 }
    }
}

// MARK: - Today's Plan Card (mirrors today-plan-card.tsx)

struct TodayPlanCardView: View {
    let workout: WorkoutPlan
    @EnvironmentObject var store: AppStore
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY'S PLAN")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textTertiary)
                .tracking(1.2)
                .padding(.bottom, 12)

            Text(workout.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 12)

            // Pills row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    InfoPill(icon: "dumbbell.fill", text: workout.type.label)
                    InfoPill(icon: "clock.fill", text: "~\(workout.duration) min")
                    IntensityInfoPill(intensity: workout.intensity)
                }
            }
            .padding(.bottom, 20)

            // Exercise preview
            VStack(spacing: 10) {
                ForEach(Array(workout.exercises.prefix(3).enumerated()), id: \.element.id) { idx, ex in
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color.surfaceElevated).frame(width: 24, height: 24)
                            Text("\(idx+1)").font(.system(size: 10, weight: .bold)).foregroundColor(.textTertiary)
                        }
                        Text(ex.name).font(.system(size: 14)).foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(ex.sets) × \(ex.reps)").font(.system(size: 12)).foregroundColor(.textTertiary)
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(x: appear ? 0 : -10)
                    .animation(.easeOut(duration: 0.3).delay(0.4 + Double(idx) * 0.1), value: appear)
                }
                if workout.exercises.count > 3 {
                    Text("+\(workout.exercises.count - 3) more exercises")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .padding(.leading, 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 20)

            // Start button
            Button(action: { store.startWorkout(); store.activeTab = .workout }) {
                HStack(spacing: 8) {
                    Text("Start Workout").font(.system(size: 16, weight: .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.ember)
                .cornerRadius(12)
                .shadow(color: Color.ember.opacity(0.35), radius: 14, x: 0, y: 4)
            }

            Button(action: { store.activeTab = .chat }) {
                Text("Change Plan")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 20)
        .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.2)) { appear = true } }
    }
}

struct InfoPill: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(.textTertiary)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.surfaceElevated).cornerRadius(100)
    }
}

struct IntensityInfoPill: View {
    let intensity: WorkoutIntensity
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(intensity.color).frame(width: 6, height: 6)
            Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundColor(.textTertiary)
            Text(intensity.label).font(.system(size: 12, weight: .medium)).foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.surfaceElevated).cornerRadius(100)
    }
}

// MARK: - Quick Stats (mirrors quick-stats.tsx)

struct QuickStatsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                MetricPillView(icon: "figure.walk",     iconColor: .success, value: store.dailyMetrics.steps.formatted(), label: "Steps",      trend: .up)
                MetricPillView(icon: "flame.fill",      iconColor: .ember,   value: "\(store.dailyMetrics.activeCalories)", label: "Cal",   trend: .up)
                MetricPillView(icon: "heart.fill",      iconColor: .danger,  value: "\(store.dailyMetrics.hrv)ms", label: "HRV",             trend: .up)
                MetricPillView(icon: "heart.circle.fill", iconColor: .steel, value: "\(store.dailyMetrics.restingHR)", label: "Resting HR",  trend: .down)
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }
}

enum TrendDir { case up, down, neutral }

struct MetricPillView: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    let trend: TrendDir

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundColor(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(value).font(.system(size: 15, weight: .bold)).foregroundColor(.textPrimary)
                    Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10))
                        .foregroundColor(trend == .up ? .success : .danger)
                }
                Text(label).font(.system(size: 11)).foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.surface)
        .cornerRadius(100)
    }
}
