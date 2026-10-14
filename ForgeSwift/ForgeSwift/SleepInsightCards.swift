import SwiftUI
import PhotosUI
import UIKit
import ForgeCore

struct SleepMorningSummaryCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    private var summary: SleepMorningSummary {
        let last = SleepData.lastNight(in: store.sleepData)
        let durations = Array(store.sleepData.map(\.totalHours).reversed())
        let estimated = CircadianRhythm.sleepNeedHours(fromAsleepHours: durations)
        let stretch = CircadianRhythm.sleepDebtHours(asleepHours: durations, need: estimated)
        let need = SleepNeedParts.make(
            estimatedBaseline: estimated,
            overrideBaseline: SleepNeedBaselineStore.load() ?? hkService.userProfile.sleepNeedBaselineHours,
            debtHours: stretch
        )
        let coach = SleepBedtimeCoach.make(
            from: store.sleepData,
            lowEnergyDay: store.readiness.overall < 60
        )
        return SleepMorningSummary.make(
            lastNightHours: last?.totalHours,
            lastNightAwakeMinutes: Double(last?.awakeMinutes ?? 0),
            scoredNightCount: store.sleepData.count,
            bedtimeLabel: last == nil ? nil : coach.bedtimeLabel,
            need: need
        )
    }

    var body: some View {
        let card = summary
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            ForgeSectionHeader(
                title: "This morning",
                subtitle: card.calibration.caption
            )
            HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                Text(card.hoursLabel)
                    .font(ForgeType.heroScore)
                    .foregroundColor(.textPrimary)
                    .monospacedDigit()
                Text("asleep")
                    .font(ForgeType.body)
                    .foregroundColor(.textSecondary)
                Spacer()
                if let score = card.visibleScore {
                    Text("\(score)")
                        .font(ForgeType.metric)
                        .foregroundColor(.steel)
                        .monospacedDigit()
                        .accessibilityLabel("Sleep score \(score) of 100")
                }
            }
            Text(card.contextLine)
                .font(ForgeType.body)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.nextStep)
                .font(ForgeType.headline)
                .foregroundColor(.ember)
                .fixedSize(horizontal: false, vertical: true)
            if card.calibration.isReady, let parts = card.published?.parts {
                HStack(spacing: FDS.Spacing.sm) {
                    ForEach(parts, id: \.name) { part in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(part.weight)%")
                                .font(ForgeType.micro)
                                .foregroundColor(.textTertiary)
                            Text("\(part.value)")
                                .font(ForgeType.caption)
                                .foregroundColor(.textPrimary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("\(part.name), weight \(part.weight) percent, \(part.value)")
                    }
                }
            }
            Text(card.need.whyLines.joined(separator: " · "))
                .font(ForgeType.caption)
                .foregroundColor(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FDS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .ember)
        .accessibilityElement(children: .combine)
    }
}

struct SleepFeelingCheckIn: View {
    @EnvironmentObject var store: AppStore
    @State private var picked: SleepFeeling?

    private var dateKey: String? { SleepData.lastNight(in: store.sleepData)?.date }

    var body: some View {
        if let dateKey {
            VStack(alignment: .leading, spacing: FDS.Spacing.md) {
                Text("How did you feel?")
                    .font(ForgeType.caption)
                    .foregroundColor(.textTertiary)
                HStack(spacing: FDS.Spacing.sm) {
                    ForEach(SleepFeeling.allCases, id: \.self) { feeling in
                        Button {
                            FDS.haptic(.press)
                            SleepFeelingStore.save(feeling, on: dateKey)
                            picked = feeling
                        } label: {
                            Text(feeling.label)
                                .font(ForgeType.caption)
                                .foregroundColor(picked == feeling ? .white : .textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: ForgeDS.minTap)
                                .background((picked == feeling ? Color.steel : Color.white).opacity(picked == feeling ? 0.9 : 0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(feeling.label)
                        .accessibilityAddTraits(picked == feeling ? .isSelected : [])
                    }
                }
            }
            .padding(FDS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .steel)
            .onAppear { picked = SleepFeelingStore.feeling(on: dateKey) }
        }
    }
}

/// A quiet fact, not a score to protect — same framing `HomeWinCard` uses for
/// the workout streak. No badge, no glow, no tap that leads nowhere.
struct SleepStreakCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var streak: Int { hkService.computeGoodSleepStreak(from: store.sleepData) }

    var body: some View {
        if streak > 0 {
            HStack(spacing: FDS.Spacing.lg) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.16)).frame(width: 40, height: 40)
                    Image(systemName: "moon.fill").font(.system(size: 16, weight: .semibold)).foregroundColor(.ember)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streak) night\(streak == 1 ? "" : "s") of good sleep in a row")
                        .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                        .foregroundColor(.textPrimary)
                    Text("A quiet fact, not a score to protect.")
                        .font(ForgeType.caption)
                        .foregroundColor(.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(FDS.Spacing.lg)
            .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .ember)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .accessibilityElement(children: .combine)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.easeOut(duration: 0.4)) { appeared = true }
                }
            }
        }
    }
}

/// Tonight's bedtime, straight from the same circadian model
/// `EnergyScheduleCard` already draws its chart from — plus one lazy ARIA
/// sentence explaining why, since the number alone is already live there.
struct AISleepPredictionCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false

    private var schedule: EnergySchedule? { EnergySchedule.make(from: store.sleepData) }

    var body: some View {
        if let schedule {
            VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
                HStack(spacing: FDS.Spacing.md) {
                    ZStack {
                        Circle().fill(Color.steel.opacity(0.15)).frame(width: 34, height: 34)
                        Image(systemName: "sparkles").font(.system(size: 14)).foregroundColor(.steel)
                    }
                    Text("Tonight's Bedtime").font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                    Text(EnergySchedule.clockLabel(schedule.phase.onsetHour))
                        .font(ForgeType.display).foregroundColor(.steel)
                    Text("· dim lights by \(EnergySchedule.clockLabel(schedule.melatoninHour))")
                        .font(ForgeType.body).foregroundColor(.textTertiary)
                }
                if let note = store.remoteSleepInsight {
                    Text(note)
                        .font(ForgeType.caption)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let note = hkService.aiBedtimeNote {
                    Text(note)
                        .font(ForgeType.caption)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(schedule.debtHeadline)
                        .font(ForgeType.caption).foregroundColor(.textMuted).lineLimit(2)
                }
            }
            .padding(FDS.Spacing.lg)
            .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .steel)
            .opacity(appear || reduceMotion ? 1 : 0)
            .offset(y: appear || reduceMotion ? 0 : 10)
            .onAppear {
                if reduceMotion {
                    appear = true
                } else {
                    withAnimation(.easeOut(duration: 0.4).delay(0.1)) { appear = true }
                }
            }
            .task {
                await hkService.refreshBedtimeNote(store: store, schedule: schedule)
                if store.remoteSleepInsight == nil {
                    await store.refreshCoachInsightsIfNeeded()
                }
            }
        }
    }
}

/// Room-photo environment check — a real photo goes to `/sleep/environment-check`
/// (`HealthKitSleepService.analyzeSleepEnvironment`), which only ever reports what
/// the model actually saw. No local "evaluation" heuristic here on purpose: there
/// is no sensor data to derive a light/noise/clutter read from, and inventing one
/// would be exactly the fabricated reading `analyzeSleepEnvironment`'s own doc
/// comment rules out.
struct AISleepEnvironmentView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedPreview: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: "camera.fill").font(.system(size: 14)).foregroundColor(.steel)
                Text("Sleep Environment").font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
            }

            if let preview = pickedPreview {
                Image(uiImage: preview)
                    .resizable().scaledToFill()
                    .frame(height: 120).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md))
            }

            if hkService.isAnalyzingEnvironment {
                HStack(spacing: FDS.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Looking at the room…").font(ForgeType.caption).foregroundColor(.textSecondary)
                }
            } else if let error = hkService.environmentCheckError {
                HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundColor(.warning)
                    Text(error).font(ForgeType.caption).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(FDS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.warning.opacity(0.08))
                .cornerRadius(FDS.Radius.sm)
            } else if let assessment = hkService.environmentAssessment {
                HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundColor(.steel)
                    Text(assessment).font(ForgeType.caption).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(FDS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.steel.opacity(0.08))
                .cornerRadius(FDS.Radius.sm)
            } else {
                Text(SleepLifestyleCopy.environmentHint)
                    .font(ForgeType.caption).foregroundColor(.textMuted).lineLimit(3)
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: FDS.Spacing.sm) {
                    Image(systemName: "camera.fill").font(.system(size: 12))
                    Text(pickedPreview == nil ? "Show ARIA the room" : "Try another photo").font(FDS.TypeScale.Dynamic.caption)
                }
                .foregroundColor(.steel)
                .padding(.horizontal, FDS.Spacing.md).padding(.vertical, FDS.Spacing.sm)
                .background(Color.steel.opacity(0.12))
                .cornerRadius(FDS.Radius.sm)
            }
        }
        .padding(FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .aurora)
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                pickedPreview = image
                hkService.environmentAssessment = nil
                await hkService.analyzeSleepEnvironment(image: image)
            }
        }
    }
}

struct AIPersonalizedGoalsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var goals: [AdaptiveSleepGoal] {
        hkService.computeAdaptiveGoals(from: store.sleepData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: "target").font(.system(size: 14)).foregroundColor(.ember)
                Text("Sleep Goals").font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
            }
            VStack(spacing: FDS.Spacing.md) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { i, g in
                    VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                        HStack {
                            Image(systemName: g.icon).font(.system(size: 12)).foregroundColor(.steel)
                            Text(g.title).font(FDS.TypeScale.Dynamic.caption).foregroundColor(.textPrimary)
                            Spacer()
                            Text(String(format: "%.1f / %.1f %@", g.current, g.target, g.unit))
                                .font(FDS.TypeScale.Dynamic.caption).foregroundColor(.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.4)).frame(height: 6)
                                Capsule()
                                    .fill(g.current >= g.target ? Color.success : Color.steel)
                                    .frame(width: (appeared || reduceMotion) ? geo.size.width * CGFloat(min(g.current / max(0.01, g.target), 1.0)) : 0, height: 6)
                                    .animation(reduceMotion ? nil : .spring(response: 1.0, dampingFraction: 0.7).delay(0.3 + Double(i) * 0.1), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(FDS.Spacing.md).forgeInsetTile(radius: FDS.Radius.md)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(i) * 0.1), value: appeared)
                }
            }
            if let note = hkService.aiGoalsNote {
                HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundColor(.ember)
                    Text(note).font(ForgeType.caption).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(FDS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ember.opacity(0.08))
                .cornerRadius(FDS.Radius.sm)
            }
        }
        .padding(FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .aurora)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
        }
        .task { await hkService.refreshGoalsNote(store: store, goals: goals) }
    }
}

struct AISmartRecommendationsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var recs: [SleepRecommendation] {
        hkService.chronotypeRecommendations(debt: hkService.computeSleepDebt(from: store.sleepData))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            Text("Smart Recommendations").font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
            VStack(spacing: FDS.Spacing.md) {
                ForEach(Array(recs.enumerated()), id: \.element.id) { i, rec in
                    HStack(alignment: .top, spacing: FDS.Spacing.md) {
                        ZStack {
                            Circle().fill(Color.steel.opacity(0.12)).frame(width: 38, height: 38)
                            Image(systemName: rec.icon).font(.system(size: 14)).foregroundColor(.steel)
                        }
                        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                            HStack {
                                Text(rec.title).font(FDS.TypeScale.Dynamic.caption).foregroundColor(.textPrimary)
                                Spacer()
                                Text(rec.priority)
                                    .font(FDS.TypeScale.Dynamic.micro)
                                    .foregroundColor(rec.priority == "High" ? .ember : .warning)
                                    .padding(.horizontal, FDS.Spacing.sm).padding(.vertical, FDS.Spacing.xs)
                                    .background((rec.priority == "High" ? Color.ember : Color.warning).opacity(0.12))
                                    .cornerRadius(FDS.Radius.xs)
                            }
                            Text(rec.description).font(ForgeType.caption).foregroundColor(.textSecondary).lineLimit(2)
                        }
                    }
                    .padding(FDS.Spacing.md).forgeInsetTile(radius: FDS.Radius.md)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .offset(x: appeared || reduceMotion ? 0 : -10)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(i) * 0.08), value: appeared)
                }
            }
            if let note = hkService.aiRecommendationsNote {
                HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundColor(.steel)
                    Text(note).font(ForgeType.caption).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(FDS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.steel.opacity(0.08))
                .cornerRadius(FDS.Radius.sm)
            }
        }
        .padding(FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: .aurora)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
        }
        .task {
            let debt = hkService.computeSleepDebt(from: store.sleepData)
            await hkService.refreshRecommendationsNote(store: store, debt: debt)
        }
    }
}
