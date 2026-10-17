import SwiftUI
import UIKit
import ForgeCore

@MainActor
struct ARIADashboardView: View {
    let snapshot: ARIASessionSnapshot
    var isPreWorkout: Bool = false
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var aria = ARIACoachService()
    @State private var sent = false
    @State private var briefing: String = ""
    @State private var loadingBrief = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                ForgeScreenStack(top: ForgeLayout.screenTop) {
                    hero
                    muscleBalanceCard
                    muscleEmphasisCard
                    if !isPreWorkout { zoneCard }
                    if !snapshot.autoRegLog.isEmpty { autoRegCard }
                    recommendationsCard
                    sendCard
                }
            }
            .forgeScreenBackground(accent: .ember)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { briefing = snapshot.localBriefing }
        }
    }

    // MARK: Hero

    private var heroEyebrow: String {
        isPreWorkout ? "ARIA · PRE-FLIGHT" : "ARIA · DEBRIEF"
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            HStack(spacing: ForgeLayout.rowGap) {
                ARIAIdentityMark(state: .idle, mood: .energized, size: 40, amplitude: 0.24)
                    .environment(\.forgeMinimalAnimation, true)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(heroEyebrow)
                        .forgeSectionLabel(tint: .aurora)
                    Text(snapshot.title)
                        .font(ForgeType.title)
                        .foregroundColor(.textPrimary)
                        .forgeWrapping()
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 0)
            }
            heroStats
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard()
        .accessibilityElement(children: .contain)
    }

    private var heroStats: some View {
        ForgeStatGrid(columns: 3) {
            ForgeStatTile(
                label: "Volume",
                value: snapshot.totalVolume.formattedVolume,
                unit: "lb",
                energy: .steel
            )
            ForgeStatTile(
                label: "Sets",
                value: "\(snapshot.totalSets)",
                energy: .ember
            )
            if isPreWorkout {
                ForgeStatTile(
                    label: "Readiness",
                    value: "\(snapshot.readiness)",
                    energy: HomeReadiness.color(snapshot.readiness)
                )
            } else {
                ForgeStatTile(
                    label: "Avg RPE",
                    value: snapshot.avgRPE > 0 ? String(format: "%.1f", snapshot.avgRPE) : "—",
                    energy: .amber
                )
            }
        }
    }

    // MARK: Balance + emphasis

    /// Label and percent on one line, the bar full-width beneath, so a long
    /// label ("Conditioning") never competes with a fixed-width column.
    private func shareRow(label: String, share: Double, tint: Color) -> some View {
        let percent = Int((share * 100).rounded())
        return VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeAdaptiveStack(spacing: ForgeLayout.pairGap, alignment: .firstTextBaseline) {
                Text(label)
                    .font(HomeType.status)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(percent)%")
                    .font(HomeType.label)
                    .monospacedDigit()
                    .foregroundColor(.textSecondary)
                    .forgeSingleLine()
            }
            ForgeProgressBar(fraction: share, tint: tint, height: 8)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(percent) percent")
    }

    private var muscleBalanceCard: some View {
        dashCard("MOVEMENT BALANCE", tint: .ember) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(snapshot.regionShare.filter { $0.1 > 0.001 }, id: \.0) { region, share in
                    shareRow(label: region.label, share: share, tint: region.accent)
                }
            }
        }
    }

    private var muscleEmphasisCard: some View {
        dashCard("MUSCLE EMPHASIS", tint: .ember) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(snapshot.topMuscles, id: \.0) { m, share in
                    shareRow(label: m.label, share: share, tint: m.accent)
                }
                if snapshot.topMuscles.isEmpty {
                    ForgeEmptyNote(title: "Add library movements to see muscle targeting.")
                }
            }
        }
    }

    // MARK: Zones

    private var zoneCard: some View {
        dashCard("HEART-RATE ZONES", tint: .steel) {
            let maxV = max(1, snapshot.zoneSeconds.max() ?? 1)
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(Array(snapshot.zoneSeconds.enumerated()), id: \.offset) { idx, secs in
                    zoneRow(index: idx, seconds: secs, maxSeconds: maxV)
                }
            }
        }
    }

    private func zoneRow(index idx: Int, seconds secs: Int, maxSeconds maxV: Int) -> some View {
        let zones = WorkoutHRZone.all
        let z = zones[min(idx + 1, zones.count - 1)]
        let isMinutes = secs >= 60
        let value = isMinutes ? "\(secs / 60)" : "\(secs)"
        let unit = isMinutes ? "min" : "s"
        let fraction = Double(secs) / Double(maxV)
        return VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeMetricRow(label: "Zone \(idx + 1)", value: value, unit: unit, tint: z.color)
            ForgeProgressBar(fraction: fraction, tint: z.color, height: 4)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone \(idx + 1)")
        .accessibilityValue(isMinutes ? "\(secs / 60) minutes" : "\(secs) seconds")
    }

    // MARK: Log + recommendations

    /// Agenda-row anatomy for a sentence: icon well, then wrapping body text.
    private func sentenceRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: icon, tint: tint)
            Text(text)
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var autoRegCard: some View {
        dashCard("AUTO-REGULATION LOG", tint: .ember) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(Array(snapshot.autoRegLog.enumerated()), id: \.offset) { _, line in
                    sentenceRow(icon: "arrow.triangle.branch", tint: .ember, text: line)
                }
            }
        }
    }

    private var recommendationsCard: some View {
        dashCard("HOW TO IMPROVE", tint: .amber) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(Array(recommendations.enumerated()), id: \.offset) { _, rec in
                    sentenceRow(icon: "lightbulb.fill", tint: .amber, text: rec)
                }
            }
        }
    }

    private var recommendations: [String] {
        var r: [String] = []
        if let weak = snapshot.regionShare.filter({ $0.1 > 0 }).min(by: { $0.1 < $1.1 }), snapshot.regionShare.filter({ $0.1 > 0 }).count > 1 {
            r.append("Add a \(weak.0.rawValue) movement next session to even out weekly volume.")
        }
        if snapshot.avgRPE > 0 && snapshot.avgRPE < 6 { r.append("Average RPE was low — there's room to add load or reps and drive progression.") }
        if snapshot.avgRPE >= 9 { r.append("Effort ran very high — schedule a deload-leaning session to bank recovery.") }
        if snapshot.minO2 < 95 && !isPreWorkout { r.append("O₂ dipped under 95% — build aerobic base with 1–2 easy Zone-2 sessions weekly.") }
        if !snapshot.painFlags.isEmpty { r.append("Pain flagged at \(snapshot.painFlags.joined(separator: ", ")) — ARIA will pre-screen loads next time.") }
        if snapshot.readiness >= 85 && isPreWorkout { r.append("Readiness is elite — attack your first compound for a rep PR.") }
        if r.isEmpty { r.append("Balanced, well-executed session. Keep the progression steady — small, consistent overload.") }
        return r
    }

    // MARK: Send

    private var briefingText: String {
        briefing.isEmpty ? snapshot.localBriefing : briefing
    }

    private var primaryTitle: String {
        if sent { return "Open in chat" }
        return loadingBrief ? "ARIA is reviewing…" : "Send this data to ARIA"
    }

    private var primaryIcon: String {
        if sent { return "checkmark" }
        return loadingBrief ? "ellipsis" : "paperplane.fill"
    }

    private var sendCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "text.bubble.fill", tint: .ember)
                Text(briefingText)
                    .font(HomeType.body)
                    .foregroundColor(.textSecondary)
                    .lineSpacing(3)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .forgeContentCard(tint: .ember)

            ForgePrimaryButton(
                title: primaryTitle,
                icon: primaryIcon,
                accent: .ember,
                subtitle: sent ? "Sent to ARIA" : nil
            ) {
                Task { await sendToARIA() }
            }
            .disabled(loadingBrief)
            .opacity(loadingBrief ? 0.6 : 1)

            if !aria.isLiveCoachingAvailable {
                // Was: "add ANTHROPIC_API_KEY to enable ARIA's live Claude debrief."
                // Telling a user to put an API key in the app was the visible end
                // of a client that called Anthropic directly. Whether live
                // reasoning is on is now a server-side fact, and not something
                // anyone should be able to change from the device.
                Text("ARIA's live debrief isn't available right now. Using the on-device analysis instead.")
                    .font(HomeType.body)
                    .foregroundColor(.textTertiary)
                    .forgeWrapping()
            }
        }
    }

    private func sendToARIA() async {
        if !sent {
            loadingBrief = true
            // Prefer a live Claude debrief; fall back to the on-device briefing.
            if let live = await aria.briefing(for: snapshot) { briefing = live }
            loadingBrief = false
            let muscles = snapshot.topMuscles
            let chart = RichCardData(
                type: .dataChart,
                chartTitle: "Muscle Emphasis · \(snapshot.title)",
                chartValues: muscles.map { $0.1 * 100 },
                chartInsight: muscles.map { "\($0.0.label) \(Int($0.1*100))%" }.joined(separator: " · "),
                chartColor: .ember
            )
            let content = briefing.isEmpty ? snapshot.localBriefing : briefing
            let message = ChatMessage(id: UUID().uuidString, role: .trainer,
                                      content: content,
                                      timestamp: Date(), richCard: muscles.isEmpty ? nil : chart)
            store.addMessage(message)
            AriaContextStore.shared.addInsight("Workout briefing (\(snapshot.title)): \(content)")
            withAnimation(reduceMotion ? nil : Animation.default) { sent = true }
            ForgeHaptics.play(.success)
        } else {
            store.activeTab = .chat
            dismiss()
        }
    }

    /// Standard card: eyebrow header, then the body at the block gap.
    private func dashCard<Content: View>(
        _ title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title)
            content()
        }
        .forgeContentCard(tint: tint)
    }
}
