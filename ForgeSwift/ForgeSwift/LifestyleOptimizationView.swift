import SwiftUI
import UIKit
import HealthKit
import ForgeCore

struct AIOptimizationContent: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var vm: LifestyleViewModel
    @ObservedObject var locationLogger: LocationMealLogger
    @State private var showsMoreInsights = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expandTransition: AnyTransition {
        reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    var body: some View {
        LazyVStack(spacing: ForgeLayout.sectionGap) {
            TodaysFocusCard(vm: vm)
            ReadinessForecastCard(compact: true)
            LocationQuickLogCard(locationLogger: locationLogger, vm: vm)

            if let stats = vm.healthStats {
                LiveHealthDashboard(stats: stats, trends: vm.weeklyTrends)
            }

            if !vm.aiWorkouts.isEmpty {
                AIWorkoutSuggestionsCard(workouts: vm.aiWorkouts)
            }

            moreInsightsLink

            if showsMoreInsights {
                moreInsights
            }
        }
    }

    private var moreInsightsLink: some View {
        ForgeTextLink(title: "More insights", accent: .vitality, expanded: showsMoreInsights) {
            if reduceMotion {
                showsMoreInsights.toggle()
            } else {
                withForgeMotion(ForgeMotion.smooth) { showsMoreInsights.toggle() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Deeper analysis waits behind the disclosure; every card stays reachable.
    private var moreInsights: some View {
        VStack(spacing: ForgeLayout.sectionGap) {
            MultiArcQOLCard(metrics: vm.metrics)
            QOLTrendCard(history: vm.qolHistory)
            AILifeAnalysisCard(metrics: vm.metrics, analysis: vm.aiLifeAnalysis, isLive: vm.aiInsightsLive)
            AIRecommendationsCard(recommendations: vm.recommendations, store: store)
            OptimizationGoalsCard(vm: vm)

            if let stats = vm.healthStats {
                RecoveryMetricsCard(stats: stats)
            }
        }
        .transition(expandTransition)
    }
}

struct LocationQuickLogCard: View {
    @ObservedObject var locationLogger: LocationMealLogger
    @ObservedObject var vm: LifestyleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Quick Location Log") {
                if locationLogger.isDetectingLocation {
                    ProgressView().controlSize(.mini)
                }
            }

            Text("Detect nearby restaurants and log meals in one tap. Location stays on this iPhone.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()

            ForgeSecondaryButton(
                title: locationLogger.isDetectingLocation ? "Detecting location..." : "Detect Current Location & Log Meal",
                icon: "location.circle.fill",
                accent: .ember
            ) {
                Task { await locationLogger.detectCurrentLocationAndLog() }
            }
            .disabled(locationLogger.isDetectingLocation)

            if let error = locationLogger.errorMessage {
                Text(error)
                    .font(HomeType.body)
                    .foregroundStyle(Color.danger)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .amber)
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
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    Text("Select what you ate. Macros write to Apple Health.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()

                    if items.isEmpty {
                        ForgeEmptyNote(
                            title: "No menu items found",
                            message: "Try Places to browse and log a meal.",
                            systemImage: "fork.knife",
                            tint: .amber
                        )
                        .forgeWell()
                    }

                    ForEach(items) { item in
                        itemRow(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .forgeScreenBackground(accent: .amber)
            .navigationTitle(venue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }

    private func itemRow(_ item: MenuItem) -> some View {
        Button {
            ForgeHaptics.play(.press)
            onLog(item)
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeListRow(
                    icon: "fork.knife",
                    iconColor: .amber,
                    title: item.name,
                    subtitle: "\(item.calories) cal · \(item.protein)g protein"
                )
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.ember)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeWell()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(item.calories) cal, \(item.protein)g protein")
        .accessibilityHint("Logs this meal")
    }
}

struct TodaysFocusCard: View {
    @ObservedObject var vm: LifestyleViewModel

    private var focusArea: (title: String, icon: String, priority: String, action: String, color: Color, gradient: [Color]) {
        guard let stats = vm.healthStats else {
            return ("Start Your Day", "sun.max.fill", "Morning Routine", "Log your first meal", .ember, [.ember, .ember.opacity(0.7)])
        }
        
        // AI decision tree for daily focus
        if stats.hrv < 30 {
            return ("Recovery Focus", "heart.circle.fill", "Critical", "Take an active recovery day", .danger, [.danger, Color(hex: "FF6B6B")])
        }
        
        if stats.sleepHours < 6.5 {
            return ("Sleep Priority", "moon.zzz.fill", "High", "Aim for 8+ hours tonight", Color.aurora, [Color.aurora, Color(hex: "C77DFF")])
        }
        
        if stats.protein < 120 {
            let remaining = Int(180 - stats.protein)
            return ("Protein Deficit", "fork.knife.circle.fill", "High", "Add \(remaining)g protein today", .ember, [.ember, Color.amber])
        }
        
        if stats.steps < 5000 {
            return ("Movement Goal", "figure.walk.circle.fill", "Medium", "Hit 10K steps today", .steel, [.steel, .success])
        }
        
        if stats.water < 6 {
            return ("Hydration Check", "drop.circle.fill", "Medium", "Drink more water", Color.steel, [Color.steel, Color(hex: "00D4FF")])
        }
        
        return ("Peak Performance", "bolt.circle.fill", "Ready", "Crush your workout", .success, [.success, Color(hex: "00FF88")])
    }
    
    /// One token energy per focus. Alert red and the success green are not
    /// status colors here: recovery reads as steel, "ready" as vitality.
    private func focusEnergy(for color: Color) -> Color {
        if color == Color.danger { return HudChrome.miss }
        if color == Color.success { return Color.vitality }
        return color
    }

    var body: some View {
        let area = focusArea
        let energy = focusEnergy(for: area.color)
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            ForgeCardHeader(title: "Today's Focus", tint: .textTertiary) {
                HudVibeChip(label: area.priority, energy: energy)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }

            ForgeAdaptiveStack(spacing: FDS.Spacing.md) {
                ForgeIconWell(systemImage: area.icon, tint: energy, diameter: 44)

                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(area.title)
                        .font(HomeType.sessionTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(ForgeLayout.labelMinScale)
                    Text(area.action)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
            }

            // No destination is wired for the focus yet, so this stays a text
            // link (not a primary). `ForgeTextLink` already fires the press haptic.
            ForgeTextLink(title: "Take Action", accent: energy) { }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPlate(energy: energy)
        .accessibilityElement(children: .contain)
    }
}
