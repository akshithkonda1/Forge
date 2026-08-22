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
                    VStack(spacing: 18) {
                        header
                        muscleBalanceCard
                        muscleEmphasisCard
                        if !isPreWorkout { zoneCard }
                        if !snapshot.autoRegLog.isEmpty { autoRegCard }
                        recommendationsCard
                        sendCard
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 50)
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
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.ember, Color(hex: "FF5A00")], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 50, height: 50)
                        .shadow(color: .ember.opacity(0.5), radius: 12, y: 4)
                    Image(systemName: "brain.head.profile").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPreWorkout ? "ARIA · PRE-FLIGHT" : "ARIA · DEBRIEF").font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.ember)
                    Text(snapshot.title).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
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
        .padding(18).background(Color.white.opacity(0.04)).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func metric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.white)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Color.white.opacity(0.04)).cornerRadius(12)
    }

    private var muscleBalanceCard: some View {
        dashCard("MOVEMENT BALANCE", icon: "scale.3d") {
            VStack(spacing: 10) {
                ForEach(snapshot.regionShare.filter { $0.1 > 0.001 }, id: \.0) { region, share in
                    HStack(spacing: 10) {
                        Text(region.rawValue.capitalized).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.8)).frame(width: 90, alignment: .leading)
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
            VStack(spacing: 8) {
                ForEach(snapshot.topMuscles, id: \.0) { m, share in
                    HStack(spacing: 10) {
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
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(snapshot.zoneSeconds.enumerated()), id: \.offset) { idx, secs in
                    let z = WorkoutHRZone.all[idx + 1]
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)).frame(height: 70)
                            RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [z.color, z.color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(4, 70 * CGFloat(appeared ? Double(secs) / Double(maxV) : 0)))
                                .animation(.spring(response: 0.8, dampingFraction: 0.78).delay(Double(idx) * 0.06), value: appeared)
                        }
                        .frame(height: 70)
                        Text(secs >= 60 ? "\(secs/60)m" : "\(secs)s").font(.system(size: 9, weight: .bold)).foregroundColor(secs > 0 ? z.color : .white.opacity(0.25))
                        Text("Z\(idx+1)").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var autoRegCard: some View {
        dashCard("AUTO-REGULATION LOG", icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(snapshot.autoRegLog.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
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
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(recommendations.enumerated()), id: \.offset) { _, rec in
                    HStack(alignment: .top, spacing: 8) {
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
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.bubble.fill").font(.system(size: 14)).foregroundColor(.ember)
                Text(briefing.isEmpty ? snapshot.localBriefing : briefing)
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.85)).lineSpacing(4)
                Spacer(minLength: 0)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ember.opacity(0.07)).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ember.opacity(0.2), lineWidth: 1))

            Button { Task { await sendToARIA() } } label: {
                HStack(spacing: 10) {
                    if loadingBrief { ProgressView().tint(.white) }
                    else { Image(systemName: sent ? "checkmark.circle.fill" : "paperplane.fill").font(.system(size: 17, weight: .bold)) }
                    Text(sent ? "Sent to ARIA — open chat" : loadingBrief ? "ARIA is reviewing…" : "Send this data to ARIA").font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56)
                .background(LinearGradient(colors: sent ? [.success, .success.opacity(0.8)] : [.ember, Color(hex: "FF5A00")], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(16).shadow(color: (sent ? Color.success : Color.ember).opacity(0.5), radius: 16, y: 6)
            }
            .disabled(loadingBrief)
            if !aria.hasAPIKey {
                Text("Tip: add ANTHROPIC_API_KEY to enable ARIA's live Claude debrief. Using the on-device analysis for now.")
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
            let message = ChatMessage(id: UUID().uuidString, role: .trainer,
                                      content: briefing.isEmpty ? snapshot.localBriefing : briefing,
                                      timestamp: Date(), richCard: muscles.isEmpty ? nil : chart)
            store.chatMessages.append(message)
            withAnimation { sent = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            store.activeTab = .chat
            dismiss()
        }
    }

    @ViewBuilder
    private func dashCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(.ember)
                Text(title).font(.system(size: 10, weight: .black)).tracking(2).foregroundColor(.white.opacity(0.45))
            }
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04)).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}
