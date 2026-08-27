import SwiftUI

struct SleepDayTab: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                EnergyScheduleCard()
                SleepLastNightStrip()
                SleepWeekRhythm()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
    }
}

struct SleepNightTab: View {
    @EnvironmentObject var store: AppStore
    @Binding var showPersonalization: Bool
    @State private var showSounds = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                SleepLastNightDetail()
                SleepWeekRhythm()
                ChronotypeBadge(onTap: { showPersonalization = true })
                Button { showSounds = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sounds")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text("Rain, noise, or a timer for wind-down.")
                                .font(.system(size: 13))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showSounds) {
            NavigationStack {
                SleepSoundsTab()
                    .navigationTitle("Sounds")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSounds = false }
                        }
                    }
            }
        }
    }
}

struct SleepLastNightStrip: View {
    @EnvironmentObject var store: AppStore

    private var night: SleepData? { store.sleepData.first }

    var body: some View {
        if let night {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Last night")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textTertiary)
                    Spacer()
                    Text("\(night.efficiencyPercent)% efficient")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.aurora)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(EnergySchedule.durationLabel(night.totalHours))
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                    Text("asleep")
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("\(night.clock(night.onset)) → \(night.clock(night.wake))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .monospacedDigit()
                }
                SleepHypnogram(night: night, height: 54)
                SleepStageLegend(night: night)
            }
        } else {
            Text("Last night will show duration, stages, and efficiency once Apple Health is connected.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
        }
    }
}

struct SleepLastNightDetail: View {
    @EnvironmentObject var store: AppStore

    private var night: SleepData? { store.sleepData.first }

    var body: some View {
        if let night {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last night")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
                HStack(alignment: .firstTextBaseline) {
                    Text(EnergySchedule.durationLabel(night.totalHours))
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .monospacedDigit()
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(night.score)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundColor(.textPrimary)
                        Text("score")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                }
                Text("\(night.clock(night.onset))  →  \(night.clock(night.wake))   ·   \(night.efficiencyPercent)% of time in bed was sleep")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                SleepHypnogram(night: night, height: 92)
                HStack(spacing: 0) {
                    nightStat("Deep", "\(night.deepMinutes)m", Color.steel)
                    nightStat("REM", "\(night.remMinutes)m", Color.aurora)
                    nightStat("Light", "\(night.lightMinutes)m", Color(hex: "64748B"))
                    nightStat("Awake", "\(night.awakeMinutes)m", Color.danger.opacity(0.8))
                }
                .padding(.top, 4)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No night on file")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Connect Apple Health and last night will land here — stages, efficiency, and the energy day it built.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private func nightStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pillow-style stage map: stacked bands from time-in-bed, not a hairline.
struct SleepHypnogram: View {
    let night: SleepData
    var height: CGFloat = 64

    private var bands: [(id: String, color: Color, minutes: Int, y: CGFloat)] {
        [
            ("awake", Color.danger.opacity(0.75), night.awakeMinutes, 0.08),
            ("rem", Color.aurora, night.remMinutes, 0.30),
            ("light", Color(hex: "64748B"), night.lightMinutes, 0.54),
            ("deep", Color.steel, night.deepMinutes, 0.78),
        ]
    }

    private var total: Int {
        max(1, night.deepMinutes + night.remMinutes + night.lightMinutes + night.awakeMinutes)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(bands, id: \.id) { band in
                        let share = CGFloat(band.minutes) / CGFloat(total)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(band.color)
                            .frame(
                                width: max(band.minutes > 0 ? 6 : 0, w * share - 2),
                                height: height * (1 - band.y * 0.35)
                            )
                    }
                }
                .padding(6)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Sleep stages. Deep \(night.deepMinutes) minutes, REM \(night.remMinutes), light \(night.lightMinutes), awake \(night.awakeMinutes).")
    }
}

struct SleepStageLegend: View {
    let night: SleepData

    var body: some View {
        HStack(spacing: 12) {
            legend("Deep", night.deepMinutes, Color.steel)
            legend("REM", night.remMinutes, Color.aurora)
            legend("Light", night.lightMinutes, Color(hex: "64748B"))
            legend("Awake", night.awakeMinutes, Color.danger.opacity(0.75))
        }
    }

    private func legend(_ name: String, _ minutes: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(minutes)m")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textTertiary)
                .monospacedDigit()
        }
    }
}

struct SleepWeekRhythm: View {
    @EnvironmentObject var store: AppStore

    private var nights: [SleepData] {
        Array(store.sleepData.prefix(7).reversed())
    }

    private var need: Double {
        EnergySchedule.make(from: store.sleepData)?.needHours ?? 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textTertiary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(nights) { night in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(night.totalHours >= need - 0.4 ? Color.ember.opacity(0.88) : Color.aurora.opacity(0.28))
                            .frame(height: max(10, CGFloat(night.totalHours / 10) * 78))
                        Text(weekday(night.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(weekday(night.date)), \(EnergySchedule.durationLabel(night.totalHours))")
                }
            }
            .frame(height: 102, alignment: .bottom)
        }
    }

    private func weekday(_ value: String) -> String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: value) else { return "" }
        let out = DateFormatter()
        out.setLocalizedDateFormatFromTemplate("EEEEE")
        return out.string(from: date)
    }
}

struct SleepScoreHeroCard: View {
    @EnvironmentObject var store: AppStore
    @State private var progress: CGFloat = 0
    @State private var appeared = false

    // Dead code today (never instantiated -- see the identical note on
    // SleepInsightCards.swift's SleepTimelineView). Kept in the same
    // graceful-empty shape as the live SleepLastNightDetail rather than the
    // unguarded sleepData[0] this used to trap on.
    var latest: SleepData? { store.sleepData.first }
    var score: Int { latest.map { min(100, max(0, $0.score)) } ?? 0 }
    var totalHrs: String {
        guard let latest else { return "0h 0m" }
        let h = Int(latest.totalHours); let m = Int((latest.totalHours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var scoreLabel: String {
        switch score { case 85...: return "Excellent"; case 70..<85: return "Good"; case 55..<70: return "Fair"; default: return "Poor" }
    }
    var scoreColor: Color {
        switch score { case 85...: return .success; case 70..<85: return .steel; case 55..<70: return .warning; default: return .danger }
    }

    let size: CGFloat = 168
    let stroke: CGFloat = 13

    var body: some View {
        if let latest {
            heroContent(latest)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No night on file")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Connect Apple Health and last night's score will land here.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
            }
            .padding(24)
            .background(Color.surface)
            .cornerRadius(24)
        }
    }

    private func heroContent(_ latest: SleepData) -> some View {
        VStack(spacing: 20) {
            // Ring
            ZStack {
                // Track
                Circle()
                    .stroke(Color.borderColor.opacity(0.5), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .frame(width: size, height: size)

                // Glow
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(scoreColor.opacity(0.3), style: StrokeStyle(lineWidth: stroke + 6, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 8)

                // Main arc
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(colors: [scoreColor, scoreColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: scoreColor.opacity(0.5), radius: 12)
                    .animation(.spring(response: 1.4, dampingFraction: 0.7).delay(0.3), value: progress)

                // Tip dot
                if progress > 0.02 {
                    Circle()
                        .fill(scoreColor)
                        .frame(width: stroke * 0.85, height: stroke * 0.85)
                        .shadow(color: scoreColor, radius: 4)
                        .offset(y: -size / 2)
                        .rotationEffect(.degrees(-90 + Double(progress) * 360))
                }

                // Center
                VStack(spacing: 5) {
                    Text("\(score)")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .scaleEffect(appeared ? 1 : 0.7)
                        .animation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.25), value: appeared)
                    Text(scoreLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(scoreColor)
                        .tracking(0.5)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.45), value: appeared)
                }
            }
            .frame(width: size, height: size)

            // Stats row
            HStack(spacing: 0) {
                ScoreStatPill(value: totalHrs, label: "Total")
                Divider().frame(height: 32).background(Color.borderColor)
                ScoreStatPill(value: "\(latest.deepMinutes)m", label: "Deep")
                Divider().frame(height: 32).background(Color.borderColor)
                ScoreStatPill(value: "\(latest.remMinutes)m", label: "REM")
                Divider().frame(height: 32).background(Color.borderColor)
                ScoreStatPill(value: "\(latest.awakeMinutes)m", label: "Awake")
            }
            .padding(.horizontal, 8)
        }
        .padding(24)
        .background(
            ZStack {
                Color.surface
                RadialGradient(colors: [scoreColor.opacity(0.07), .clear], center: .center, startRadius: 40, endRadius: 200)
            }
        )
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                progress = CGFloat(score) / 100
            }
        }
    }
}

struct ScoreStatPill: View {
    let value: String; let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
