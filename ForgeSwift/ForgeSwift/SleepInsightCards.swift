import SwiftUI
import PhotosUI
import UIKit

/// An ARIA sentence inside a card: a small sparkle plus the note in body
/// type, in Home's inner well. Sentences wrap, they never truncate.
private struct SleepAriaNote: View {
    let text: String
    var tint: Color = .aurora

    var body: some View {
        HStack(alignment: .top, spacing: FDS.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .forgeWell()
        .accessibilityElement(children: .combine)
    }
}

/// A quiet fact, not a score to protect — same framing `HomeWinCard` uses for
/// the workout streak. No badge, no glow, no tap that leads nowhere.
struct SleepStreakCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    private var streak: Int { hkService.computeGoodSleepStreak(from: store.sleepData) }

    var body: some View {
        if streak > 0 {
            ForgeListRow(
                icon: "moon.fill",
                iconColor: .steel,
                title: "\(streak) night\(streak == 1 ? "" : "s") of good sleep in a row",
                subtitle: "A quiet fact, not a score to protect."
            )
            .forgeContentCard(tint: .steel)
        }
    }
}

/// Tonight's bedtime, straight from the same circadian model
/// `EnergyScheduleCard` already draws its chart from — plus one lazy ARIA
/// sentence explaining why, since the number alone is already live there.
struct AISleepPredictionCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    private var schedule: EnergySchedule? { EnergySchedule.make(from: store.sleepData) }

    var body: some View {
        if let schedule {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                ForgeCardHeader("Tonight's Bedtime", tint: .steel)
                bedtimeLead(schedule)
                noteText(schedule)
            }
            .forgeContentCard(tint: .steel)
            .task {
                await hkService.refreshBedtimeNote(store: store, schedule: schedule)
                if store.remoteSleepInsight == nil {
                    await store.refreshCoachInsightsIfNeeded()
                }
            }
        }
    }

    private func bedtimeLead(_ schedule: EnergySchedule) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(EnergySchedule.clockLabel(schedule.phase.onsetHour))
                .font(HomeType.metric)
                .foregroundStyle(Color.steel)
                .monospacedDigit()
                .forgeSingleLine()
                .contentTransition(.numericText())
            Text("Dim lights by \(EnergySchedule.clockLabel(schedule.melatoninHour))")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func noteText(_ schedule: EnergySchedule) -> some View {
        if let note = store.remoteSleepInsight {
            noteSentence(note, color: .textSecondary)
        } else if let note = hkService.aiBedtimeNote {
            noteSentence(note, color: .textSecondary)
        } else {
            noteSentence(schedule.debtHeadline, color: .textTertiary)
        }
    }

    private func noteSentence(_ text: String, color: Color) -> some View {
        Text(text)
            .font(HomeType.body)
            .foregroundStyle(color)
            .forgeWrapping()
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
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Sleep Environment", tint: .steel) {
                if hkService.isAnalyzingEnvironment {
                    ProgressView().controlSize(.mini)
                }
            }

            if let preview = pickedPreview {
                Image(uiImage: preview)
                    .resizable().scaledToFill()
                    .frame(height: 120).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous))
                    .accessibilityLabel("Photo of your room")
            }

            statusBody

            PhotosPicker(selection: $pickerItem, matching: .images) {
                pickerLabel
            }
        }
        .forgeContentCard(tint: .steel)
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

    @ViewBuilder
    private var statusBody: some View {
        if hkService.isAnalyzingEnvironment {
            ForgeSkeletonWell(message: "Looking at the room…", minHeight: 56)
        } else if let error = hkService.environmentCheckError {
            HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.warning)
                    .accessibilityHidden(true)
                Text(error)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                Spacer(minLength: 0)
            }
            .forgeWell()
            .accessibilityElement(children: .combine)
        } else if let assessment = hkService.environmentAssessment {
            SleepAriaNote(text: assessment, tint: .steel)
        } else {
            Text(SleepLifestyleCopy.environmentHint)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }

    private var pickerLabel: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: "camera.fill")
                .font(.system(size: ForgeUX.icon, weight: .semibold))
                .accessibilityHidden(true)
            Text(pickedPreview == nil ? "Show ARIA the room" : "Try another photo")
                .font(HomeType.label)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
        }
        .foregroundStyle(Color.steel)
        .frame(maxWidth: .infinity)
        .frame(minHeight: ForgeUX.minTap)
        .padding(.horizontal, FDS.Spacing.lg)
        .background(Color.steel.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                .stroke(Color.steel.opacity(0.28), lineWidth: ForgeUX.hairline)
        )
    }
}

struct AIPersonalizedGoalsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    var goals: [AdaptiveSleepGoal] {
        hkService.computeAdaptiveGoals(from: store.sleepData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Sleep Goals", tint: .steel)
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(goals) { g in
                    goalRow(g)
                }
            }
            if let note = hkService.aiGoalsNote {
                SleepAriaNote(text: note)
            }
        }
        .forgeContentCard(tint: .steel)
        .task { await hkService.refreshGoalsNote(store: store, goals: goals) }
    }

    private func goalRow(_ g: AdaptiveSleepGoal) -> some View {
        let met = g.current >= g.target
        let fraction = g.current / max(0.01, g.target)
        return VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeMetricRow(
                label: g.title,
                value: String(format: "%.1f / %.1f", g.current, g.target),
                unit: g.unit,
                tint: met ? Color.vitality : Color.steel
            )
            ForgeProgressBar(fraction: fraction, tint: met ? Color.vitality : Color.steel)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AISmartRecommendationsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService

    var recs: [SleepRecommendation] {
        hkService.chronotypeRecommendations(debt: hkService.computeSleepDebt(from: store.sleepData))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Smart Recommendations", tint: .steel)
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(recs) { rec in
                    recommendationRow(rec)
                }
            }
            if let note = hkService.aiRecommendationsNote {
                SleepAriaNote(text: note, tint: .steel)
            }
        }
        .forgeContentCard(tint: .steel)
        .task {
            let debt = hkService.computeSleepDebt(from: store.sleepData)
            await hkService.refreshRecommendationsNote(store: store, debt: debt)
        }
    }

    private func recommendationRow(_ rec: SleepRecommendation) -> some View {
        let priorityColor: Color = rec.priority == "High" ? Color.steel : Color.amber
        return HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: rec.icon, tint: .steel)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(rec.title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(rec.description)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                ForgeChip(label: rec.priority, energy: priorityColor, selected: true)
                    .accessibilityLabel("\(rec.priority) priority")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
