import SwiftUI
import Combine
import UIKit
import ForgeCore

struct LifestyleView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var vm = LifestyleViewModel.shared
    @StateObject private var locationLogger = LocationMealLogger()
    @State private var selectedSegment: LifestyleSegment = .nutrition
    @State private var showInsights = false
    @State private var reconnectingHK = false
    @State private var showLifestyleInterview = false
    @Namespace private var segmentNS

    var body: some View {
        ZStack {
            // Background — subtle radial haze tuned to selected segment
            LifestyleBackground(segment: selectedSegment)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LifestyleHeaderView(showInsights: $showInsights, metrics: vm.metrics)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 16)

                if !store.healthKitLive {
                    Button {
                        reconnectingHK = true
                        Task {
                            await store.reconnectHealthKit()
                            reconnectingHK = false
                            FDS.notificationHaptic(store.healthKitLive ? .success : .warning)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(Color.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple Health offline")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text(store.isHealthKitPulling
                                    ? "Pulling…"
                                    : (reconnectingHK ? "Reconnecting…" : "Tap to reconnect for live nutrition & recovery"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textTertiary)
                            }
                            Spacer()
                            if reconnectingHK {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(Color.ember)
                            }
                        }
                        .padding(14)
                        .forgeGlassCard(cornerRadius: 14, accent: .warning)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                SegmentedPillControl(selected: $selectedSegment, namespace: segmentNS)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        segmentContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await vm.refresh()
                    await vm.refreshAIInsights(store: store, allowNetwork: true)
                }
            }

            if showInsights {
                AIInsightsModal(
                    isPresented: $showInsights,
                    recommendations: vm.recommendations,
                    metrics: vm.metrics,
                    stats: vm.healthStats,
                    summary: vm.aiLifeAnalysis,
                    isLive: vm.aiInsightsLive
                )
                    .zIndex(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showLifestyleInterview {
                LifestyleInterviewOverlay {
                    showLifestyleInterview = false
                    Task { await vm.refresh() }
                }
                .zIndex(20)
                .transition(.opacity)
            }

        }
        .animation(.easeInOut(duration: 0.3), value: showInsights)
        .task {
            vm.applyPersonalization(
                store.userProfile,
                dailyDeepSleepMinutes: store.dailyMetrics.deepSleep,
                readinessStressLevel: store.readiness.stressLevel
            )
            await vm.load()
            await vm.refreshAIInsights(store: store, allowNetwork: false)
        }
        .onAppear {
            consumePendingLifestyleSegment()
            if !QualityOfLifeLivingStore.hasCompletedInterview() {
                showLifestyleInterview = true
            }
        }
        .onChange(of: store.pendingLifestyleSegment) { _, _ in
            consumePendingLifestyleSegment()
        }
        .onChange(of: selectedSegment) { _, segment in
            Task { await handleSegmentWork(segment) }
        }
        .onChange(of: showInsights) { _, open in
            if open {
                Task { await vm.refreshAIInsights(store: store, allowNetwork: true) }
            }
        }
        .sheet(isPresented: $locationLogger.showConfirmation) {
            if let venue = locationLogger.detectedVenue {
                LocationMealConfirmationSheet(
                    venue: venue,
                    items: locationLogger.detectedItems,
                    onLog: { item in locationLogger.logSelectedMeal(item, to: vm) },
                    onDismiss: { locationLogger.showConfirmation = false }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .alert("Lifestyle", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        ), presenting: vm.error) { _ in
            Button("OK") { vm.error = nil }
        } message: { err in
            let raw = err.localizedDescription
            let copy = raw.lowercased().contains("kclerror")
                ? "Still finding your location. Try Places again in a moment."
                : raw
            Text(copy)
        }
    }

    private func consumePendingLifestyleSegment() {
        guard let raw = store.pendingLifestyleSegment?.lowercased() else { return }
        store.pendingLifestyleSegment = nil
        let mapped: LifestyleSegment? = {
            switch raw {
            case "nutrition": return .nutrition
            case "restaurants", "meals", "food", "places", "map": return .restaurants
            case "wellbeing", "wellness": return .wellbeing
            case "ai", "aioptimization", "optimize": return .aiOptimization
            default: return LifestyleSegment(rawValue: Int(raw) ?? -1)
            }
        }()
        if let mapped {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
                selectedSegment = mapped
            }
            Task { await handleSegmentWork(mapped) }
        }
    }

    @MainActor
    private func handleSegmentWork(_ segment: LifestyleSegment) async {
        switch segment {
        case .wellbeing:
            LifestyleLocationStore.shared.stopTracking()
            await vm.loadWellbeingExtrasIfNeeded()
        case .aiOptimization:
            LifestyleLocationStore.shared.stopTracking()
            await vm.loadWorkoutsIfNeeded()
        case .restaurants:
            let locator = LifestyleLocationStore.shared
            if locator.canAsk { _ = await locator.requestAccess() }
            locator.startTracking()
        default:
            LifestyleLocationStore.shared.stopTracking()
        }
    }

    @ViewBuilder
    private var segmentContent: some View {
        if store.dataLoadState == .loading && !store.hasMeaningfulLifeSignal {
            ForgeSkeletonBlock(height: 88, cornerRadius: 16)
            ForgeSkeletonBlock(height: 180, cornerRadius: 16)
            ForgeSkeletonBlock(height: 140, cornerRadius: 16)
        } else if !store.healthKitLive && !store.hasMeaningfulLifeSignal {
            ForgeEmptyStateCard(
                icon: "heart.text.square.fill",
                title: "Connect Apple Health to unlock lifestyle",
                message: "Nutrition, recovery, and today’s focus come from your live metrics — not a blank chart.",
                accent: .ember,
                cta: "Reconnect Apple Health",
                action: { Task { await store.reconnectHealthKit() } }
            )
        } else {
            switch selectedSegment {
            case .aiOptimization: AIOptimizationContent(vm: vm, locationLogger: locationLogger)
            case .homeCooking:    HomeCookingView(vm: vm)
            case .restaurants:    LifestylePlacesView(vm: vm, locationLogger: locationLogger)
            case .nutrition:      DailyNutritionView(vm: vm)
            case .wellbeing:      WellbeingView(vm: vm)
            }
        }
    }
}

struct LifestyleBackground: View {
    let segment: LifestyleSegment

    private var accentColor: Color {
        switch segment {
        case .aiOptimization: return .ember
        case .homeCooking:    return Color(hex: "7C5CFF")
        case .restaurants:    return .steel
        case .nutrition:      return Color(hex: "FFB84D")
        case .wellbeing:      return .success
        }
    }

    var body: some View {
        ZStack {
            Color.background
            RadialGradient(
                colors: [accentColor.opacity(0.12), accentColor.opacity(0.04), .clear],
                center: UnitPoint(x: 0.12, y: -0.04),
                startRadius: 8,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.steel.opacity(0.06), .clear],
                center: UnitPoint(x: 0.92, y: 0.90),
                startRadius: 8,
                endRadius: 320
            )
        }
        .animation(.easeInOut(duration: 0.35), value: segment)
    }
}

struct LifestyleHeaderView: View {
    @EnvironmentObject var store: AppStore
    @Binding var showInsights: Bool
    let metrics: LifestyleMetrics
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Lifestyle")
                    .font(FDS.TypeScale.pageTitle())
                    .foregroundColor(.textPrimary)
                Text("How you eat, move, and live")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // QOL score chip + AI button
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 3)
                        .frame(width: 46, height: 46)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(100, max(0, metrics.qualityOfLifeScore))) / 100)
                        .stroke(Color.vitality, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 46, height: 46)
                        .animation(FDS.Spring.sweep, value: metrics.qualityOfLifeScore)
                    VStack(spacing: 0) {
                        Text("\(metrics.qualityOfLifeScore)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.textPrimary)
                    }
                }
                .accessibilityLabel("Quality of life \(metrics.qualityOfLifeScore)")

                ForgeIconButton(
                    systemImage: "drop.fill",
                    accent: Color(hex: "4A9EFF"),
                    accessibilityLabel: "Open hydration"
                ) {
                    store.openHydration()
                }

                Button {
                    FDS.haptic(.light)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { showInsights = true }
                } label: {
                    ARIAIdentityMark(state: .idle, mood: .energized, size: 40, amplitude: 0.24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ARIA insights")
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) { appeared = true } }
    }
}

struct SegmentedPillControl: View {
    @Binding var selected: LifestyleSegment
    let namespace: Namespace.ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LifestyleSegment.allCases, id: \.self) { seg in
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) { selected = seg }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: seg.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(seg.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(selected == seg ? .white : .textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background {
                            if selected == seg {
                                Capsule()
                                    .fill(FDS.Gradient.ember)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                                    .shadow(color: Color.ember.opacity(0.45), radius: 10, y: 4)
                            } else {
                                Capsule()
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }
}

#Preview {
    LifestyleView()
        .environmentObject(AppStore())
}
