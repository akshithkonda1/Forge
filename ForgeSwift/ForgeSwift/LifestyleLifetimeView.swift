import SwiftUI
import ForgeCore

/// First-class Lifetime surface on Lifestyle: aging + metabolic health.
///
/// Aging already had a card buried under Optimize. Metabolic had meals
/// and a device catalog, but no meal ↔ glucose story. This is that room.
struct LifestyleLifetimeView: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @State private var showDevices = false

    private var metabolic: MetabolicHealthSnapshot { vm.metabolicSnapshot }
    private var aging: AgingSnapshot { vm.agingSnapshot }

    var body: some View {
        VStack(spacing: 20) {
            if !aging.oneBreathLine.isEmpty {
                LifetimeOneBreathCard(
                    line: aging.oneBreathLine,
                    detail: aging.comparisonLine,
                    tone: agingTone
                )
            }

            BiologicalAgeCard(snapshot: aging)
            if store.metabolicHealthEnabled {
                MetabolicStoryCard(snapshot: metabolic)
                if !metabolic.pairs.isEmpty {
                    MealGlucoseStoryCard(pairs: metabolic.pairs)
                }
                MetabolicAccessoryCard(
                    snapshot: metabolic,
                    onOpenDevices: { showDevices = true }
                )
            }
        }
        .sheet(isPresented: $showDevices) {
            ConnectedDevicesLibraryView()
                .environmentObject(store)
        }
    }

    private var agingTone: Color {
        switch aging.state {
        case .younger: return .success
        case .older: return .warning
        case .matched, .unknown: return Color(hex: "A855F7")
        }
    }
}

struct LifetimeOneBreathCard: View {
    let line: String
    let detail: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIFETIME")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.textTertiary)
                .tracking(2.5)
            Text(line)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !detail.isEmpty, detail != line {
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            Text("Lifestyle comparison — not a medical biological age.")
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: 22, accent: tone)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line)
    }
}

struct MetabolicStoryCard: View {
    let snapshot: MetabolicHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: "FFB84D").opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "FFB84D"))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Metabolic health")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("Meals, macros, and how glucose landed")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }

            if !snapshot.storyLine.isEmpty {
                Text(snapshot.storyLine)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            HStack(spacing: 12) {
                macroChip("Meals", "\(snapshot.mealCount)")
                macroChip("Carbs", snapshot.carbsGrams > 0 ? "\(Int(snapshot.carbsGrams.rounded()))g" : "—")
                macroChip("Glucose", snapshot.latestMgdl.map { "\(Int($0.rounded()))" } ?? "—")
            }

            if let estimate = snapshot.watchEstimate, estimate.hasSignals {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ESTIMATED FROM APPLE WATCH")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.textTertiary)
                        .tracking(1.6)
                    ForEach(estimate.displayLines, id: \.self) { line in
                        Text("•  \(line)")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Estimates, not measurements — not medical advice.")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FourBulletList(bullets: snapshot.bullets)
        }
        .padding(22)
        .forgeGlassCard(cornerRadius: 22, accent: Color(hex: "FFB84D"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.storyLine.isEmpty ? "Metabolic health" : snapshot.storyLine)
    }

    private func macroChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(1.1)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MealGlucoseStoryCard: View {
    let pairs: [MealGlucosePair]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MEAL ↔ GLUCOSE")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.textTertiary)
                .tracking(2.5)

            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 4) {
                    Text(pair.line)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let peak = pair.peakMgdl {
                        Text(peakCaption(peak: peak, delta: pair.deltaMgdl))
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceElevated)
                .cornerRadius(14)
            }
        }
        .padding(22)
        .forgeGlassCard(cornerRadius: 22, accent: Color(hex: "FFB84D"))
    }

    private func peakCaption(peak: Double, delta: Double?) -> String {
        if let delta {
            return "Peak \(Int(peak.rounded())) mg/dL · \(delta >= 0 ? "+" : "")\(Int(delta.rounded())) from before the meal"
        }
        return "Peak \(Int(peak.rounded())) mg/dL after the meal"
    }
}

struct MetabolicAccessoryCard: View {
    let snapshot: MetabolicHealthSnapshot
    var onOpenDevices: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cross.vial.fill")
                    .foregroundColor(Color(hex: "FFB84D"))
                Text("Sensor sold separately")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            Text(snapshot.accessoryLine)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpenDevices) {
                Text("Open devices")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ember)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open devices")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: 20, accent: Color(hex: "FFB84D"))
    }
}
