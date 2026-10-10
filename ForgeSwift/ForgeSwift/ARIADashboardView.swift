import SwiftUI
import UIKit

@MainActor
struct ARIADashboardView: View {
    let snapshot: ARIASessionSnapshot
    var isPreWorkout: Bool = false
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var aria = ARIACoachService()
    @State private var sent = false
    @State private var briefing: String = ""
    @State private var loadingBrief = false
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0A").ignoresSafeArea()
                RadialGradient(colors: [Color.ember.opacity(appeared ? 0.10 : 0), .clear], center: .top, startRadius: 0, endRadius: 360)
                    .ignoresSafeArea().animation(.easeInOut(duration: 1.2), value: appeared)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: FDS.Spacing.lg) {
                        header
                        muscleBalanceCard
                        muscleEmphasisCard
                        if !isPreWorkout { zoneCard }
                        if !snapshot.autoRegLog.isEmpty { autoRegCard }
                        recommendationsCard
                        sendCard
                    }
                    .padding(.horizontal, FDS.Spacing.lg).padding(.top, FDS.Spacing.md).padding(.bottom, 50)
                }
            }
            .navigationTitle(isPreWorkout ? "Session Brief" : "Performance Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold) } }
            .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true }; briefing = snapshot.localBriefing }
        }
    }

    private var header: some View {
        VStack(spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.lg) {
                ARIAIdentityMark(state: .idle, mood: .energized, size: 50, amplitude: 0.24)
                    .shadow(color: .ember.opacity(0.5), radius: 12, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPreWorkout ? "ARIA · PRE-FLIGHT" : "ARIA · DEBRIEF").font(FDS.TypeScale.Dynamic.micro).tracking(2).foregroundColor(.ember)
                    Text(snapshot.title).font(FDS.TypeScale.Dynamic.title).foregroundColor(.white)
                }
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("\(snapshot.totalVolume.formattedVolume)", "Volume", .steel)
                metric("\(snapshot.totalSets)", "Sets", .ember)
                if isPreWorkout { metric("\(snapshot.readiness)", "Readiness", .success) }
                else { metric(snapshot.avgRPE > 0 ? String(format: "%.1f", snapshot.avgRPE) : "—", "Avg RPE", .warning) }
            }
        }
        .padding(FDS.Spacing.lg).background(Color.white.opacity(0.04)).cornerRadius(FDS.Radius.xl)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func metric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(FDS.TypeScale.Dynamic.metric).foregroundColor(.white)
            Text(label).font(FDS.TypeScale.Dynamic.micro).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, FDS.Spacing.md)
        .background(Color.white.opacity(0.04)).cornerRadius(FDS.Radius.md)
    }

    private var muscleBalanceCard: some View {
        dashCard("MOVEMENT BALANCE", icon: "scale.3d") {
            VStack(spacing: FDS.Spacing.md) {
                ForEach(snapshot.regionShare.filter { $0.1 > 0.001 }, id: \.0) { region, share in
                    HStack(spacing: FDS.Spacing.md) {
                        Text(region.rawValue.capitalized).font(FDS.TypeScale.Dynamic.caption).foregroundColor(.white.opacity(0.8)).frame(width: 90, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06)).frame(height: 8)
                                Capsule().fill(LinearGradient(colors: [region.accent, region.accent.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, geo.size.width * (appeared ? share : 0)), height: 8)
                                    .animation(.spring(response: 0.8, dampingFraction: 0.8), value: appeared)
                            }
                        }
                        .frame(height: 8)
                        Text("\(Int(share * 100))%").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(region.accent).frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var muscleEmphasisCard: some View {
        dashCard("MUSCLE EMPHASIS", icon: "figure.arms.open") {
            VStack(spacing: FDS.Spacing.sm) {
                ForEach(snapshot.topMuscles, id: \.0) { m, share in
                    HStack(spacing: FDS.Spacing.md) {
                        Circle().fill(m.accent).frame(width: 8, height: 8)
                        Text(m.label).font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text("\(Int(share * 100))%").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(m.accent)
                    }
                }
                if snapshot.topMuscles.isEmpty {
                    Text("Add library movements to see muscle targeting.").font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    private var zoneCard: some View {
        dashCard("HEART-RATE ZONES", icon: "waveform.path.ecg") {
            let maxV = max(1, snapshot.zoneSeconds.max() ?? 1)
            HStack(alignment: .bottom, spacing: FDS.Spacing.md) {
                ForEach(Array(snapshot.zoneSeconds.enumerated()), id: \.offset) { idx, secs in
                    let z = WorkoutHRZone.all[idx + 1]
                    VStack(spacing: FDS.Spacing.sm) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: FDS.Radius.xs).fill(Color.white.opacity(0.06)).frame(height: 70)
                            RoundedRectangle(cornerRadius: FDS.Radius.xs).fill(LinearGradient(colors: [z.color, z.color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(4, 70 * CGFloat(appeared ? Double(secs) / Double(maxV) : 0)))
                                .animation(.spring(response: 0.8, dampingFraction: 0.78).delay(Double(idx) * 0.06), value: appeared)
                        }
                        .frame(height: 70)
                        Text(secs >= 60 ? "\(secs/60)m" : "\(secs)s").font(FDS.TypeScale.Dynamic.micro).foregroundColor(secs > 0 ? z.color : .white.opacity(0.25))
                        Text("Z\(idx+1)").font(FDS.TypeScale.Dynamic.micro).foregroundColor(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var autoRegCard: some View {
        dashCard("AUTO-REGULATION LOG", icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                ForEach(Array(snapshot.autoRegLog.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 11)).foregroundColor(.ember)
                        Text(line).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).lineSpacing(3)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var recommendationsCard: some View {
        dashCard("HOW TO IMPROVE", icon: "lightbulb.fill") {
            VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                ForEach(Array(recommendations.enumerated()), id: \.offset) { _, rec in
                    HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundColor(.success)
                        Text(rec).font(.system(size: 13)).foregroundColor(.white.opacity(0.85)).lineSpacing(3)
                        Spacer(minLength: 0)
                    }
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

    private var sendCard: some View {
        VStack(spacing: FDS.Spacing.md) {
            HStack(alignment: .top, spacing: FDS.Spacing.md) {
                Image(systemName: "text.bubble.fill").font(.system(size: 14)).foregroundColor(.ember)
                Text(briefing.isEmpty ? snapshot.localBriefing : briefing)
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.85)).lineSpacing(4)
                Spacer(minLength: 0)
            }
            .padding(FDS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ember.opacity(0.07)).cornerRadius(FDS.Radius.lg)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.lg).stroke(Color.ember.opacity(0.2), lineWidth: 1))

            Button { Task { await sendToARIA() } } label: {
                HStack(spacing: FDS.Spacing.md) {
                    if loadingBrief { ProgressView().tint(.white) }
                    else { Image(systemName: sent ? "checkmark.circle.fill" : "paperplane.fill").font(.system(size: 17, weight: .bold)) }
                    Text(sent ? "Sent to ARIA — open chat" : loadingBrief ? "ARIA is reviewing…" : "Send this data to ARIA").font(FDS.TypeScale.Dynamic.headline)
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56)
                .background(LinearGradient(colors: sent ? [.success, .success.opacity(0.8)] : [.ember, Color(hex: "FF5A00")], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(FDS.Radius.lg).shadow(color: (sent ? Color.success : Color.ember).opacity(0.5), radius: 16, y: 6)
            }
            .disabled(loadingBrief)
            if !aria.isLiveCoachingAvailable {
                // Was: "add ANTHROPIC_API_KEY to enable ARIA's live Claude debrief."
                // Telling a user to put an API key in the app was the visible end
                // of a client that called Anthropic directly. Whether live
                // reasoning is on is now a server-side fact, and not something
                // anyone should be able to change from the device.
                Text("ARIA's live debrief isn't available right now. Using the on-device analysis instead.")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.35)).multilineTextAlignment(.center)
            }
        }
    }

    private func sendToARIA() async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
            withAnimation { sent = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            store.activeTab = .chat
            dismiss()
        }
    }

    @ViewBuilder
    private func dashCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(.ember)
                Text(title).font(FDS.TypeScale.Dynamic.micro).tracking(2).foregroundColor(.white.opacity(0.45))
            }
            content()
        }
        .padding(FDS.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04)).cornerRadius(FDS.Radius.xl)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}
