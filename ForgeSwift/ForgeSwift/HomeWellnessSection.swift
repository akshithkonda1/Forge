import SwiftUI

// MARK: - Proactive ARIA Brief

struct ARIABriefCard: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var brief: ARIABrief? { store.ariaBrief }

    var body: some View {
        Group {
            if let brief {
                Button {
                    FDS.haptic(.light)
                    store.activeTab = .chat
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.ember)
                            Text(brief.title.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.textTertiary)
                                .tracking(1.5)
                            Spacer()
                            Text(brief.focus == .evening ? "PM" : "AM")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.ember)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.ember.opacity(0.12))
                                .cornerRadius(FDS.Radius.pill)
                        }

                        Text(brief.headline)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(brief.body)
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(4)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            Image(systemName: brief.trainingDecision.icon)
                            Text(brief.trainingDecision.label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.ember)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ZStack {
                            Color.surface
                            LinearGradient(
                                colors: [Color.ember.opacity(0.07), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    )
                    .cornerRadius(FDS.Radius.xl)
                    .overlay(
                        RoundedRectangle(cornerRadius: FDS.Radius.xl)
                            .stroke(Color.ember.opacity(0.22), lineWidth: 1)
                    )
                    .forgeCardShadow()
                }
                .buttonStyle(.plain)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .onAppear {
                    withAnimation(FDS.Spring.hero.delay(0.08)) { appeared = true }
                }
            }
        }
    }
}

// MARK: - Daily Trilogy (Strain / Recovery / Sleep)

struct DailyTrilogySection: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var scores: DailyScores? { store.dailyScores }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY TRILOGY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(2)
                    Text("Strain · Recovery · Sleep")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }
                Spacer()
                if let need = scores?.sleep.sleepNeedMinutes, need > 0 {
                    SleepNeedBadge(minutes: need)
                }
            }

            HStack(spacing: 12) {
                TrilogyRingCard(
                    title: "Strain",
                    score: scores?.strain.score ?? store.readiness.overall,
                    color: Color(hex: "F97316"),
                    icon: "bolt.fill",
                    subtitle: scores?.strain.trend.capitalized ?? "—"
                )
                TrilogyRingCard(
                    title: "Recovery",
                    score: scores?.recovery.score ?? store.readiness.recoveryScore,
                    color: Color(hex: "22C55E"),
                    icon: "heart.fill",
                    subtitle: scores?.recovery.hrv.map { "HRV \($0)ms" } ?? "—"
                )
                TrilogyRingCard(
                    title: "Sleep",
                    score: scores?.sleep.score ?? store.readiness.sleepQuality,
                    color: Color(hex: "6366F1"),
                    icon: "moon.zzz.fill",
                    subtitle: sleepHoursLabel
                )
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .forgeCardShadow()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.1)) { appeared = true }
        }
    }

    private var sleepHoursLabel: String {
        guard let minutes = scores?.sleep.totalSleepMinutes, minutes > 0 else { return "—" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}

private struct TrilogyRingCard: View {
    let title: String
    let score: Int
    let color: Color
    let icon: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 6)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color)
                    Text("\(score)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
            }
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.textSecondary)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SleepNeedBadge: View {
    let minutes: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 10))
            Text("Need \(formatNeed(minutes))")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color(hex: "6366F1"))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: "6366F1").opacity(0.12))
        .cornerRadius(FDS.Radius.pill)
    }

    private func formatNeed(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

// MARK: - Today Action Card

struct TodayActionCard: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false

    private var decision: TrainingDecision {
        store.dailyScores?.trainingDecision ?? .activeRest
    }

    private var accent: Color {
        switch decision {
        case .train: return .ember
        case .activeRest: return Color(hex: "F59E0B")
        case .recover: return Color(hex: "6366F1")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: decision.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S ACTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1.5)
                    Text(decision.label)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.textPrimary)
                }
                Spacer()
            }

            Text(actionCopy)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let workout = store.todayWorkout, decision == .train {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.ember)
                    Text(workout.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("\(workout.duration) min")
                        .font(.system(size: 12))
                        .foregroundColor(.textMuted)
                }
                .padding(12)
                .background(Color.surfaceElevated)
                .cornerRadius(FDS.Radius.md)
            }
        }
        .padding(20)
        .background(
            ZStack {
                Color.surface
                LinearGradient(
                    colors: [accent.opacity(0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(FDS.Radius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
        .forgeCardShadow()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.15)) { appeared = true }
        }
    }

    private var actionCopy: String {
        if let brief = store.dataConclusions?.coachingBrief, !brief.isEmpty {
            return brief
        }
        if let note = store.dailyScores?.cycleContext.coachingNote {
            return note
        }
        switch decision {
        case .train:
            return "Recovery and sleep support a hard session. Execute today's plan with intent."
        case .activeRest:
            return "Keep movement light — mobility, zone-2 cardio, or technique work. Protect tomorrow's performance."
        case .recover:
            return "Prioritize sleep, hydration, and down-regulation. Skip max-effort work until markers rebound."
        }
    }
}

// MARK: - Biological Age Card

struct BiologicalAgeCard: View {
    @EnvironmentObject var store: AppStore

    private var bio: BiologicalAge? { store.biologicalAge }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "38BDF8"))
                Text("BIOLOGICAL AGE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.5)
            }

            if let bio {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", bio.biologicalAge))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("yrs")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textMuted)
                }

                HStack(spacing: 6) {
                    Text("Chrono \(bio.chronologicalAge)")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                    DeltaBadge(delta: bio.deltaYears)
                }

                if !bio.drivers.isEmpty {
                    Text(driverLabel(bio.drivers.first ?? ""))
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
            } else {
                Text("—")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.textMuted)
                Text("Connect health data")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func driverLabel(_ key: String) -> String {
        switch key {
        case "strong_hrv": return "Strong HRV pulling age down"
        case "quality_sleep": return "Quality sleep supporting youth markers"
        case "active_lifestyle": return "Active lifestyle offsetting age"
        case "recovery_lag": return "Recovery lag adding biological years"
        case "youthful_markers": return "Markers trending younger than calendar age"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct DeltaBadge: View {
    let delta: Double

    var body: some View {
        let positive = delta > 0
        HStack(spacing: 2) {
            Image(systemName: positive ? "arrow.up" : "arrow.down")
                .font(.system(size: 9, weight: .bold))
            Text(String(format: "%+.1f", delta))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(positive ? Color(hex: "EF4444") : Color(hex: "22C55E"))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((positive ? Color(hex: "EF4444") : Color(hex: "22C55E")).opacity(0.12))
        .cornerRadius(FDS.Radius.pill)
    }
}

// MARK: - Cycle Context Card

struct CycleContextCard: View {
    @EnvironmentObject var store: AppStore

    private var cycle: CycleContext? { store.dailyScores?.cycleContext }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: cycle?.phase.icon ?? "circle.dashed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "EC4899"))
                Text("CYCLE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(1.5)
            }

            if let cycle, cycle.hasData {
                Text(cycle.phase.label)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
                if let day = cycle.dayInCycle {
                    Text("Day \(day)")
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }
                if cycle.recommendRecovery {
                    Label("Recovery focus", systemImage: "heart.text.square")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "EC4899"))
                }
            } else {
                Text("No data")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textMuted)
                Text("Enable cycle tracking in Health")
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Wellness insights row (bio age + cycle)

struct WellnessInsightsRow: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            BiologicalAgeCard()
            if showCycleCard {
                CycleContextCard()
            }
        }
    }

    private var showCycleCard: Bool {
        let gender = store.userProfile.gender
        return gender == .female || store.dailyScores?.cycleContext.hasData == true
    }
}