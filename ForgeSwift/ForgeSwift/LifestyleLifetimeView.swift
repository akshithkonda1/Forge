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
        VStack(spacing: FDS.Spacing.lg) {
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
        case .matched, .unknown: return Color.aurora
        }
    }
}

struct LifetimeOneBreathCard: View {
    let line: String
    let detail: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            Text("LIFETIME")
                .font(FDS.TypeScale.Dynamic.micro)
                .foregroundColor(.textTertiary)
                .tracking(2.5)
            Text(line)
                .font(FDS.TypeScale.Dynamic.title)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !detail.isEmpty, detail != line {
                Text(detail)
                    .font(FDS.TypeScale.Dynamic.body)
                    .foregroundColor(.textSecondary)
            }
            Text("Lifestyle comparison — not a medical biological age.")
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
        }
        .padding(FDS.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: tone)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line)
    }
}

struct MetabolicStoryCard: View {
    let snapshot: MetabolicHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            HStack(spacing: FDS.Spacing.md) {
                ZStack {
                    Circle().fill(Color.amber.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.amber)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Metabolic health")
                        .font(FDS.TypeScale.Dynamic.headline)
                        .foregroundColor(.textPrimary)
                    Text("Meals, macros, and how glucose landed")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }

            if !snapshot.storyLine.isEmpty {
                Text(snapshot.storyLine)
                    .font(FDS.TypeScale.Dynamic.title)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            HStack(spacing: FDS.Spacing.md) {
                macroChip("Meals", "\(snapshot.mealCount)")
                macroChip("Carbs", snapshot.carbsGrams > 0 ? "\(Int(snapshot.carbsGrams.rounded()))g" : "—")
                macroChip("Glucose", snapshot.latestMgdl.map { "\(Int($0.rounded()))" } ?? "—")
            }

            if let estimate = snapshot.watchEstimate, estimate.hasSignals {
                VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                    Text("ESTIMATED FROM APPLE WATCH")
                        .font(FDS.TypeScale.Dynamic.micro)
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
        .padding(FDS.Spacing.xl)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: Color.amber)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.storyLine.isEmpty ? "Metabolic health" : snapshot.storyLine)
    }

    private func macroChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
            Text(label.uppercased())
                .font(FDS.TypeScale.Dynamic.micro)
                .tracking(1.1)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(FDS.TypeScale.Dynamic.metric)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MealGlucoseStoryCard: View {
    let pairs: [MealGlucosePair]

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
            Text("MEAL ↔ GLUCOSE")
                .font(FDS.TypeScale.Dynamic.micro)
                .foregroundColor(.textTertiary)
                .tracking(2.5)

            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                    Text(pair.line)
                        .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let peak = pair.peakMgdl {
                        Text(peakCaption(peak: peak, delta: pair.deltaMgdl))
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                }
                .padding(FDS.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeInsetTile(radius: FDS.Radius.md)
            }
        }
        .padding(FDS.Spacing.xl)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: Color.amber)
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
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: "cross.vial.fill")
                    .foregroundColor(Color.amber)
                Text("Sensor sold separately")
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundColor(.textPrimary)
            }
            Text(snapshot.accessoryLine)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpenDevices) {
                Text("Open devices")
                    .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                    .foregroundColor(.ember)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open devices")
        }
        .padding(FDS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: FDS.Radius.xl, accent: Color.amber)
    }
}
