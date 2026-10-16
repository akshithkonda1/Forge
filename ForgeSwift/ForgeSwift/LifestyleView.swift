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
    /// Presentation only: the segment rail shows bar chrome once it pins.
    @State private var segmentPinned = false
    /// Presentation only: height of the header block above the rail, which
    /// is the scroll distance at which the rail pins.
    @State private var headerBlockHeight: CGFloat = 0
    @Namespace private var segmentNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Zero-height marker at the rail's resting position, so a segment change
    /// can bring the rail back to the top of the screen.
    private static let railAnchorID = "lifestyle-segment-rail"

    var body: some View {
        ZStack {
            // Background — token wash tuned to the selected segment (spec §14)
            LifestyleBackground(segment: selectedSegment)
                .ignoresSafeArea()

            scrollBody

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
                    .forgeTransition(.move(edge: .bottom).combined(with: .opacity))
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: showInsights)
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
        let mapped = LifestyleDeepLink.segment(from: raw)
        if let mapped {
            if reduceMotion {
                selectedSegment = mapped
            } else {
                withAnimation(ForgeMotion.smooth) {
                    selectedSegment = mapped
                }
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
        case .lifetime:
            LifestyleLocationStore.shared.stopTracking()
            await vm.loadGlucoseIfNeeded(force: true)
        case .restaurants:
            let locator = LifestyleLocationStore.shared
            if locator.canAsk { _ = await locator.requestAccess() }
            locator.startTracking()
        default:
            LifestyleLocationStore.shared.stopTracking()
        }
    }

    // MARK: - Scaffold (spec §2.3 / §14)
    //
    // One scroll: header block, then a pinned segment rail as a section header,
    // then the segment's cards at Home's 16 pt rhythm. The tab bar is already a
    // safeAreaInset (ContentView), so there is no legacy top/bottom offset.

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    headerBlock
                    Color.clear
                        .frame(height: 0)
                        .id(Self.railAnchorID)
                        .accessibilityHidden(true)
                    Section {
                        segmentSection
                    } header: {
                        segmentRail
                    }
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > headerBlockHeight
            } action: { _, pinned in
                if pinned != segmentPinned { segmentPinned = pinned }
            }
            .onChange(of: selectedSegment) { _, _ in
                // Presentation only: a reader deep in one segment lands at the
                // top of the next one, with the rail where they left it.
                guard segmentPinned else { return }
                if reduceMotion {
                    proxy.scrollTo(Self.railAnchorID, anchor: .top)
                } else {
                    withForgeMotion(ForgeMotion.smooth) {
                        proxy.scrollTo(Self.railAnchorID, anchor: .top)
                    }
                }
            }
            .refreshable {
                await vm.refresh()
                await vm.refreshAIInsights(store: store, allowNetwork: true)
            }
        }
    }

    /// Page header, QoL chip and the offline banner. Everything above the rail.
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            LifestyleHeaderView(showInsights: $showInsights, metrics: vm.metrics)
            if !store.healthKitLive {
                offlineBanner
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ForgeLayout.screenInset)
        // The rail carries its own 8 pt of vertical padding, so 8 more here
        // keeps the gap to the rail's capsules at the 16 pt section rhythm.
        .padding(.bottom, ForgeLayout.sectionGap - FDS.Spacing.sm)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            headerBlockHeight = height
        }
    }

    private var offlineBannerDetail: String {
        store.isHealthKitPulling
            ? "Pulling…"
            : (reconnectingHK ? "Reconnecting…" : "Tap to reconnect for live nutrition & recovery")
    }

    /// Connection-needed banner: compact warning-tinted card, agenda-row anatomy.
    private var offlineBanner: some View {
        Button {
            reconnectingHK = true
            Task {
                await store.reconnectHealthKit()
                reconnectingHK = false
                ForgeHaptics.play(store.healthKitLive ? .success : .warning)
            }
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "heart.text.square.fill", tint: .warning)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("Apple Health offline")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(offlineBannerDetail)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .layoutPriority(1)
                Spacer(minLength: FDS.Spacing.xs)
                if reconnectingHK {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: ForgeUX.icon, weight: .semibold))
                        .foregroundStyle(Color.ember)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .forgeContentCard(tint: .warning, padding: ForgeLayout.compactCardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Tap to reconnect for live nutrition & recovery")
    }

    /// The one pinned element: the segment rail. Bar chrome only once pinned,
    /// so at rest it sits on the segment wash like Home's mini header.
    private var segmentRail: some View {
        SegmentedPillControl(selected: $selectedSegment, namespace: segmentNS)
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.vertical, FDS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeBarChrome(edge: .top, visible: segmentPinned)
    }

    /// Segment cards. The content cross-fades on a segment change; the ZStack
    /// lets the outgoing and incoming stacks overlap instead of stacking.
    private var segmentSection: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                segmentContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(selectedSegment)
            .transition(reduceMotion ? AnyTransition.identity : AnyTransition.opacity)
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, ForgeLayout.sectionGap - FDS.Spacing.sm)
        .padding(.bottom, ForgeLayout.scrollBottomClearance)
    }

    @ViewBuilder
    private var segmentContent: some View {
        if store.dataLoadState == .loading && !store.hasMeaningfulLifeSignal {
            // Page-level loading: skeleton blocks at the card radius (spec §9).
            ForgeSkeletonBlock(height: 88, cornerRadius: FDS.Radius.xl)
            ForgeSkeletonBlock(height: 180, cornerRadius: FDS.Radius.xl)
            ForgeSkeletonBlock(height: 140, cornerRadius: FDS.Radius.xl)
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
            case .lifetime:       LifestyleLifetimeView(vm: vm)
            case .wellbeing:      WellbeingView(vm: vm)
            }
        }
    }
}

struct LifestyleBackground: View {
    let segment: LifestyleSegment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Token-only segment wash (spec §14). The chrome stays `.vitality`; only
    /// this background follows the segment.
    static func wash(for segment: LifestyleSegment) -> Color {
        switch segment {
        case .aiOptimization: return Color.aurora
        case .homeCooking:    return Color.ember
        case .restaurants:    return Color.indigo
        case .nutrition:      return Color.amber
        case .lifetime:       return Color.steel
        case .wellbeing:      return Color.vitality
        }
    }

    private var accentColor: Color { Self.wash(for: segment) }

    var body: some View {
        // Flat field; the segment's color lives in its content, not a wash.
        Color.background
    }
}

/// Lifestyle page header (spec §14): `ForgePageHeader` with exactly two 44 pt
/// trailing controls (hydration, ARIA), and the display-only QoL score as a
/// chip underneath rather than a third trailing item.
struct LifestyleHeaderView: View {
    @EnvironmentObject var store: AppStore
    @Binding var showInsights: Bool
    let metrics: LifestyleMetrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            ForgePageHeader(
                title: "Lifestyle",
                subtitle: "How you eat, move, and live",
                accent: .vitality
            ) {
                HStack(spacing: FDS.Spacing.sm) {
                    hydrationButton
                    ariaButton
                }
            }
            qolChip
        }
    }

    private var hydrationButton: some View {
        ForgeIconButton(
            systemImage: "drop.fill",
            accent: Color.steel,
            accessibilityLabel: "Open hydration"
        ) {
            store.openHydration()
        }
    }

    /// 28 pt mark: at 32 pt or smaller ARIA holds its still pose (spec §8),
    /// inside a full 44 pt target.
    private var ariaButton: some View {
        Button {
            if reduceMotion {
                showInsights = true
            } else {
                withAnimation(ForgeMotion.smooth) { showInsights = true }
            }
        } label: {
            ARIAIdentityMark(state: .idle, mood: .energized, size: 28, amplitude: 0.24)
                .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ARIA insights")
    }

    private var qolChip: some View {
        HudVibeChip(
            label: "QoL \(metrics.qualityOfLifeScore)",
            energy: HomeReadiness.color(metrics.qualityOfLifeScore)
        )
        .accessibilityLabel("Quality of life \(metrics.qualityOfLifeScore)")
    }
}

/// Lifestyle's segment selector. Six options always render as the shared
/// edge-bleed rail, which scrolls the selection (including a deep-linked one)
/// into view. The accent is the Lifestyle chrome, never the segment color.
struct SegmentedPillControl: View {
    @Binding var selected: LifestyleSegment
    let namespace: Namespace.ID

    private var options: [ForgeSegmentOption<LifestyleSegment>] {
        LifestyleSegment.allCases.map { segment in
            ForgeSegmentOption(value: segment, title: segment.title, icon: segment.icon)
        }
    }

    var body: some View {
        ForgeSegmentedControl(options, selection: $selected, accent: .vitality)
    }
}

#Preview {
    LifestyleView()
        .environmentObject(AppStore())
}
