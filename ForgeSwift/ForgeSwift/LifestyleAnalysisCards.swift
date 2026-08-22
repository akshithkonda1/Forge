import SwiftUI
import UIKit
import HealthKit
import ForgeCore

struct AILifeAnalysisCard: View {
    let metrics: LifestyleMetrics
    var analysis: String? = nil
    var isLive: Bool = false
    @State private var appeared = false
    @State private var expanded = false

    private var rows: [(icon: String, label: String, current: String, optimal: String, status: InsightStatus)] {[
        ("moon.zzz.fill", "Sleep", String(format: "%.1fh avg", metrics.sleepAverage), String(format: "%.0fh target", metrics.sleepTarget), metrics.sleepAverage >= metrics.sleepTarget ? .excellent : metrics.sleepAverage >= metrics.sleepTarget * 0.9 ? .good : .warning),
        ("fork.knife", "Nutrition", "\(Int(metrics.nutritionQuality * 100))% whole foods", "85%+", metrics.nutritionQuality >= 0.85 ? .excellent : metrics.nutritionQuality >= 0.75 ? .good : .warning),
        ("figure.walk", "Movement", "\(metrics.dailySteps.formatted()) steps", "10,000 steps", metrics.dailySteps >= 10000 ? .excellent : metrics.dailySteps >= 8000 ? .good : .warning),
        ("brain.fill", "Stress", metrics.stressLevel.rawValue, "Low", metrics.stressLevel == .low ? .excellent : metrics.stressLevel == .medium ? .warning : .poor),
    ]}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LinearGradient.ember)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("AI Life Analysis")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if analysis != nil { liveBadge }
                    }
                    Text("Behavioral pattern analysis")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.bottom, 20)

            // Insight rows with left accent bar
            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    AnalysisInsightRow(
                        icon: row.icon, label: row.label,
                        current: row.current, optimal: row.optimal, status: row.status
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(0.1 + Double(i) * 0.07), value: appeared)
                }
            }
            .padding(.bottom, 20)

            // Full analysis CTA
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 14))
                    Text(expanded ? "Hide Full Analysis" : "View Full Analysis").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundColor(.ember)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(12)
            }

            if expanded {
                fullAnalysisSection
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }

    private var liveBadge: some View {
        Text(isLive ? "LIVE" : "ARIA")
            .font(.system(size: 8, weight: .black))
            .tracking(0.5)
            .foregroundColor(.ember)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.ember.opacity(0.12))
            .cornerRadius(5)
    }

    @ViewBuilder
    private var fullAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 13)).foregroundColor(.ember)
                Text(isLive ? "ARIA's analysis" : "Summary")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            if let analysis {
                Text(analysis)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Connect ARIA to unlock a personalized breakdown of how your sleep, nutrition, movement, and stress are interacting today.")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

struct AnalysisInsightRow: View {
    let icon: String
    let label: String
    let current: String
    let optimal: String
    let status: InsightStatus

    var body: some View {
        HStack(spacing: 14) {
            // Colored left accent + icon
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(status.color)
                    .frame(width: 3, height: 40)
                    .padding(.trailing, 10)

                ZStack {
                    Circle().fill(status.color.opacity(0.12)).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(status.color)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 5) {
                    Text(current)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(.textMuted)
                    Text(optimal)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            // Status dot with glow
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
                .shadow(color: status.color.opacity(0.6), radius: 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

struct AIRecommendationsCard: View {
    let recommendations: [AIRecommendation]
    @ObservedObject var store: AppStore
    @State private var appeared = false

    private var ariaPrompt: String {
        if let top = recommendations.first {
            return "Based on my lifestyle data, help me act on this: \(top.title). \(top.description)"
        }
        return "Review my lifestyle optimization metrics and suggest one high-impact change for today."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.ember)
                Text("AI Recommendations")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(recommendations.count) active")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(8)
            }

            Button {
                store.openChat(with: ariaPrompt)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Ask ARIA to optimize")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.ember)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            if recommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44)).foregroundColor(.success.opacity(0.6))
                    Text("You're doing great! No new recommendations.")
                        .font(.system(size: 14)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { i, rec in
                        RecommendationCard(recommendation: rec)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(0.05 + Double(i) * 0.08), value: appeared)
                    }
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct RecommendationCard: View {
    let recommendation: AIRecommendation
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 0) {
            // Glowing left border — the signature visual
            RoundedRectangle(cornerRadius: 3)
                .fill(recommendation.impact.color)
                .frame(width: 4)
                .shadow(color: recommendation.impact.color.opacity(0.7), radius: 6)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { expanded.toggle() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: recommendation.category.icon)
                                    .font(.system(size: 11))
                                    .foregroundColor(recommendation.impact.color)
                                Text(recommendation.category.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(recommendation.impact.color)
                                    .tracking(1.5)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text(recommendation.impact.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(recommendation.impact.color)
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.textMuted)
                            }
                        }

                        Text(recommendation.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if expanded {
                            Text(recommendation.description)
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                                .lineSpacing(4)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
        }
        .background(recommendation.impact.color.opacity(0.05))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(recommendation.impact.color.opacity(0.18), lineWidth: 1)
        )
    }
}

struct OptimizationGoalsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false

    // Derived from live HealthKit data (was a hardcoded array).
    private var goals: [(title: String, progress: Double, current: String, target: String, color: Color)] {
        let m = vm.metrics
        let protein = Int(vm.healthStats?.protein ?? 0)
        let mindfulWeek = vm.mindfulMinutesWeek
        let stressProgress: Double = {
            switch m.stressLevel {
            case .low: return 1.0
            case .medium: return 0.6
            case .high: return 0.3
            }
        }()
        return [
            ("Sleep → 8h", min(m.sleepAverage / 8.0, 1.0),
             String(format: "%.1fh avg", m.sleepAverage), "8h", Color(hex: "A855F7")),
            ("Lower stress", stressProgress,
             m.stressLevel.rawValue, "Low", .warning),
            ("Daily protein 180g", min(Double(protein) / 180.0, 1.0),
             "\(protein)g", "180g", .ember),
            ("Mindfulness 70 min/wk", min(Double(mindfulWeek) / 70.0, 1.0),
             "\(mindfulWeek) min", "70 min", .steel),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Optimization Goals")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            VStack(spacing: 12) {
                ForEach(Array(goals.enumerated()), id: \.offset) { i, goal in
                    GoalProgressItem(
                        title: goal.title, progress: goal.progress,
                        current: goal.current, target: goal.target,
                        color: goal.color, appeared: appeared, index: i
                    )
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct GoalProgressItem: View {
    let title: String
    let progress: Double
    let current: String
    let target: String
    let color: Color
    let appeared: Bool
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
            }
            HStack(spacing: 6) {
                Text(current)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10)).foregroundColor(.textMuted)
                Text(target)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }
            // Responsive animated progress bar (fixed hardcoded-points bug)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.borderColor.opacity(0.3))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: appeared ? geo.size.width * CGFloat(progress) : 0)
                        .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.4 + Double(index) * 0.1), value: appeared)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 1))
    }
}
