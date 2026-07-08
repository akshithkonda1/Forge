import SwiftUI
import UIKit

// MARK: - Workout Summary

struct WorkoutSummaryView: View {
    let data: WorkoutSummaryData
    let onDismiss: () -> Void
    @State private var appeared = false
    @State private var scoreAppeared = false
    @State private var showDashboard = false

    private var workoutScore: Int {
        var s = 60
        if data.personalRecords.count > 0 { s += min(20, data.personalRecords.count * 7) }
        if data.avgRPE >= 6 && data.avgRPE <= 8.5 { s += 10 }
        if data.minO2 >= 95 { s += 5 }
        if data.totalSets >= 12 { s += 5 }
        return min(100, s)
    }
    private var scoreLabel: String {
        switch workoutScore { case 90...: return "Elite"; case 80...: return "Excellent"; case 70...: return "Strong"; case 60...: return "Solid"; default: return "Good" }
    }
    private var scoreColor: Color {
        switch workoutScore { case 90...: return Color.amber; case 80...: return .success; case 70...: return .ember; default: return .steel }
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            RadialGradient(colors: [scoreColor.opacity(appeared ? 0.12 : 0), .clear], center: .top, startRadius: 0, endRadius: 400)
                .ignoresSafeArea().animation(.easeInOut(duration: 1.5).delay(0.5), value: appeared)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero score
                    VStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(scoreColor.opacity(appeared ? 0.12 : 0), lineWidth: 1).frame(width: 220, height: 220).animation(.easeInOut(duration: 1.0).delay(0.4), value: appeared)
                            Circle().stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 8, lineCap: .round)).frame(width: 180, height: 180)
                            Circle().trim(from: 0, to: scoreAppeared ? CGFloat(workoutScore) / 100 : 0)
                                .stroke(LinearGradient(colors: [scoreColor.opacity(0.7), scoreColor, scoreColor.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 180, height: 180).rotationEffect(.degrees(-90)).shadow(color: scoreColor.opacity(0.5), radius: 12)
                                .animation(.spring(response: 1.4, dampingFraction: 0.75).delay(0.5), value: scoreAppeared)
                            VStack(spacing: 4) {
                                Image(systemName: "checkmark").font(.forgeDynamic(size: 22, weight: .black)).foregroundColor(scoreColor)
                                    .scaleEffect(appeared ? 1 : 0.4).opacity(appeared ? 1 : 0).animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.3), value: appeared)
                                Text("\(workoutScore)").font(.forgeDynamic(size: 52, weight: .black, design: .rounded)).foregroundColor(.white)
                                    .scaleEffect(appeared ? 1 : 0.6).opacity(appeared ? 1 : 0).animation(.spring(response: 0.65, dampingFraction: 0.7).delay(0.2), value: appeared)
                                Text(scoreLabel.uppercased()).font(.forgeDynamic(size: 10, weight: .black)).foregroundColor(scoreColor).tracking(2.5)
                                    .opacity(appeared ? 1 : 0).animation(.easeOut(duration: 0.5).delay(0.55), value: appeared)
                            }
                        }
                        .frame(width: 220, height: 220)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Workout score")
                        .accessibilityValue("\(workoutScore) out of 100, \(scoreLabel)")
                        VStack(spacing: 8) {
                            Text("Workout Complete").font(.forgeDynamic(size: 26, weight: .bold)).foregroundColor(.white)
                            HStack(spacing: 16) {
                                HStack(spacing: 5) {
                                    Image(systemName: "clock.fill").font(.forgeDynamic(size: 12)).foregroundColor(.white.opacity(0.5))
                                    Text(formatDuration(data.duration)).font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                                }
                                if !data.personalRecords.isEmpty {
                                    HStack(spacing: 5) {
                                        Image(systemName: "crown.fill").font(.forgeDynamic(size: 12)).foregroundColor(.warning)
                                        Text("\(data.personalRecords.count) PR\(data.personalRecords.count == 1 ? "" : "s")").font(.forgeDynamic(size: 14, weight: .bold)).foregroundColor(.warning)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 5).background(Color.warning.opacity(0.15)).cornerRadius(100)
                                    .overlay(Capsule().stroke(Color.warning.opacity(0.3), lineWidth: 1))
                                }
                            }
                        }
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 14).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: appeared)
                    }
                    .padding(.top, 64).padding(.bottom, 28)

                    // ARIA dashboard CTA
                    Button { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); showDashboard = true } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.ember.opacity(0.18)).frame(width: 38, height: 38)
                                Image(systemName: "brain.head.profile").font(.forgeDynamic(size: 17)).foregroundColor(.ember)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open ARIA Dashboard").font(.forgeDynamic(size: 15, weight: .bold)).foregroundColor(.white)
                                Text("Muscle balance, auto-reg log & how to improve").font(.forgeDynamic(size: 11)).foregroundColor(.white.opacity(0.5))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.forgeDynamic(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.4))
                        }
                        .padding(16).background(Color.white.opacity(0.05)).cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ember.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.bottom, 20)
                    .opacity(appeared ? 1 : 0).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: appeared)

                    if !data.hrHistory.isEmpty {
                        HRSparklineCard(hrHistory: data.hrHistory, peakHR: data.peakHR, avgHR: data.avgHR)
                            .padding(.horizontal, 16).padding(.bottom, 20)
                            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.45), value: appeared)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach([
                            ("scalemass.fill", "\(data.totalVolume.formattedVolume)", "Volume", Color.steel),
                            ("flame.fill", "\(data.caloriesBurned)", "Kcal", Color.ember),
                            ("repeat", "\(data.totalSets)", "Sets", Color.success),
                            ("hand.raised.fill", "\(data.totalReps)", "Reps", Color.amber),
                            ("heart.fill", "\(data.peakHR)", "Peak HR", Color.danger),
                            ("waveform.path.ecg", "\(data.avgHR)", "Avg HR", Color.steel),
                            ("lungs.fill", "\(data.minO2)%", "Min O₂", data.minO2 < 94 ? Color.danger : Color.sky),
                            ("bolt.fill", String(format: "%.1f", data.avgRPE), "Avg RPE", rpeColor(data.avgRPE)),
                            ("dumbbell.fill", "\(data.exercisesCompleted)", "Exercises", Color.ember),
                        ], id: \.0) { icon, value, label, color in darkStatCard(icon, value, label, color) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5), value: appeared)

                    ZoneBreakdownCard(hrHistory: data.hrHistory)
                        .padding(.horizontal, 16).padding(.bottom, 20)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.55), value: appeared)

                    if !data.personalRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: "crown.fill").font(.forgeDynamic(size: 14)).foregroundColor(.warning)
                                Text("PERSONAL RECORDS").font(.forgeDynamic(size: 10, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                            }
                            ForEach(data.personalRecords, id: \.self) { pr in
                                HStack(spacing: 12) {
                                    ZStack { Circle().fill(Color.warning.opacity(0.15)).frame(width: 38, height: 38); Image(systemName: "crown.fill").font(.forgeDynamic(size: 15)).foregroundColor(.warning) }
                                    Text(pr).font(.forgeDynamic(size: 15, weight: .semibold)).foregroundColor(.white)
                                    Spacer()
                                    Text("NEW PR").font(.forgeDynamic(size: 10, weight: .black)).foregroundColor(.warning).tracking(1)
                                        .padding(.horizontal, 8).padding(.vertical, 5).background(Color.warning.opacity(0.15)).cornerRadius(100).overlay(Capsule().stroke(Color.warning.opacity(0.3), lineWidth: 1))
                                }
                                .padding(16).background(Color.white.opacity(0.05)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.warning.opacity(0.2), lineWidth: 1))
                            }
                        }
                        .padding(20).background(Color.white.opacity(0.04)).cornerRadius(22).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
                        .padding(.horizontal, 16).padding(.bottom, 20)
                        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.6), value: appeared)
                    }

                    VStack(spacing: 12) {
                        Button { showDashboard = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "paperplane.fill").font(.forgeDynamic(size: 16))
                                Text("Send to ARIA").font(.forgeDynamic(size: 17, weight: .bold))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 58)
                            .background(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(18).shadow(color: Color.ember.opacity(0.5), radius: 18, y: 6)
                        }
                        Button(action: onDismiss) {
                            HStack(spacing: 8) {
                                Image(systemName: "house.fill").font(.forgeDynamic(size: 15))
                                Text("Back to Dashboard").font(.forgeDynamic(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity).frame(height: 50)
                            .background(Color.white.opacity(0.07)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 60)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20).animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.7), value: appeared)
                }
            }
        }
        .sheet(isPresented: $showDashboard) { ARIADashboardView(snapshot: data.ariaSnapshot, isPreWorkout: false) }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.8).delay(0.1)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scoreAppeared = true }
        }
    }

    private func darkStatCard(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack { Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40); Image(systemName: icon).font(.forgeDynamic(size: 16)).foregroundColor(color) }
            Text(value).font(.forgeDynamic(size: 18, weight: .black, design: .rounded)).foregroundColor(.white)
            Text(label).font(.forgeDynamic(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.4)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18).background(Color.white.opacity(0.05)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
    private func rpeColor(_ rpe: Double) -> Color { rpe <= 4 ? .success : rpe <= 7 ? Color.amber : .danger }
    private func formatDuration(_ s: Int) -> String { let m = s / 60; let sec = s % 60; return m > 0 ? "\(m)m \(sec)s" : "\(sec)s" }
}
// MARK: - Zone Breakdown Card

struct ZoneBreakdownCard: View {
    let hrHistory: [Int]
    @State private var barsAppeared = false
    private struct ZoneBar { let zone: String; let color: Color; let range: ClosedRange<Int>; var count: Int = 0 }
    private var zoneBars: [ZoneBar] {
        var bars = [
            ZoneBar(zone: "Z1", color: Color.sky, range: 100...114),
            ZoneBar(zone: "Z2", color: .success, range: 115...133),
            ZoneBar(zone: "Z3", color: Color.amber, range: 134...152),
            ZoneBar(zone: "Z4", color: .ember, range: 153...171),
            ZoneBar(zone: "Z5", color: .danger, range: 172...220),
        ]
        for hr in hrHistory { for i in bars.indices where bars[i].range.contains(hr) { bars[i].count += 1 } }
        return bars
    }
    var body: some View {
        let bars = zoneBars
        let maxCount = max(1, bars.map { $0.count }.max() ?? 1)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg").font(.forgeDynamic(size: 13)).foregroundColor(.danger)
                Text("HEART RATE ZONES").font(.forgeDynamic(size: 10, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                Spacer()
                Text("\(hrHistory.count) samples").font(.forgeDynamic(size: 11)).foregroundColor(.white.opacity(0.3))
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(bars.enumerated()), id: \.element.zone) { idx, bar in
                    VStack(spacing: 8) {
                        let fraction = barsAppeared ? CGFloat(bar.count) / CGFloat(maxCount) : 0
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)).frame(maxWidth: .infinity, maxHeight: .infinity)
                            RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [bar.color, bar.color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                                .frame(maxWidth: .infinity).frame(height: max(4, 80 * fraction)).shadow(color: bar.color.opacity(0.4), radius: 4)
                        }
                        .frame(height: 80).animation(.spring(response: 0.9, dampingFraction: 0.75).delay(Double(idx) * 0.08), value: barsAppeared)
                        Text(formatZoneTime(bar.count)).font(.forgeDynamic(size: 10, weight: .bold)).foregroundColor(bar.count > 0 ? bar.color : .white.opacity(0.2))
                        Text(bar.zone).font(.forgeDynamic(size: 10, weight: .black)).foregroundColor(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20).background(Color.white.opacity(0.04)).cornerRadius(22).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { barsAppeared = true } }
    }
    private func formatZoneTime(_ count: Int) -> String { let secs = count * 2; return secs < 60 ? "\(secs)s" : "\(secs / 60)m" }
}

// MARK: - HR Sparkline Card

struct HRSparklineCard: View {
    let hrHistory: [Int]
    let peakHR: Int
    let avgHR:  Int
    @State private var lineAppeared = false
    private var smoothed: [Int] {
        guard hrHistory.count > 4 else { return hrHistory }
        let step = max(1, hrHistory.count / 60)
        return stride(from: 0, to: hrHistory.count, by: step).map { hrHistory[$0] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.forgeDynamic(size: 13)).foregroundColor(.danger)
                    Text("HEART RATE").font(.forgeDynamic(size: 10, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                }
                Spacer()
                HStack(spacing: 18) {
                    VStack(spacing: 1) { Text("\(peakHR)").font(.forgeDynamic(size: 16, weight: .black, design: .monospaced)).foregroundColor(.danger); Text("peak").font(.forgeDynamic(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.35)) }
                    VStack(spacing: 1) { Text("\(avgHR)").font(.forgeDynamic(size: 16, weight: .black, design: .monospaced)).foregroundColor(.white); Text("avg").font(.forgeDynamic(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.35)) }
                }
            }
            GeometryReader { geo in
                Canvas { ctx, size in
                    let pts = smoothed
                    guard pts.count > 1 else { return }
                    let minV = Double(pts.min() ?? 60); let maxV = Double(pts.max() ?? 200); let rng = max(maxV - minV, 1)
                    let xStep = size.width / Double(pts.count - 1)
                    func y(_ v: Int) -> Double { size.height - (Double(v) - minV) / rng * size.height }
                    func pt(_ i: Int) -> CGPoint { CGPoint(x: Double(i) * xStep, y: y(pts[i])) }
                    let zoneDefs: [(min: Int, max: Int, col: Color)] = [(100,114,Color.sky),(115,133,.success),(134,152,Color.amber),(153,171,.ember),(172,220,.danger)]
                    for z in zoneDefs {
                        let yT = max(0.0, size.height - (Double(z.max) - minV) / rng * size.height)
                        let yB = min(size.height, size.height - (Double(z.min) - minV) / rng * size.height)
                        if yB > yT { ctx.fill(Path(CGRect(x: 0, y: yT, width: size.width, height: yB - yT)), with: .color(z.col.opacity(0.09))) }
                    }
                    var area = Path(); area.move(to: CGPoint(x: 0, y: size.height))
                    for i in pts.indices { i == 0 ? area.move(to: pt(0)) : area.addLine(to: pt(i)) }
                    area.addLine(to: CGPoint(x: size.width, y: size.height)); area.closeSubpath()
                    ctx.fill(area, with: .color(Color.danger.opacity(0.10)))
                    var line = Path(); for i in pts.indices { i == 0 ? line.move(to: pt(0)) : line.addLine(to: pt(i)) }
                    ctx.stroke(line, with: .color(Color.danger.opacity(0.85)), lineWidth: 2)
                }
                .opacity(lineAppeared ? 1 : 0).animation(.easeInOut(duration: 0.8), value: lineAppeared)
            }
            .frame(height: 88)
        }
        .padding(20).background(Color.white.opacity(0.04)).cornerRadius(22).overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { lineAppeared = true } }
    }
}

