import SwiftUI

// MARK: - Home Tab (World-Class Edition)

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var isRefreshing = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showHeaderBlur = false
    
    var body: some View {
        ZStack(alignment: .top) {
            // Dynamic gradient background
            DynamicHomeBackground(readinessScore: store.readiness.overall)
                .ignoresSafeArea()
            
            // Main content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Floating header
                    HomeHeaderView()
                        .padding(.top, 60)
                        .padding(.horizontal, 20)
                    
                    AIGreetingView()
                    ReadinessSectionView()
                    
                    if let workout = store.todayWorkout {
                        TodayPlanCardView(workout: workout)
                    }
                    
                    QuickStatsView()
                    
                    // Insights section
                    InsightsSectionView()
                    
                    // Recent activity
                    RecentActivityView()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .refreshable {
                await refreshData()
            }
            
            // Floating status bar with blur
            if showHeaderBlur {
                FloatingStatusBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showHeaderBlur)
    }
    
    @MainActor
    func refreshData() async {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        isRefreshing = true
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        // Simulate data refresh
        store.refreshDailyData()
        
        isRefreshing = false
        
        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.notificationOccurred(.success)
    }
}

// MARK: - Dynamic Home Background

struct DynamicHomeBackground: View {
    let readinessScore: Int
    @State private var animateGradient = false
    
    var gradientColors: [Color] {
        if readinessScore >= 80 {
            return [
                Color.background,
                Color.success.opacity(0.05),
                Color.background,
                Color.ember.opacity(0.03)
            ]
        } else if readinessScore >= 60 {
            return [
                Color.background,
                Color.ember.opacity(0.04),
                Color.background,
                Color.steel.opacity(0.03)
            ]
        } else {
            return [
                Color.background,
                Color.steel.opacity(0.05),
                Color.background,
                Color.background
            ]
        }
    }
    
    var body: some View {
        ZStack {
            Color.background
            
            LinearGradient(
                colors: gradientColors,
                startPoint: animateGradient ? .topLeading : .bottomLeading,
                endPoint: animateGradient ? .bottomTrailing : .topTrailing
            )
            .opacity(0.7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
        .animation(.easeInOut(duration: 1.2), value: readinessScore)
    }
}

// MARK: - Home Header

struct HomeHeaderView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    
    var currentDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentDate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .tracking(0.5)
                
                Text("Your Dashboard")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            
            Spacer()
            
            // Profile button with streak indicator
            Button(action: {}) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.surface)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(Color.borderColor, lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.ember)
                        )
                    
                    // Streak badge
                    if store.currentStreak > 0 {
                        ZStack {
                            Circle()
                                .fill(Color.ember)
                                .frame(width: 20, height: 20)
                            
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appear = true
            }
        }
    }
}

// MARK: - Floating Status Bar

struct FloatingStatusBar: View {
    @EnvironmentObject var store: AppStore
    
    var body: some View {
        HStack {
            Text("Readiness: \(store.readiness.overall)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            
            Spacer()
            
            Circle()
                .fill(readinessColor(store.readiness.overall))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .padding(.top, 50)
    }
}

// MARK: - AI Greeting (Enhanced)

struct AIGreetingView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    @State private var isTyping = false
    @State private var displayedText = ""
    @State private var pulseAnimation = false
    
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
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            store.activeTab = .chat
        }) {
            HStack(alignment: .top, spacing: 14) {
                // Enhanced Avatar with glow
                ZStack {
                    // Pulsing glow
                    Circle()
                        .fill(Color.ember.opacity(0.3))
                        .frame(width: 48, height: 48)
                        .blur(radius: 8)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0.0 : 0.8)
                    
                    // Avatar background with gradient
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.ember, Color.ember.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .shadow(color: Color.ember.opacity(0.4), radius: 8)
                    
                    Text("F")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Forge AI Trainer")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.ember)
                        
                        // Active indicator
                        Circle()
                            .fill(Color.success)
                            .frame(width: 6, height: 6)
                    }

                    Text(displayedText.isEmpty ? greeting : displayedText)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.textPrimary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Label("Reply", systemImage: "message.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.ember)
                        
                        Divider()
                            .frame(height: 12)
                            .background(Color.borderColor)
                        
                        Label("Ask anything", systemImage: "sparkles")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(
                ZStack {
                    Color.surface
                    
                    // Subtle gradient overlay
                    LinearGradient(
                        colors: [
                            Color.ember.opacity(0.03),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [Color.ember.opacity(0.3), Color.ember.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .opacity(appear ? 1 : 0)
        .offset(x: appear ? 0 : -30)
        .scaleEffect(appear ? 1 : 0.95)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                appear = true
            }
            
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                pulseAnimation = true
            }
        }
    }
}

// MARK: - Readiness Section (Enhanced)

struct ReadinessSectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with expand button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("READINESS SCORE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1.5)
                    
                    Text("Updated just now")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textMuted)
                }
                
                Spacer()
                
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        showDetails.toggle()
                    }
                }) {
                    Image(systemName: showDetails ? "chevron.up.circle.fill" : "info.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.ember)
                        .rotationEffect(.degrees(showDetails ? 180 : 0))
                }
            }
            .padding(.bottom, 24)

            // Enhanced Ring
            ReadinessRingView(score: store.readiness.overall, size: 200, strokeWidth: 16)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)

            // Breakdown grid
            let items: [(String, Int, Bool)] = [
                ("Sleep Quality", store.readiness.sleepQuality, false),
                ("Recovery",      store.readiness.recoveryScore, false),
                ("Stress",        store.readiness.stressLevel,   true),
                ("Energy Bank",   store.readiness.energyBank,    false),
            ]
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    BreakdownCardView(label: item.0, value: item.1, inverted: item.2, index: idx)
                }
            }
            
            // Detailed insights (expandable)
            if showDetails {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.vertical, 8)
                    
                    ReadinessInsightRow(
                        icon: "moon.stars.fill",
                        title: "Sleep Analysis",
                        value: "\(store.dailyMetrics.deepSleep / 60)h \(store.dailyMetrics.deepSleep % 60)m deep",
                        color: .steel
                    )
                    
                    ReadinessInsightRow(
                        icon: "heart.fill",
                        title: "Heart Rate Variability",
                        value: "\(store.dailyMetrics.hrv)ms",
                        color: .danger
                    )
                    
                    ReadinessInsightRow(
                        icon: "figure.mind.and.body",
                        title: "Training Load",
                        value: "Moderate",
                        color: .ember
                    )
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
                .padding(.top, 8)
            }
        }
        .padding(24)
        .background(
            ZStack {
                Color.surface
                
                // Subtle radial gradient based on readiness
                RadialGradient(
                    colors: [
                        readinessColor(store.readiness.overall).opacity(0.08),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: 200
                )
            }
        )
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 30)
        .scaleEffect(appear ? 1 : 0.95)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.3)) {
                appear = true
            }
        }
    }
}

struct ReadinessInsightRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

struct BreakdownCardView: View {
    let label: String
    let value: Int
    let inverted: Bool
    let index: Int
    @State private var appear = false
    @State private var isPressed = false

    var displayValue: Int { inverted ? 100 - value : value }
    var displayStr: String { inverted ? "\(100 - value)%" : "\(value)%" }
    var dotColor: Color { readinessColor(displayValue) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: dotColor.opacity(0.5), radius: 4)
                
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(displayStr)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.surfaceElevated)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(dotColor.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 15)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.7 + Double(index) * 0.08)) {
                appear = true
            }
        }
    }
}

// MARK: - Readiness Ring (Enhanced)

struct ReadinessRingView: View {
    let score: Int
    let size: CGFloat
    let strokeWidth: CGFloat
    var showLabel: Bool = true

    @State private var progress: CGFloat = 0
    @State private var pulseAnimation = false

    var scoreColor: Color { readinessColor(score) }

    var body: some View {
        ZStack {
            // Background ring with gradient
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.borderColor.opacity(0.5), Color.borderColor.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)

            // Pulsing glow layer
            Circle()
                .trim(from: 0, to: progress)
                .stroke(scoreColor.opacity(0.3), style: StrokeStyle(lineWidth: strokeWidth + 4, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .blur(radius: 6)
                .scaleEffect(pulseAnimation ? 1.02 : 1.0)
                .opacity(pulseAnimation ? 0.5 : 0.8)

            // Main progress ring with enhanced shadow
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [scoreColor, scoreColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: scoreColor.opacity(0.4), radius: 12, x: 0, y: 0)
                .animation(.spring(response: 1.5, dampingFraction: 0.7).delay(0.5), value: progress)

            // Inner content
            VStack(spacing: 6) {
                Text("\(score)")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.textPrimary, scoreColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .contentTransition(.numericText())
                
                if showLabel {
                    VStack(spacing: 2) {
                        Text(readinessLabel(score))
                            .font(.system(size: size * 0.095, weight: .semibold))
                            .foregroundColor(scoreColor)
                        
                        Text("Readiness")
                            .font(.system(size: size * 0.065, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 1.5, dampingFraction: 0.7).delay(0.6)) {
                progress = CGFloat(score) / 100
            }
            
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

// MARK: - Today's Plan Card (Enhanced)

struct TodayPlanCardView: View {
    let workout: WorkoutPlan
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with badge
            HStack {
                Text("TODAY'S PLAN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.5)
                
                Spacer()
                
                // AI-optimized badge
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                    Text("AI Optimized")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.ember)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(6)
            }
            .padding(.bottom, 16)

            Text(workout.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 16)

            // Pills row with scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    InfoPill(icon: "dumbbell.fill", text: workout.type.label)
                    InfoPill(icon: "clock.fill", text: "~\(workout.duration) min")
                    IntensityInfoPill(intensity: workout.intensity)
                    InfoPill(icon: "flame.fill", text: "\(workout.estimatedCalories) cal")
                }
            }
            .padding(.bottom, 24)

            // Exercise preview with enhanced styling
            VStack(spacing: 12) {
                ForEach(Array(workout.exercises.prefix(3).enumerated()), id: \.element.id) { idx, ex in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.ember.opacity(0.15), Color.ember.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32, height: 32)
                            
                            Text("\(idx+1)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.ember)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.textPrimary)
                            
                            Text("\(ex.sets) sets × \(ex.reps) reps")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                    .padding(12)
                    .background(Color.surfaceElevated)
                    .cornerRadius(12)
                    .opacity(appear ? 1 : 0)
                    .offset(x: appear ? 0 : -15)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.5 + Double(idx) * 0.1), value: appear)
                }
                
                if workout.exercises.count > 3 {
                    HStack {
                        Text("+\(workout.exercises.count - 3) more exercises")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                        
                        Spacer()
                        
                        Image(systemName: "ellipsis")
                            .foregroundColor(.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .padding(.bottom, 24)

            // Action buttons
            VStack(spacing: 12) {
                // Start button with gradient
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    store.startWorkout()
                    store.activeTab = .workout
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text("Start Workout")
                            .font(.system(size: 17, weight: .semibold))
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(
                        LinearGradient(
                            colors: [Color.ember, Color.ember.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.ember.opacity(0.4), radius: 16, y: 8)
                }
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)

                // Secondary actions
                HStack(spacing: 12) {
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        store.activeTab = .chat
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13))
                            Text("Change Plan")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.surfaceElevated)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {}) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13))
                            Text("Share")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.surfaceElevated)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(24)
        .background(
            ZStack {
                Color.surface
                
                // Subtle gradient accent
                LinearGradient(
                    colors: [
                        Color.ember.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [Color.ember.opacity(0.2), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 30)
        .scaleEffect(appear ? 1 : 0.95)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.4)) {
                appear = true
            }
        }
    }
}

struct InfoPill: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.surfaceElevated)
        .cornerRadius(100)
    }
}

struct IntensityInfoPill: View {
    let intensity: WorkoutIntensity
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(intensity.color)
                .frame(width: 7, height: 7)
            Image(systemName: "bolt.fill")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
            Text(intensity.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.surfaceElevated)
        .cornerRadius(100)
    }
}

// MARK: - Quick Stats (Enhanced)

struct QuickStatsView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TODAY'S ACTIVITY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.5)
                
                Spacer()
                
                Button(action: {}) {
                    Text("View All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ember)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    MetricPillView(
                        icon: "figure.walk",
                        iconColor: .success,
                        value: store.dailyMetrics.steps.formatted(),
                        label: "Steps",
                        trend: .up,
                        trendValue: "+12%"
                    )
                    MetricPillView(
                        icon: "flame.fill",
                        iconColor: .ember,
                        value: "\(store.dailyMetrics.activeCalories)",
                        label: "Active Cal",
                        trend: .up,
                        trendValue: "+8%"
                    )
                    MetricPillView(
                        icon: "heart.fill",
                        iconColor: .danger,
                        value: "\(store.dailyMetrics.hrv)ms",
                        label: "HRV",
                        trend: .up,
                        trendValue: "+5%"
                    )
                    MetricPillView(
                        icon: "heart.circle.fill",
                        iconColor: .steel,
                        value: "\(store.dailyMetrics.restingHR)",
                        label: "Resting HR",
                        trend: .down,
                        trendValue: "-2%"
                    )
                }
                .padding(.horizontal, 1)
            }
            .padding(.horizontal, -1)
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5)) {
                appear = true
            }
        }
    }
}

enum TrendDir { case up, down, neutral }

struct MetricPillView: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    let trend: TrendDir
    var trendValue: String = ""
    
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(value)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        if !trendValue.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 9, weight: .bold))
                                Text(trendValue)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(trend == .up ? .success : .danger)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((trend == .up ? Color.success : Color.danger).opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                    
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
        .opacity(appear ? 1 : 0)
        .scaleEffect(appear ? 1 : 0.9)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.6)) {
                appear = true
            }
        }
    }
}

// MARK: - Insights Section

struct InsightsSectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    
    var insights: [Insight] {
        var result: [Insight] = []
        
        // Recovery insight
        if store.readiness.overall < 70 {
            result.append(Insight(
                icon: "bed.double.fill",
                title: "Consider a Rest Day",
                description: "Your recovery is below optimal. A lighter session or rest day could help.",
                color: .steel,
                priority: .high
            ))
        }
        
        // HRV insight
        if store.dailyMetrics.hrv < 40 {
            result.append(Insight(
                icon: "heart.text.square.fill",
                title: "Low HRV Detected",
                description: "Your nervous system is stressed. Focus on sleep and recovery.",
                color: .danger,
                priority: .high
            ))
        }
        
        // Positive insight
        if store.currentStreak >= 7 {
            result.append(Insight(
                icon: "flame.fill",
                title: "\(store.currentStreak)-Day Streak! 🔥",
                description: "You're on fire! Keep up the momentum.",
                color: .ember,
                priority: .medium
            ))
        }
        
        return result
    }
    
    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("INSIGHTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.5)
                
                VStack(spacing: 12) {
                    ForEach(insights) { insight in
                        InsightCard(insight: insight)
                    }
                }
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.6)) {
                    appear = true
                }
            }
        }
    }
}

struct Insight: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color
    let priority: Priority
    
    enum Priority {
        case high, medium, low
    }
}

struct InsightCard: View {
    let insight: Insight
    @State private var appear = false
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(insight.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: insight.icon)
                        .font(.system(size: 20))
                        .foregroundColor(insight.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    
                    Text(insight.description)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            .padding(16)
            .background(Color.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(insight.color.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Activity

struct RecentActivityView: View {
    @EnvironmentObject var store: AppStore
    @State private var appear = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("RECENT WORKOUTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.5)
                
                Spacer()
                
                Button(action: {}) {
                    Text("See All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ember)
                }
            }
            
            VStack(spacing: 12) {
                RecentWorkoutRow(
                    name: "Upper Body Strength",
                    date: "Yesterday",
                    duration: "45 min",
                    icon: "dumbbell.fill",
                    color: .ember
                )
                
                RecentWorkoutRow(
                    name: "HIIT Cardio",
                    date: "2 days ago",
                    duration: "30 min",
                    icon: "bolt.fill",
                    color: .steel
                )
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.7)) {
                appear = true
            }
        }
    }
}

struct RecentWorkoutRow: View {
    let name: String
    let date: String
    let duration: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                
                HStack(spacing: 8) {
                    Text(date)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                    
                    Circle()
                        .fill(Color.textMuted)
                        .frame(width: 3, height: 3)
                    
                    Text(duration)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.success)
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
    }
}
