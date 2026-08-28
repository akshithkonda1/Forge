import SwiftUI
import PhotosUI
import UIKit

/// A quiet fact, not a score to protect — same framing `HomeWinCard` uses for
/// the workout streak. No badge, no glow, no tap that leads nowhere.
struct SleepStreakCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    private var streak: Int { hkService.computeGoodSleepStreak(from: store.sleepData) }

    var body: some View {
        if streak > 0 {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.16)).frame(width: 40, height: 40)
                    Image(systemName: "moon.fill").font(.system(size: 16, weight: .semibold)).foregroundColor(.ember)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streak) night\(streak == 1 ? "" : "s") of good sleep in a row")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("A quiet fact, not a score to protect.")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
            .opacity(appeared ? 1 : 0)
            .accessibilityElement(children: .combine)
            .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
        }
    }
}

/// Tonight's bedtime, straight from the same circadian model
/// `EnergyScheduleCard` already draws its chart from — plus one lazy ARIA
/// sentence explaining why, since the number alone is already live there.
struct AISleepPredictionCard: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appear = false

    private var schedule: EnergySchedule? { EnergySchedule.make(from: store.sleepData) }

    var body: some View {
        if let schedule {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.steel.opacity(0.15)).frame(width: 34, height: 34)
                        Image(systemName: "sparkles").font(.system(size: 14)).foregroundColor(.steel)
                    }
                    Text("Tonight's Bedtime").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(EnergySchedule.clockLabel(schedule.phase.onsetHour))
                        .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(.steel)
                    Text("· dim lights by \(EnergySchedule.clockLabel(schedule.melatoninHour))")
                        .font(.system(size: 13)).foregroundColor(.textTertiary)
                }
                if let note = hkService.aiBedtimeNote {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(schedule.debtHeadline)
                        .font(.system(size: 12)).foregroundColor(.textMuted).lineLimit(2)
                }
            }
            .padding(18)
            .background(Color.surface)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.steel.opacity(0.25), lineWidth: 1))
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
            .onAppear { withAnimation(.easeOut(duration: 0.4).delay(0.1)) { appear = true } }
            .task { await hkService.refreshBedtimeNote(store: store, schedule: schedule) }
        }
    }
}

struct RecoveryTrendsView: View {
    @EnvironmentObject var store: AppStore

    private let mockHRV: [Double] = [44, 46, 52, 48, 41, 55, 50]
    private let mockRHR: [Double] = [62, 60, 58, 61, 64, 57, 59]

            if let evaluation {
                VStack(alignment: .leading, spacing: 4) {
                    Text(evaluation.label).font(.system(size: 13, weight: .semibold)).foregroundColor(evaluation.tint)
                    Text(evaluation.detail).font(.system(size: 12)).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            if let preview = pickedPreview {
                Image(uiImage: preview)
                    .resizable().scaledToFill()
                    .frame(height: 120).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if hkService.isAnalyzingEnvironment {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking at the room…").font(.system(size: 12)).foregroundColor(.textSecondary)
                }
            } else if let assessment = hkService.environmentAssessment {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundColor(.steel)
                    Text(assessment).font(.system(size: 12)).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.steel.opacity(0.08))
                .cornerRadius(10)
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill").font(.system(size: 12))
                    Text(pickedPreview == nil ? "Show ARIA the room" : "Try another photo").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.steel)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.steel.opacity(0.12))
                .cornerRadius(10)
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
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
    @State private var appeared = false

    var goals: [AdaptiveSleepGoal] {
        hkService.computeAdaptiveGoals(from: store.sleepData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "target").font(.system(size: 14)).foregroundColor(.ember)
                Text("Sleep Goals").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            }
            VStack(spacing: 10) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { i, g in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: g.icon).font(.system(size: 12)).foregroundColor(.steel)
                            Text(g.title).font(.system(size: 13, weight: .medium)).foregroundColor(.textPrimary)
                            Spacer()
                            Text(String(format: "%.1f / %.1f %@", g.current, g.target, g.unit))
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.4)).frame(height: 6)
                                Capsule()
                                    .fill(g.current >= g.target ? Color.success : Color.steel)
                                    .frame(width: appeared ? geo.size.width * CGFloat(min(g.current / g.target, 1.0)) : 0, height: 6)
                                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3 + Double(i) * 0.1), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(12).background(Color.surfaceElevated).cornerRadius(12)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.1), value: appeared)
                }
            }
            if let note = hkService.aiGoalsNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundColor(.ember)
                    Text(note).font(.system(size: 12)).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ember.opacity(0.08))
                .cornerRadius(10)
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
        .task { await hkService.refreshGoalsNote(store: store, goals: goals) }
    }
}

struct AISmartRecommendationsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var hkService: HealthKitSleepService
    @State private var appeared = false

    var recs: [SleepRecommendation] {
        hkService.chronotypeRecommendations(debt: hkService.computeSleepDebt(from: store.sleepData))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Recommendations").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
            VStack(spacing: 10) {
                ForEach(Array(recs.enumerated()), id: \.element.id) { i, rec in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(Color.steel.opacity(0.12)).frame(width: 38, height: 38)
                            Image(systemName: rec.icon).font(.system(size: 14)).foregroundColor(.steel)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(rec.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                                Spacer()
                                Text(rec.priority)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(rec.priority == "High" ? .ember : .warning)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background((rec.priority == "High" ? Color.ember : Color.warning).opacity(0.12))
                                    .cornerRadius(6)
                            }
                            Text(rec.description).font(.system(size: 12)).foregroundColor(.textSecondary).lineLimit(2)
                        }
                    }
                    .padding(12).background(Color.surfaceElevated).cornerRadius(12)
                    .opacity(appeared ? 1 : 0).offset(x: appeared ? 0 : -10)
                    .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.08), value: appeared)
                }
            }
            if let note = hkService.aiRecommendationsNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundColor(.steel)
                    Text(note).font(.system(size: 12)).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.steel.opacity(0.08))
                .cornerRadius(10)
            }
        }
        .padding(18).background(Color.surface).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
        .task {
            let debt = hkService.computeSleepDebt(from: store.sleepData)
            await hkService.refreshRecommendationsNote(store: store, debt: debt)
        }
    }
}

struct SleepQuickActionsBar: View {
    @State private var appeared = false
    let onAITap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            QuickActionButton(icon: "moon.fill",                  title: "Tips",   color: .steel,   action: {})
            QuickActionButton(icon: "bell.badge.fill",            title: "Alarm",  color: .ember,   action: {})
            QuickActionButton(icon: "brain.head.profile",         title: "ARIA",   color: .steel,   action: onAITap)
            QuickActionButton(icon: "chart.line.uptrend.xyaxis",  title: "Trends", color: Color(hex: "6366F1"), action: {})
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 14, y: 5)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 20)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3)) { appeared = true } }
    }
}

struct QuickActionButton: View {
    let icon: String; let title: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.14)).frame(width: 44, height: 44)
                    Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundColor(color)
                }
                Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
