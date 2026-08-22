import SwiftUI
import UIKit
import HealthKit
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
