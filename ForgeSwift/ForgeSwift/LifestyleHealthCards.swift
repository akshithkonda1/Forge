import SwiftUI
import Charts
import HealthKit
import ForgeCore

struct LiveHealthDashboard: View {
    let stats: DailyHealthStats
    let trends: [WeeklyHealthTrend]
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with live indicator
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.success.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [.success, .ember], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Live Health Data")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        // Pulsing live indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.success)
                                .frame(width: 6, height: 6)
                                .overlay(
                                    Circle()
                                        .stroke(Color.success.opacity(0.3), lineWidth: 2)
                                        .scaleEffect(appeared ? 1.5 : 1)
                                        .opacity(appeared ? 0 : 1)
                                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: appeared)
                                )
                            Text("LIVE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.success)
                                .tracking(1)
                        }
                    }
                    Text("Powered by Apple Health")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.bottom, 4)
            
            // Today's Key Metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                HealthMetricTile(
                    icon: "figure.walk",
                    label: "Steps",
                    value: "\(stats.steps.formatted())",
                    target: "10,000",
                    progress: Double(stats.steps) / 10000.0,
                    color: .steel,
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "flame.fill",
                    label: "Active Cal",
                    value: "\(stats.activeCalories)",
                    target: "600",
                    progress: Double(stats.activeCalories) / 600.0,
                    color: .ember,
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "moon.zzz.fill",
                    label: "Sleep",
                    value: String(format: "%.1fh", stats.sleepHours),
                    target: "8h",
                    progress: stats.sleepHours / 8.0,
                    color: Color(hex: "A855F7"),
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: "\(Int(stats.hrv))",
                    target: "50+",
                    progress: stats.hrv / 50.0,
                    color: .success,
                    appeared: appeared
                )

                // Cardio fitness — surfaced from HealthKit, previously unused
                if stats.vo2Max > 0 {
                    HealthMetricTile(
                        icon: "lungs.fill",
                        label: "VO₂ Max",
                        value: String(format: "%.0f", stats.vo2Max),
                        target: "50",
                        progress: stats.vo2Max / 50.0,
                        color: Color(hex: "FF6B9D"),
                        appeared: appeared
                    )
                }

                if stats.exerciseMinutes > 0 {
                    HealthMetricTile(
                        icon: "figure.run",
                        label: "Exercise",
                        value: "\(Int(stats.exerciseMinutes))m",
                        target: "30m",
                        progress: stats.exerciseMinutes / 30.0,
                        color: Color(hex: "FFB84D"),
                        appeared: appeared
                    )
                }
            }

            // Weekly Trend Chart (Swift Charts — interactive, multi-metric)
            if !trends.isEmpty {
                WeeklyTrendChart(trends: trends)
            }
        }
        .padding(22)
        .forgeGlassCard(cornerRadius: 22, accent: .success)
        .onAppear { appeared = true }
    }
}

private enum TrendMetric: String, CaseIterable, Identifiable {
    case steps = "Steps"
    case activeCalories = "Active"
    case sleep = "Sleep"
    case hrv = "HRV"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .steps:          return .steel
        case .activeCalories: return .ember
        case .sleep:          return Color(hex: "A855F7")
        case .hrv:            return .success
        }
    }

    func value(_ t: WeeklyHealthTrend) -> Double {
        switch self {
        case .steps:          return Double(t.steps)
        case .activeCalories: return Double(t.activeCalories)
        case .sleep:          return t.sleepHours
        case .hrv:            return t.avgHRV
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .steps:          return Int(v).formatted()
        case .activeCalories: return "\(Int(v)) cal"
        case .sleep:          return String(format: "%.1f h", v)
        case .hrv:            return "\(Int(v)) ms"
        }
    }
}

/// Interactive 7-day chart replacing the old steps-only sparkline. Toggles between
/// Steps / Active Cal / Sleep / HRV and supports tap-to-read on any day.
struct WeeklyTrendChart: View {
    let trends: [WeeklyHealthTrend]
    @State private var metric: TrendMetric = .steps
    @State private var selectedDate: Date?

    private var selectedTrend: WeeklyHealthTrend? {
        guard let selectedDate else { return nil }
        return trends.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("7-Day Trends")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                if let t = selectedTrend {
                    Text("\(t.date.formatted(.dateTime.weekday(.abbreviated))) · \(metric.format(metric.value(t)))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(metric.color)
                        .transition(.opacity)
                }
            }

            Picker("Metric", selection: $metric) {
                ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Chart(trends) { t in
                BarMark(
                    x: .value("Day", t.date, unit: .day),
                    y: .value(metric.rawValue, metric.value(t))
                )
                .foregroundStyle(metric.color.gradient)
                .cornerRadius(5)
                .opacity(selectedTrend == nil || selectedTrend?.id == t.id ? 1 : 0.35)
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .frame(height: 150)
            .animation(.easeInOut(duration: 0.25), value: metric)
        }
        .padding(.top, 8)
    }
}

struct HealthMetricTile: View {
    let icon: String
    let label: String
    let value: String
    let target: String
    let progress: Double
    let color: Color
    let appeared: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("/ \(target)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Spacer()
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.borderColor.opacity(0.3))
                    Capsule()
                        .fill(color)
                        .frame(width: appeared ? geo.size.width * CGFloat(min(progress, 1.0)) : 0)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: appeared)
                }
            }
            .frame(height: 4)
        }
        .padding(14)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

struct RecoveryMetricsCard: View {
    let stats: DailyHealthStats
    @State private var appeared = false
    
    var recoveryScore: Int {
        var score = 0
        
        // HRV component (40% weight)
        let hrvScore = min(Int(stats.hrv * 1.5), 100)
        score += Int(Double(hrvScore) * 0.4)
        
        // Resting HR component (30% weight)
        let hrScore = stats.restingHeartRate > 0 ? max(100 - Int((stats.restingHeartRate - 60) * 2), 0) : 70
        score += Int(Double(hrScore) * 0.3)
        
        // Sleep component (30% weight)
        let sleepScore = Int((stats.sleepHours / 8.0) * 100)
        score += Int(Double(sleepScore) * 0.3)
        
        return min(score, 100)
    }
    
    var recoveryStatus: (label: String, color: Color) {
        switch recoveryScore {
        case 80...: return ("Excellent", .success)
        case 60..<80: return ("Good", .steel)
        case 40..<60: return ("Moderate", .warning)
        default: return ("Low", .danger)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(recoveryStatus.color.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(recoveryStatus.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recovery Status")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(recoveryStatus.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(recoveryStatus.color)
                }
                Spacer()
                
                // Recovery score ring
                ZStack {
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), lineWidth: 8)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: appeared ? CGFloat(recoveryScore) / 100 : 0)
                        .stroke(recoveryStatus.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.2), value: appeared)
                    
                    Text("\(recoveryScore)")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.textPrimary)
                }
            }
            .padding(.bottom, 20)
            
            // Recovery metrics grid
            VStack(spacing: 12) {
                RecoveryMetricRow(
                    icon: "waveform.path.ecg",
                    label: "Heart Rate Variability",
                    value: "\(Int(stats.hrv)) ms",
                    status: stats.hrv > 50 ? "Optimal" : stats.hrv > 30 ? "Good" : "Low",
                    color: stats.hrv > 50 ? .success : stats.hrv > 30 ? .warning : .danger
                )
                
                RecoveryMetricRow(
                    icon: "heart.fill",
                    label: "Resting Heart Rate",
                    value: "\(Int(stats.restingHeartRate)) bpm",
                    status: stats.restingHeartRate < 60 ? "Excellent" : stats.restingHeartRate < 70 ? "Good" : "Elevated",
                    color: stats.restingHeartRate < 60 ? .success : stats.restingHeartRate < 70 ? .steel : .warning
                )
                
                RecoveryMetricRow(
                    icon: "bed.double.fill",
                    label: "Sleep Duration",
                    value: String(format: "%.1f hours", stats.sleepHours),
                    status: stats.sleepHours >= 8 ? "Optimal" : stats.sleepHours >= 7 ? "Good" : "Low",
                    color: stats.sleepHours >= 8 ? .success : stats.sleepHours >= 7 ? .steel : .warning
                )
            }
            
            Divider().background(Color.borderColor.opacity(0.4)).padding(.vertical, 16)
            
            // Training readiness
            HStack(spacing: 12) {
                Image(systemName: recoveryScore > 70 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(recoveryScore > 70 ? .success : .warning)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(recoveryScore > 70 ? "Ready to Train" : "Consider Active Recovery")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(recoveryScore > 70 
                         ? "Your body is primed for a hard session"
                         : "Focus on mobility, stretching, or light cardio")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(3)
                }
            }
            .padding(14)
            .background(recoveryStatus.color.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(recoveryStatus.color.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(22)
        .forgeGlassCard(cornerRadius: 22, accent: .vitality)
        .onAppear { appeared = true }
    }
}

struct RecoveryMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            
            Spacer()
            
            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(color.opacity(0.12))
                .cornerRadius(8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

struct MultiArcQOLCard: View {
    let metrics: LifestyleMetrics
    @State private var appeared = false

    private var snapshot: QualityOfLifeLivingStore.Snapshot? {
        QualityOfLifeLivingStore.load()
    }

    private var pillarArcs: [(label: String, value: Int, color: Color, radius: CGFloat)] {
        let colors: [Color] = [
            Color(hex: "A855F7"), .success, Color(hex: "FFB84D"),
            Color(hex: "4A9EFF"), .ember, .steel, Color(hex: "F472B6"),
        ]
        let radii: [CGFloat] = [102, 88, 74, 60, 46, 32, 18]
        let snap = snapshot
        return QualityOfLifePillar.allCases.enumerated().map { index, pillar in
            let value = snap?.pillarScores[pillar.rawValue]
                ?? legacyProjection(for: pillar)
            return (pillar.title, value, colors[index % colors.count], radii[index % radii.count])
        }
    }

    private func legacyProjection(for pillar: QualityOfLifePillar) -> Int {
        switch pillar {
        case .sleep: return metrics.sleepQuality
        case .activity: return metrics.physicalHealth
        case .nutrition: return metrics.nutritionScore
        case .hydration: return metrics.physicalHealth
        case .vitals: return metrics.energyLevels
        case .mind: return metrics.mentalWellbeing
        case .social: return metrics.mentalWellbeing
        }
    }

    var body: some View {
        let arcs = pillarArcs
        let band = snapshot?.qualityBand ?? QualityOfLifeBand(score: metrics.qualityOfLifeScore)
        VStack(spacing: 0) {
            HStack {
                Text("QUALITY OF LIFE")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(2.5)
                Spacer()
                Text(band.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(band.color)
            }
            .padding(.bottom, 28)

            ZStack {
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                }

                ForEach(Array(arcs.enumerated()), id: \.offset) { i, arc in
                    let progress = appeared ? CGFloat(max(0, min(100, arc.value))) / 100 : 0
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(arc.color.opacity(0.3), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(arc.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: arc.color.opacity(0.35), radius: 5)
                        .animation(.spring(response: 1.4, dampingFraction: 0.68).delay(0.25 + Double(i) * 0.08), value: appeared)
                }

                VStack(spacing: 3) {
                    Text("\(metrics.qualityOfLifeScore)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("QOL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1)
                }
            }
            .frame(height: 230)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    ArcLegendItem(label: arc.label, value: arc.value, color: arc.color)
                }
            }

            if let snap = snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    if !snap.drivers.isEmpty {
                        Text(band == .thriving
                             ? "Holding you up: \(snap.drivers.joined(separator: " · "))"
                             : "Pulling the grade: \(snap.drivers.joined(separator: " · "))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    if !snap.missingPillars.isEmpty {
                        Text("Still unmeasured: \(snap.missingPillars.prefix(3).joined(separator: ", "))")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textMuted)
                    }
                    if !snap.coaching.isEmpty {
                        Text(snap.coaching)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
            }
        }
        .padding(24)
        .forgeGlassCard(cornerRadius: 24, accent: .success)
        .onAppear { appeared = true }
    }
}

struct ArcLegendItem: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 3)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

enum AgingVendorStore {
    static var ages: [AgingVendorAge] = []

    static func replaceAll(_ incoming: [AgingVendorAge]) {
        ages = incoming
    }

    static func ingest(metricType: String, years: Double, source: String, confidence: Double = 0.85) {
        guard let age = AgingVendorAge(metricType: metricType, years: years, source: source, confidence: confidence) else {
            return
        }
        ages.removeAll { $0.kind == age.kind && $0.source.caseInsensitiveCompare(age.source) == .orderedSame }
        ages.append(age)
    }

    static func ingest(metrics: [CloudHealthMetric]) {
        for metric in metrics {
            ingest(metricType: metric.metricType, years: metric.value, source: metric.source)
        }
    }
}

enum AgingBridge {
    static func snapshot(
        age: Int?,
        sexFemale: Bool?,
        stats: DailyHealthStats?,
        vendorAges: [AgingVendorAge]? = nil
    ) -> AgingSnapshot {
        AgingSnapshot.evaluate(
            chronologicalAge: age.map(Double.init),
            sexFemale: sexFemale,
            vo2Max: stats.flatMap { $0.vo2Max > 0 ? $0.vo2Max : nil },
            hrv: stats.flatMap { $0.hrv > 0 ? $0.hrv : nil },
            restingHR: stats.flatMap { $0.restingHeartRate > 0 ? $0.restingHeartRate : nil },
            sleepHours: stats.flatMap { $0.sleepHours > 0 ? $0.sleepHours : nil },
            vendorAges: vendorAges ?? AgingVendorStore.ages
        )
    }
}

struct BiologicalAgeCard: View {
    let snapshot: AgingSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tone.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(tone)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Training age")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("Calendar vs how the body is showing up")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }

            if snapshot.showsOnTrain {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    ageColumn(title: "Calendar", value: snapshot.chronologicalAge)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textMuted)
                    ageColumn(
                        title: "Training",
                        value: snapshot.confidence > 0.25 ? snapshot.biologicalAge : nil,
                        emphasis: true
                    )
                    Spacer()
                }

                if snapshot.hasComparison, snapshot.confidence > 0.25 {
                    GeometryReader { geo in
                        let width = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.surfaceElevated).frame(height: 8)
                            Capsule()
                                .fill(tone)
                                .frame(width: max(8, width * barFraction), height: 8)
                        }
                    }
                    .frame(height: 8)
                }

                Text(snapshot.comparisonLine)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)

                if !snapshot.trainingHint.isEmpty {
                    Text(snapshot.trainingHint)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(4)
                }

                if AgingNorms.webConfirmed {
                    Text("Cardio norms confirmed from a public fitness page.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                }

                if !snapshot.components.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(snapshot.components.prefix(4).enumerated()), id: \.offset) { _, component in
                            HStack {
                                Text(component.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                Text(component.source)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                                Spacer()
                                Text("\(Int(component.years.rounded()))")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.textPrimary)
                            }
                        }
                    }
                }

                Text("Lifestyle estimate from the signals Forge already has — not a medical biological age.")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            } else {
                Text("Add your age in You, then ARIA can compare calendar age with training age from VO₂, HRV, resting heart rate, and sleep.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(tone.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.comparisonLine.isEmpty ? "Training age unavailable" : snapshot.comparisonLine)
    }

    private var tone: Color {
        switch snapshot.state {
        case .younger: return .success
        case .older: return .warning
        case .matched, .unknown: return Color(hex: "A855F7")
        }
    }

    private var barFraction: CGFloat {
        guard let chrono = snapshot.chronologicalAge, let bio = snapshot.biologicalAge, chrono > 0 else { return 0.5 }
        return CGFloat(min(1.0, max(0.15, bio / max(chrono, bio))))
    }

    private func ageColumn(title: String, value: Double?, emphasis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(1.2)
                .foregroundColor(.textTertiary)
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.system(size: emphasis ? 32 : 28, weight: .bold, design: .rounded))
                .foregroundColor(emphasis ? tone : .textPrimary)
        }
    }
}

