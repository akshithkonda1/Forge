import SwiftUI
import Combine
import Charts
import UIKit
import HealthKit
import WorkoutKit
import ForgeCore

struct AIOptimizationContent: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var vm: LifestyleViewModel
    @ObservedObject var locationLogger: LocationMealLogger

    var body: some View {
        LazyVStack(spacing: 20) {
            LocationQuickLogCard(locationLogger: locationLogger, vm: vm)
            TodaysFocusCard(vm: vm)
            
            // NEW: Real-time HealthKit Dashboard
            if let stats = vm.healthStats {
                LiveHealthDashboard(stats: stats, trends: vm.weeklyTrends)
            }
            
            // NEW: AI Workout Suggestions
            if !vm.aiWorkouts.isEmpty {
                AIWorkoutSuggestionsCard(workouts: vm.aiWorkouts)
            }
            
            MultiArcQOLCard(metrics: vm.metrics)
            QOLTrendCard(history: vm.qolHistory)
            AILifeAnalysisCard(metrics: vm.metrics, analysis: vm.aiLifeAnalysis, isLive: vm.aiInsightsLive)
            AIRecommendationsCard(recommendations: vm.recommendations, store: store)
            OptimizationGoalsCard(vm: vm)
            
            // NEW: Recovery & Performance
            if let stats = vm.healthStats {
                RecoveryMetricsCard(stats: stats)
            }
        }
    }
}

struct LocationQuickLogCard: View {
    @ObservedObject var locationLogger: LocationMealLogger
    @ObservedObject var vm: LifestyleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.ember)
                Text("Quick Location Log")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
            }

            Text("Detect nearby restaurants and log meals in one tap. Location stays on this iPhone.")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(4)

            Button {
                Task { await locationLogger.detectCurrentLocationAndLog() }
            } label: {
                HStack {
                    if locationLogger.isDetectingLocation {
                        ProgressView().tint(.white)
                        Text("Detecting location...")
                    } else {
                        Image(systemName: "location.circle.fill")
                        Text("Detect Current Location & Log Meal")
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient.emberGradient)
                .cornerRadius(14)
            }
            .disabled(locationLogger.isDetectingLocation)

            if let error = locationLogger.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.danger)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

struct LocationMealConfirmationSheet: View {
    let venue: String
    let items: [MenuItem]
    let onLog: (MenuItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Select what you ate. Macros write to Apple Health.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)

                    ForEach(items) { item in
                        Button { onLog(item) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("\(item.calories) cal · \(item.protein)g protein")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.ember)
                            }
                            .padding(14)
                            .background(Color.surfaceElevated)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.background)
            .navigationTitle(venue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }
}

struct TodaysFocusCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false
    
    private var focusArea: (title: String, icon: String, priority: String, action: String, color: Color, gradient: [Color]) {
        guard let stats = vm.healthStats else {
            return ("Start Your Day", "sun.max.fill", "Morning Routine", "Log your first meal", .ember, [.ember, .ember.opacity(0.7)])
        }
        
        // AI decision tree for daily focus
        if stats.hrv < 30 {
            return ("Recovery Focus", "heart.circle.fill", "Critical", "Take an active recovery day", .danger, [.danger, Color(hex: "FF6B6B")])
        }
        
        if stats.sleepHours < 6.5 {
            return ("Sleep Priority", "moon.zzz.fill", "High", "Aim for 8+ hours tonight", Color(hex: "A855F7"), [Color(hex: "A855F7"), Color(hex: "C77DFF")])
        }
        
        if stats.protein < 120 {
            let remaining = Int(180 - stats.protein)
            return ("Protein Deficit", "fork.knife.circle.fill", "High", "Add \(remaining)g protein today", .ember, [.ember, Color(hex: "FFB84D")])
        }
        
        if stats.steps < 5000 {
            return ("Movement Goal", "figure.walk.circle.fill", "Medium", "Hit 10K steps today", .steel, [.steel, .success])
        }
        
        if stats.water < 6 {
            return ("Hydration Check", "drop.circle.fill", "Medium", "Drink more water", Color(hex: "4A9EFF"), [Color(hex: "4A9EFF"), Color(hex: "00D4FF")])
        }
        
        return ("Peak Performance", "bolt.circle.fill", "Ready", "Crush your workout", .success, [.success, Color(hex: "00FF88")])
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated gradient header
            ZStack(alignment: .topLeading) {
                // Background gradient
                LinearGradient(
                    colors: focusArea.gradient + [focusArea.gradient.first!.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // Animated particles
                TimelineView(.animation(minimumInterval: 2)) { timeline in
                    Canvas { context, size in
                        let now = timeline.date.timeIntervalSinceReferenceDate
                        for i in 0..<8 {
                            let x = (CGFloat(i) / 8.0) * size.width + CGFloat(sin(now * 0.5 + Double(i))) * 30
                            let y = (CGFloat(i % 3) / 3.0) * size.height + CGFloat(cos(now * 0.3 + Double(i))) * 20
                            let opacity = 0.1 + abs(sin(now + Double(i))) * 0.2
                            
                            context.opacity = opacity
                            context.fill(
                                Circle().path(in: CGRect(x: x, y: y, width: 4, height: 4)),
                                with: .color(.white)
                            )
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // Priority badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                            .shadow(color: .white.opacity(0.6), radius: 4)
                        Text(focusArea.priority.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.2))
                    .cornerRadius(20)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                    
                    // Main content
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 70, height: 70)
                            Circle()
                                .fill(.white.opacity(0.1))
                                .frame(width: 70, height: 70)
                                .blur(radius: 8)
                            
                            Image(systemName: focusArea.icon)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.2), radius: 4)
                        }
                        .scaleEffect(appeared ? 1 : 0.7)
                        .animation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.1), value: appeared)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TODAY'S FOCUS")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.white.opacity(0.8))
                                .tracking(2)
                            
                            Text(focusArea.title)
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.2), radius: 4)
                            
                            Text(focusArea.action)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .padding(24)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            
            // Quick action button
            Button {
                // Navigate to relevant section
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Take Action")
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(focusArea.color)
                .padding(18)
                .background(focusArea.color.opacity(0.1))
                .cornerRadius(16)
            }
            .padding(16)
            .background(Color.surface)
        }
        .background(Color.surface)
        .cornerRadius(24)
        .shadow(color: focusArea.color.opacity(0.2), radius: 20, y: 10)
        .onAppear { appeared = true }
    }
}

struct LiveHealthDashboard: View {
    let stats: DailyHealthStats
    let trends: [WeeklyHealthTrend]
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with live indicator
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.success.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [.success, .ember], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Live Health Data")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        // Pulsing live indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.success)
                                .frame(width: 6, height: 6)
                                .overlay(
                                    Circle()
                                        .stroke(Color.success.opacity(0.3), lineWidth: 2)
                                        .scaleEffect(appeared ? 1.5 : 1)
                                        .opacity(appeared ? 0 : 1)
                                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: appeared)
                                )
                            Text("LIVE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.success)
                                .tracking(1)
                        }
                    }
                    Text("Powered by Apple Health")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.bottom, 4)
            
            // Today's Key Metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                HealthMetricTile(
                    icon: "figure.walk",
                    label: "Steps",
                    value: "\(stats.steps.formatted())",
                    target: "10,000",
                    progress: Double(stats.steps) / 10000.0,
                    color: .steel,
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "flame.fill",
                    label: "Active Cal",
                    value: "\(stats.activeCalories)",
                    target: "600",
                    progress: Double(stats.activeCalories) / 600.0,
                    color: .ember,
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "moon.zzz.fill",
                    label: "Sleep",
                    value: String(format: "%.1fh", stats.sleepHours),
                    target: "8h",
                    progress: stats.sleepHours / 8.0,
                    color: Color(hex: "A855F7"),
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: "\(Int(stats.hrv))",
                    target: "50+",
                    progress: stats.hrv / 50.0,
                    color: .success,
                    appeared: appeared
                )

                // Cardio fitness — surfaced from HealthKit, previously unused
                if stats.vo2Max > 0 {
                    HealthMetricTile(
                        icon: "lungs.fill",
                        label: "VO₂ Max",
                        value: String(format: "%.0f", stats.vo2Max),
                        target: "50",
                        progress: stats.vo2Max / 50.0,
                        color: Color(hex: "FF6B9D"),
                        appeared: appeared
                    )
                }

                if stats.exerciseMinutes > 0 {
                    HealthMetricTile(
                        icon: "figure.run",
                        label: "Exercise",
                        value: "\(Int(stats.exerciseMinutes))m",
                        target: "30m",
                        progress: stats.exerciseMinutes / 30.0,
                        color: Color(hex: "FFB84D"),
                        appeared: appeared
                    )
                }
            }

            // Weekly Trend Chart (Swift Charts — interactive, multi-metric)
            if !trends.isEmpty {
                WeeklyTrendChart(trends: trends)
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(LinearGradient(
                    colors: [Color.success.opacity(0.3), Color.ember.opacity(0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

private enum TrendMetric: String, CaseIterable, Identifiable {
    case steps = "Steps"
    case activeCalories = "Active"
    case sleep = "Sleep"
    case hrv = "HRV"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .steps:          return .steel
        case .activeCalories: return .ember
        case .sleep:          return Color(hex: "A855F7")
        case .hrv:            return .success
        }
    }

    func value(_ t: WeeklyHealthTrend) -> Double {
        switch self {
        case .steps:          return Double(t.steps)
        case .activeCalories: return Double(t.activeCalories)
        case .sleep:          return t.sleepHours
        case .hrv:            return t.avgHRV
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .steps:          return Int(v).formatted()
        case .activeCalories: return "\(Int(v)) cal"
        case .sleep:          return String(format: "%.1f h", v)
        case .hrv:            return "\(Int(v)) ms"
        }
    }
}

/// Interactive 7-day chart replacing the old steps-only sparkline. Toggles between
/// Steps / Active Cal / Sleep / HRV and supports tap-to-read on any day.
struct WeeklyTrendChart: View {
    let trends: [WeeklyHealthTrend]
    @State private var metric: TrendMetric = .steps
    @State private var selectedDate: Date?

    private var selectedTrend: WeeklyHealthTrend? {
        guard let selectedDate else { return nil }
        return trends.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("7-Day Trends")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                if let t = selectedTrend {
                    Text("\(t.date.formatted(.dateTime.weekday(.abbreviated))) · \(metric.format(metric.value(t)))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(metric.color)
                        .transition(.opacity)
                }
            }

            Picker("Metric", selection: $metric) {
                ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Chart(trends) { t in
                BarMark(
                    x: .value("Day", t.date, unit: .day),
                    y: .value(metric.rawValue, metric.value(t))
                )
                .foregroundStyle(metric.color.gradient)
                .cornerRadius(5)
                .opacity(selectedTrend == nil || selectedTrend?.id == t.id ? 1 : 0.35)
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .frame(height: 150)
            .animation(.easeInOut(duration: 0.25), value: metric)
        }
        .padding(.top, 8)
    }
}

struct HealthMetricTile: View {
    let icon: String
    let label: String
    let value: String
    let target: String
    let progress: Double
    let color: Color
    let appeared: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("/ \(target)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Spacer()
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.borderColor.opacity(0.3))
                    Capsule()
                        .fill(color)
                        .frame(width: appeared ? geo.size.width * CGFloat(min(progress, 1.0)) : 0)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: appeared)
                }
            }
            .frame(height: 4)
        }
        .padding(14)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

struct AIWorkoutSuggestionsCard: View {
    let workouts: [AIWorkoutSuggestion]
    @State private var appeared = false
    @State private var selectedWorkout: CustomWorkoutPlan?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.ember)
                Text("AI Workout Suggestions")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(workouts.count) ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(8)
            }
            
            VStack(spacing: 12) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { i, suggestion in
                    AIWorkoutCard(suggestion: suggestion)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(Double(i) * 0.1), value: appeared)
                        .onTapGesture {
                            selectedWorkout = suggestion.workout
                        }
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
        }
    }
}

struct AIWorkoutCard: View {
    let suggestion: AIWorkoutSuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ember.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(LinearGradient.emberGradient)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 8) {
                        Label("\(suggestion.workout.duration) min", systemImage: "clock.fill")
                        Label("\(suggestion.workout.exercises.count) exercises", systemImage: "list.bullet")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.ember)
            }
            
            Divider().background(Color.borderColor.opacity(0.4))
            
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(.ember)
                Text(suggestion.reason)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.ember.opacity(0.2), lineWidth: 1)
        )
    }
}

struct RecoveryMetricsCard: View {
    let stats: DailyHealthStats
    @State private var appeared = false
    
    var recoveryScore: Int {
        var score = 0
        
        // HRV component (40% weight)
        let hrvScore = min(Int(stats.hrv * 1.5), 100)
        score += Int(Double(hrvScore) * 0.4)
        
        // Resting HR component (30% weight)
        let hrScore = stats.restingHeartRate > 0 ? max(100 - Int((stats.restingHeartRate - 60) * 2), 0) : 70
        score += Int(Double(hrScore) * 0.3)
        
        // Sleep component (30% weight)
        let sleepScore = Int((stats.sleepHours / 8.0) * 100)
        score += Int(Double(sleepScore) * 0.3)
        
        return min(score, 100)
    }
    
    var recoveryStatus: (label: String, color: Color) {
        switch recoveryScore {
        case 80...: return ("Excellent", .success)
        case 60..<80: return ("Good", .steel)
        case 40..<60: return ("Moderate", .warning)
        default: return ("Low", .danger)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(recoveryStatus.color.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(recoveryStatus.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recovery Status")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(recoveryStatus.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(recoveryStatus.color)
                }
                Spacer()
                
                // Recovery score ring
                ZStack {
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), lineWidth: 8)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: appeared ? CGFloat(recoveryScore) / 100 : 0)
                        .stroke(recoveryStatus.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.2), value: appeared)
                    
                    Text("\(recoveryScore)")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.textPrimary)
                }
            }
            .padding(.bottom, 20)
            
            // Recovery metrics grid
            VStack(spacing: 12) {
                RecoveryMetricRow(
                    icon: "waveform.path.ecg",
                    label: "Heart Rate Variability",
                    value: "\(Int(stats.hrv)) ms",
                    status: stats.hrv > 50 ? "Optimal" : stats.hrv > 30 ? "Good" : "Low",
                    color: stats.hrv > 50 ? .success : stats.hrv > 30 ? .warning : .danger
                )
                
                RecoveryMetricRow(
                    icon: "heart.fill",
                    label: "Resting Heart Rate",
                    value: "\(Int(stats.restingHeartRate)) bpm",
                    status: stats.restingHeartRate < 60 ? "Excellent" : stats.restingHeartRate < 70 ? "Good" : "Elevated",
                    color: stats.restingHeartRate < 60 ? .success : stats.restingHeartRate < 70 ? .steel : .warning
                )
                
                RecoveryMetricRow(
                    icon: "bed.double.fill",
                    label: "Sleep Duration",
                    value: String(format: "%.1f hours", stats.sleepHours),
                    status: stats.sleepHours >= 8 ? "Optimal" : stats.sleepHours >= 7 ? "Good" : "Low",
                    color: stats.sleepHours >= 8 ? .success : stats.sleepHours >= 7 ? .steel : .warning
                )
            }
            
            Divider().background(Color.borderColor.opacity(0.4)).padding(.vertical, 16)
            
            // Training readiness
            HStack(spacing: 12) {
                Image(systemName: recoveryScore > 70 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(recoveryScore > 70 ? .success : .warning)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(recoveryScore > 70 ? "Ready to Train" : "Consider Active Recovery")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(recoveryScore > 70 
                         ? "Your body is primed for a hard session"
                         : "Focus on mobility, stretching, or light cardio")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(3)
                }
            }
            .padding(14)
            .background(recoveryStatus.color.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(recoveryStatus.color.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct RecoveryMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            
            Spacer()
            
            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(color.opacity(0.12))
                .cornerRadius(8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

struct WorkoutDetailSheet: View {
    let workout: CustomWorkoutPlan
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workout.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        HStack(spacing: 16) {
                            StatPill(icon: "clock.fill", value: "\(workout.duration) min", color: .steel)
                            StatPill(icon: "flame.fill", value: "~\(workout.caloriesBurn) cal", color: .ember)
                            StatPill(icon: "list.bullet", value: "\(workout.exercises.count) exercises", color: .success)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Exercise list
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Exercises")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 20)
                        
                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, exercise in
                            ExerciseRow(index: i + 1, exercise: exercise)
                                .padding(.horizontal, 20)
                        }
                    }
                    
                    // Start workout button
                    Button {
                        // Integration with WorkoutKit would go here
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Start Workout")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.emberGradient)
                        .cornerRadius(16)
                        .shadow(color: Color.ember.opacity(0.4), radius: 12, y: 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .padding(.vertical, 24)
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }
}

struct ExerciseRow: View {
    let index: Int
    let exercise: WorkoutExercise
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.12)).frame(width: 40, height: 40)
                Text("\(index)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.ember)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 8) {
                    Text("\(exercise.sets) sets")
                    Text("·")
                    Text("\(exercise.reps) reps")
                    Text("·")
                    Text("\(exercise.restSeconds)s rest")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            Text(exercise.muscleGroup.rawValue.capitalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.surfaceElevated)
                .cornerRadius(6)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
    }
}

struct MultiArcQOLCard: View {
    let metrics: LifestyleMetrics
    @State private var appeared = false

    private let arcs: [(label: String, kp: KeyPath<LifestyleMetrics, Int>, color: Color, radius: CGFloat)] = [
        ("Physical",  \.physicalHealth,  .success,                  96),
        ("Mental",    \.mentalWellbeing, .steel,                    78),
        ("Energy",    \.energyLevels,    .ember,                    60),
        ("Sleep",     \.sleepQuality,    Color(hex: "A855F7"),      42),
        ("Nutrition", \.nutritionScore,  Color(hex: "FFB84D"),      24),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Section label
            HStack {
                Text("QUALITY OF LIFE")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(2.5)
                Spacer()
                Text("All dimensions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
            }
            .padding(.bottom, 28)

            // Arc visualisation
            ZStack {
                // Background arcs (tracks)
                ForEach(Array(arcs.enumerated()), id: \.offset) { i, arc in
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                }

                // Progress arcs
                ForEach(Array(arcs.enumerated()), id: \.offset) { i, arc in
                    let value = metrics[keyPath: arc.kp]
                    let progress = appeared ? CGFloat(value) / 100 : 0

                    // Glow
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(arc.color.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 6)

                    // Main arc
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(arc.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: arc.color.opacity(0.4), radius: 6)
                        .animation(.spring(response: 1.4, dampingFraction: 0.68).delay(0.3 + Double(i) * 0.12), value: appeared)
                }

                // Center score
                VStack(spacing: 3) {
                    Text("\(metrics.qualityOfLifeScore)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("QOL Score")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1)
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)

            // Legend grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    let val = metrics[keyPath: arc.kp]
                    ArcLegendItem(label: arc.label, value: val, color: arc.color)
                }
            }
        }
        .padding(24)
        .background(Color.surface)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

struct ArcLegendItem: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 3)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

struct AILifeAnalysisCard: View {
    let metrics: LifestyleMetrics
    var analysis: String? = nil
    var isLive: Bool = false
    @State private var appeared = false
    @State private var expanded = false

    private var rows: [(icon: String, label: String, current: String, optimal: String, status: InsightStatus)] {[
        ("moon.zzz.fill", "Sleep", String(format: "%.1fh avg", metrics.sleepAverage), String(format: "%.0fh target", metrics.sleepTarget), metrics.sleepAverage >= metrics.sleepTarget ? .excellent : metrics.sleepAverage >= metrics.sleepTarget * 0.9 ? .good : .warning),
        ("fork.knife", "Nutrition", "\(Int(metrics.nutritionQuality * 100))% whole foods", "85%+", metrics.nutritionQuality >= 0.85 ? .excellent : metrics.nutritionQuality >= 0.75 ? .good : .warning),
        ("figure.walk", "Movement", "\(metrics.dailySteps.formatted()) steps", "10,000 steps", metrics.dailySteps >= 10000 ? .excellent : metrics.dailySteps >= 8000 ? .good : .warning),
        ("brain.fill", "Stress", metrics.stressLevel.rawValue, "Low", metrics.stressLevel == .low ? .excellent : metrics.stressLevel == .medium ? .warning : .poor),
    ]}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LinearGradient.ember)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("AI Life Analysis")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if analysis != nil { liveBadge }
                    }
                    Text("Behavioral pattern analysis")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.bottom, 20)

            // Insight rows with left accent bar
            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    AnalysisInsightRow(
                        icon: row.icon, label: row.label,
                        current: row.current, optimal: row.optimal, status: row.status
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(0.1 + Double(i) * 0.07), value: appeared)
                }
            }
            .padding(.bottom, 20)

            // Full analysis CTA
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 14))
                    Text(expanded ? "Hide Full Analysis" : "View Full Analysis").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundColor(.ember)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(12)
            }

            if expanded {
                fullAnalysisSection
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }

    private var liveBadge: some View {
        Text(isLive ? "LIVE" : "ARIA")
            .font(.system(size: 8, weight: .black))
            .tracking(0.5)
            .foregroundColor(.ember)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.ember.opacity(0.12))
            .cornerRadius(5)
    }

    @ViewBuilder
    private var fullAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 13)).foregroundColor(.ember)
                Text(isLive ? "ARIA's analysis" : "Summary")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            if let analysis {
                Text(analysis)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Connect ARIA to unlock a personalized breakdown of how your sleep, nutrition, movement, and stress are interacting today.")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

struct AnalysisInsightRow: View {
    let icon: String
    let label: String
    let current: String
    let optimal: String
    let status: InsightStatus

    var body: some View {
        HStack(spacing: 14) {
            // Colored left accent + icon
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(status.color)
                    .frame(width: 3, height: 40)
                    .padding(.trailing, 10)

                ZStack {
                    Circle().fill(status.color.opacity(0.12)).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(status.color)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 5) {
                    Text(current)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(.textMuted)
                    Text(optimal)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            // Status dot with glow
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
                .shadow(color: status.color.opacity(0.6), radius: 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

struct AIRecommendationsCard: View {
    let recommendations: [AIRecommendation]
    @ObservedObject var store: AppStore
    @State private var appeared = false

    private var ariaPrompt: String {
        if let top = recommendations.first {
            return "Based on my lifestyle data, help me act on this: \(top.title). \(top.description)"
        }
        return "Review my lifestyle optimization metrics and suggest one high-impact change for today."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.ember)
                Text("AI Recommendations")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(recommendations.count) active")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(8)
            }

            Button {
                store.openChat(with: ariaPrompt)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Ask ARIA to optimize")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.ember)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            if recommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44)).foregroundColor(.success.opacity(0.6))
                    Text("You're doing great! No new recommendations.")
                        .font(.system(size: 14)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { i, rec in
                        RecommendationCard(recommendation: rec)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(0.05 + Double(i) * 0.08), value: appeared)
                    }
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct RecommendationCard: View {
    let recommendation: AIRecommendation
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 0) {
            // Glowing left border — the signature visual
            RoundedRectangle(cornerRadius: 3)
                .fill(recommendation.impact.color)
                .frame(width: 4)
                .shadow(color: recommendation.impact.color.opacity(0.7), radius: 6)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { expanded.toggle() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: recommendation.category.icon)
                                    .font(.system(size: 11))
                                    .foregroundColor(recommendation.impact.color)
                                Text(recommendation.category.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(recommendation.impact.color)
                                    .tracking(1.5)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text(recommendation.impact.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(recommendation.impact.color)
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.textMuted)
                            }
                        }

                        Text(recommendation.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if expanded {
                            Text(recommendation.description)
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                                .lineSpacing(4)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
        }
        .background(recommendation.impact.color.opacity(0.05))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(recommendation.impact.color.opacity(0.18), lineWidth: 1)
        )
    }
}

struct OptimizationGoalsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false

    // Derived from live HealthKit data (was a hardcoded array).
    private var goals: [(title: String, progress: Double, current: String, target: String, color: Color)] {
        let m = vm.metrics
        let protein = Int(vm.healthStats?.protein ?? 0)
        let mindfulWeek = vm.mindfulMinutesWeek
        let stressProgress: Double = {
            switch m.stressLevel {
            case .low: return 1.0
            case .medium: return 0.6
            case .high: return 0.3
            }
        }()
        return [
            ("Sleep → 8h", min(m.sleepAverage / 8.0, 1.0),
             String(format: "%.1fh avg", m.sleepAverage), "8h", Color(hex: "A855F7")),
            ("Lower stress", stressProgress,
             m.stressLevel.rawValue, "Low", .warning),
            ("Daily protein 180g", min(Double(protein) / 180.0, 1.0),
             "\(protein)g", "180g", .ember),
            ("Mindfulness 70 min/wk", min(Double(mindfulWeek) / 70.0, 1.0),
             "\(mindfulWeek) min", "70 min", .steel),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Optimization Goals")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            VStack(spacing: 12) {
                ForEach(Array(goals.enumerated()), id: \.offset) { i, goal in
                    GoalProgressItem(
                        title: goal.title, progress: goal.progress,
                        current: goal.current, target: goal.target,
                        color: goal.color, appeared: appeared, index: i
                    )
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct GoalProgressItem: View {
    let title: String
    let progress: Double
    let current: String
    let target: String
    let color: Color
    let appeared: Bool
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
            }
            HStack(spacing: 6) {
                Text(current)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10)).foregroundColor(.textMuted)
                Text(target)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }
            // Responsive animated progress bar (fixed hardcoded-points bug)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.borderColor.opacity(0.3))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: appeared ? geo.size.width * CGFloat(progress) : 0)
                        .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.4 + Double(index) * 0.1), value: appeared)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 1))
    }
}
