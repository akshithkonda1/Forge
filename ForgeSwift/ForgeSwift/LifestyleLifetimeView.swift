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
        VStack(spacing: ForgeLayout.sectionGap) {
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

    /// Behind and matched states stay calm: steel for "older", never a
    /// warning color.
    private var agingTone: Color {
        switch aging.state {
        case .younger: return .vitality
        case .older: return HudChrome.miss
        case .matched, .unknown: return Color.aurora
        }
    }
}

struct LifetimeOneBreathCard: View {
    let line: String
    let detail: String
    let tone: Color

    private var showsDetail: Bool { !detail.isEmpty && detail != line }

    private var spokenSummary: String {
        var parts = [line]
        if showsDetail { parts.append(detail) }
        parts.append(Self.disclaimer)
        return parts.joined(separator: ". ")
    }

    private static let disclaimer = "Lifestyle comparison — not a medical biological age."

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            Text("Lifetime")
                .forgeSectionLabel()
                .accessibilityAddTraits(.isHeader)
            Text(line)
                .font(HomeType.sessionTitle)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            if showsDetail {
                Text(detail)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            Text(Self.disclaimer)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPlate(energy: tone)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
    }
}

struct MetabolicStoryCard: View {
    let snapshot: MetabolicHealthSnapshot

    @State private var showEstimate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var carbsValue: String {
        snapshot.carbsGrams > 0 ? "\(Int(snapshot.carbsGrams.rounded()))" : "—"
    }

    private var glucoseValue: String {
        snapshot.latestMgdl.map { "\(Int($0.rounded()))" } ?? "—"
    }

    private var expandTransition: AnyTransition {
        reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header

            if !snapshot.storyLine.isEmpty {
                Text(snapshot.storyLine)
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)
            }

            statGrid

            if let estimate = snapshot.watchEstimate, estimate.hasSignals {
                estimateWell(estimate)
            }

            FourBulletList(bullets: snapshot.bullets)
        }
        .forgeContentCard(tint: .amber)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            ForgeCardHeader("Metabolic health")
            Text("Meals, macros, and how glucose landed")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }

    private var statGrid: some View {
        ForgeStatGrid(columns: 3) {
            ForgeStatTile(label: "Meals", value: "\(snapshot.mealCount)", energy: .amber)
            ForgeStatTile(
                label: "Carbs",
                value: carbsValue,
                unit: snapshot.carbsGrams > 0 ? "g" : nil,
                energy: .amber
            )
            ForgeStatTile(
                label: "Glucose",
                value: glucoseValue,
                unit: snapshot.latestMgdl == nil ? nil : "mg/dL",
                energy: .amber
            )
        }
    }

    /// Watch estimates stay visibly apart from measurements: a well with a
    /// disclosure, so the card keeps to four blocks.
    private func estimateWell(_ estimate: MetabolicWatchEstimate) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeTextLink(title: "Estimated from Apple Watch", accent: .amber, expanded: showEstimate) {
                toggleEstimate()
            }
            if showEstimate {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(estimate.displayLines, id: \.self) { line in
                        ForgeBulletRow(text: line, tint: .amber)
                    }
                    Text("Lifestyle estimates from Apple Watch trends, not measurements.")
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .transition(expandTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private func toggleEstimate() {
        if reduceMotion {
            showEstimate.toggle()
        } else {
            withAnimation(FDS.Spring.standard) { showEstimate.toggle() }
        }
    }
}

struct MealGlucoseStoryCard: View {
    let pairs: [MealGlucosePair]

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Meal ↔ Glucose")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Meals and glucose")
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: ForgeLayout.tileGap) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    pairWell(pair)
                }
            }
        }
        .forgeContentCard(tint: .aurora)
    }

    private func pairWell(_ pair: MealGlucosePair) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(pair.line)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            if let peak = pair.peakMgdl {
                Text(peakCaption(peak: peak, delta: pair.deltaMgdl))
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .combine)
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
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Sensor sold separately")
            Text(snapshot.accessoryLine)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            ForgeTextLink(title: "Open devices", accent: .amber, action: onOpenDevices)
        }
        .forgeContentCard(tint: .amber)
        .accessibilityElement(children: .contain)
    }
}
