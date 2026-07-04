import SwiftUI
import ForgeCore

// MARK: - HomeView (watch)
//
// The glanceable overview: readiness orb + ring, a warm ARIA greeting,
// today's highest-leverage action (usually the recommended reset), and
// quick paths to context + sleep. Everything above the fold in one crown
// scroll or less — launch → meaning in under 1.5s.

struct HomeView: View {
    @Environment(WatchHealthKitManager.self) private var health
    @Environment(ContextEngine.self) private var contextEngine
    @Environment(ARIAWatchService.self) private var aria
    @Environment(MindfulnessSessionManager.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @Binding var path: [WatchRoute]

    var body: some View {
        ScrollView {
            VStack(spacing: ForgeDS.Spacing.md) {
                readinessHeader

                Text(aria.greeting)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ForgePalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("ARIA says: \(aria.greeting)")

                if let suggestion = contextEngine.suggestedMode {
                    suggestedModeBanner(suggestion)
                }

                if let rec = aria.recommendation {
                    ContextCard(
                        systemImage: rec.practice.symbolName,
                        title: "\(rec.durationLabel) \(rec.practice.displayName)",
                        body_: rec.reason,
                        accent: rec.practice.accentColor,
                        accessibilityHint: "Opens the guided session, pre-filled."
                    ) {
                        path.append(.mindfulness)
                    }
                }

                quickActions
                sleepGlance
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Forge")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HapticButton(haptic: .click) {
                    path.append(.context)
                } label: {
                    Image(systemName: contextEngine.currentMode?.symbolName ?? "person.crop.circle")
                        .foregroundStyle(contextEngine.currentMode?.accentColor ?? ForgePalette.textSecondary)
                }
                .accessibilityLabel(contextEngine.currentMode.map { "Context: \($0.displayName)" } ?? "Set your context")
                .accessibilityHint("Choose what part of your day you're in, like desk work or wind-down.")
            }
        }
        .task { await initialLoad() }
        .onChange(of: contextEngine.revision) {
            aria.refresh(health: health, context: contextEngine, sessionsToday: session.sessionsCompletedToday)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await health.refreshAll()
                await contextEngine.evaluate()
                aria.refresh(health: health, context: contextEngine, sessionsToday: session.sessionsCompletedToday)
            }
        }
    }

    // MARK: Header

    private var readinessHeader: some View {
        HapticButton(haptic: .click) {
            path.append(.mindfulness)
        } label: {
            ZStack {
                AuroraOrbWatch(
                    accent: health.readiness?.band.color ?? ForgePalette.steel,
                    size: 92,
                    intensity: health.readiness?.confidence ?? 0.3
                )
                ReadinessRing(
                    score: health.readiness?.overall,
                    confidence: health.readiness?.confidence ?? 0
                ) {
                    VStack(spacing: 0) {
                        if let readiness = health.readiness, readiness.confidence > 0 {
                            Text("\(readiness.overall)")
                                .font(ForgeType.metric(26))
                                .foregroundStyle(ForgePalette.textPrimary)
                            Text(readiness.band.label)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(readiness.band.color)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16))
                                .foregroundStyle(ForgePalette.textTertiary)
                        }
                    }
                }
                .frame(width: 108, height: 108)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, ForgeDS.Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private func suggestedModeBanner(_ mode: LifestyleMode) -> some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            Label("Looks like \(mode.displayName.lowercased())?", systemImage: mode.symbolName)
                .font(ForgeType.caption(12))
                .foregroundStyle(ForgePalette.textPrimary)
            HStack(spacing: ForgeDS.Spacing.sm) {
                HapticButton(haptic: .click) {
                    contextEngine.acceptSuggestedMode()
                } label: {
                    Text("Yes").font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(mode.accentColor.opacity(0.5))
                .accessibilityLabel("Yes, set context to \(mode.displayName)")

                HapticButton(haptic: .click) {
                    contextEngine.dismissSuggestedMode()
                } label: {
                    Text("No").font(.system(size: 12)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("No, dismiss suggestion")
            }
        }
        .padding(ForgeDS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.lg).fill(ForgePalette.surface))
    }

    private var quickActions: some View {
        VStack(spacing: ForgeDS.Spacing.sm) {
            ForgeActionButton(
                title: "Reset now",
                systemImage: "leaf.fill",
                tint: ForgePalette.jade,
                accessibilityHint: "Starts the recommended breathing practice."
            ) {
                path.append(.mindfulness)
            }
            .primaryDoubleTapShortcut() // Double Tap from Home = instant reset

            if session.sessionsCompletedToday > 0 || health.mindfulMinutesToday > 0 {
                Text(consistencyLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ForgePalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(consistencyLine)
            }
        }
    }

    /// Consistency framed as accumulated benefit — never a streak to break.
    private var consistencyLine: String {
        let minutes = Int(health.mindfulMinutesToday.rounded())
        if minutes > 0 {
            return "\(minutes) mindful min today — it all compounds."
        }
        return "Every reset counts, whenever it happens."
    }

    private var sleepGlance: some View {
        Group {
            if let sleep = health.sleepSummary {
                HStack(spacing: ForgeDS.Spacing.sm) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ForgePalette.indigo)
                    Text(sleepLine(sleep))
                        .font(.system(size: 11.5))
                        .foregroundStyle(ForgePalette.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(ForgeDS.Spacing.md)
                .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.lg).fill(ForgePalette.surface))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Last night: \(sleepLine(sleep))")
            }
        }
    }

    private func sleepLine(_ sleep: ForgeHealthQueries.SleepSummary) -> String {
        let hours = Int(sleep.totalMinutes) / 60
        let minutes = Int(sleep.totalMinutes) % 60
        if let quality = health.readiness?.sleepQuality, quality > 0 {
            return "\(hours)h \(minutes)m · quality \(quality)"
        }
        return "\(hours)h \(minutes)m last night"
    }

    // MARK: Load

    private func initialLoad() async {
        await health.requestAuthorization()
        await health.refreshAll()
        await contextEngine.evaluate()
        aria.refresh(health: health, context: contextEngine, sessionsToday: session.sessionsCompletedToday)
    }
}
