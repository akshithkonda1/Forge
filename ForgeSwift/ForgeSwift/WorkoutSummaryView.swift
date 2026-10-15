import SwiftUI

struct WorkoutSummaryView: View {
    let data: WorkoutSummaryData
    let onDismiss: () -> Void
    @State private var showDashboard = false
    @State private var celebrate = false
    @ScaledMetric(relativeTo: .largeTitle) private var scoreRingSize: CGFloat = 180
    @Environment(\.dynamicTypeSize) private var typeSize

    private var workoutScore: Int {
        var s = 60
        if data.personalRecords.count > 0 { s += min(20, data.personalRecords.count * 7) }
        if data.avgRPE >= 6 && data.avgRPE <= 8.5 { s += 10 }
        if data.minO2 >= 95 { s += 5 }
        if data.totalSets >= 12 { s += 5 }
        return min(100, s)
    }
    private var scoreLabel: String {
        switch workoutScore { case 90...: return "Elite"; case 80...: return "Excellent"; case 70...: return "Strong"; case 60...: return "Solid"; default: return "Good" }
    }
    private var scoreColor: Color { HomeReadiness.color(workoutScore) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: ForgeLayout.sectionGap) {
                heroPlate
                statsBlock
                if !data.personalRecords.isEmpty { personalRecordsCard }
                if !data.hrHistory.isEmpty {
                    HRSparklineCard(hrHistory: data.hrHistory, peakHR: data.peakHR, avgHR: data.avgHR)
                }
                ZoneBreakdownCard(hrHistory: data.hrHistory)
                dashboardRow
                actionButtons
            }
            .forgeScreenInsets(top: FDS.Spacing.xl)
        }
        .forgeScreenBackground(accent: .ember)
        .sheet(isPresented: $showDashboard) { ARIADashboardView(snapshot: data.ariaSnapshot, isPreWorkout: false) }
        .onAppear {
            guard !celebrate else { return }
            celebrate = true
            FDS.haptic(.success)
        }
    }

    // MARK: - Hero

    private var heroPlate: some View {
        VStack(spacing: ForgeLayout.heroGap) {
            scoreRing
            if typeSize.isAccessibilitySize {
                Text(scoreLabel)
                    .forgeSectionLabel(tint: scoreColor)
                    .multilineTextAlignment(.center)
            }
            heroTitleBlock
            if !data.personalRecords.isEmpty {
                HudVibeChip(label: prCountLabel, energy: .amber)
            }
        }
        .frame(maxWidth: .infinity)
        .hudPlate(energy: scoreColor)
        .accessibilityElement(children: .contain)
    }

    private var scoreRing: some View {
        let ringSize = ForgeLayout.scaledCap(scoreRingSize, base: 180)
        return HudProgressRing(progress: workoutScore, energy: scoreColor, size: ringSize, eventGlow: celebrate) {
            VStack(spacing: ForgeLayout.labelValueGap) {
                Text("\(workoutScore)")
                    .font(HomeType.heroScore)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .hudInArcText()
                if !typeSize.isAccessibilitySize {
                    Text(scoreLabel)
                        .forgeSectionLabel(tint: scoreColor)
                        .hudInArcText()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout score \(workoutScore) out of 100, \(scoreLabel)")
    }

    private var heroTitleBlock: some View {
        VStack(spacing: ForgeLayout.pairGap) {
            Text("Workout Complete")
                .font(FDS.TypeScale.Dynamic.pageTitle)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            if !data.workoutName.isEmpty {
                Text(data.workoutName)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var prCountLabel: String {
        "\(data.personalRecords.count) PR\(data.personalRecords.count == 1 ? "" : "s")"
    }

    // MARK: - Stats

    private var statsBlock: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            ForgeStatGrid(columns: 4) {
                ForgeStatTile(label: "Duration", value: formatDuration(data.duration), energy: .ember, icon: "clock.fill")
                ForgeStatTile(label: "Volume", value: data.totalVolume.formattedVolume, energy: .steel, icon: "scalemass.fill")
                ForgeStatTile(label: "Sets", value: "\(data.totalSets)", energy: .vitality, icon: "repeat")
                ForgeStatTile(label: "Avg HR", value: measured(data.avgHR), unit: data.avgHR > 0 ? "bpm" : nil, energy: .steel, icon: "waveform.path.ecg")
            }
            ForgeStatGrid(columns: 3) {
                ForgeStatTile(label: "Kcal", value: "\(data.caloriesBurned)", energy: .ember, icon: "flame.fill")
                ForgeStatTile(label: "Reps", value: "\(data.totalReps)", energy: .amber, icon: "hand.raised.fill")
                ForgeStatTile(label: "Peak HR", value: measured(data.peakHR), unit: data.peakHR > 0 ? "bpm" : nil, energy: .ember, icon: "heart.fill")
                ForgeStatTile(label: "Min O₂", value: measured(data.minO2, suffix: "%"), energy: o2Color, icon: "lungs.fill")
                ForgeStatTile(label: "Avg RPE", value: data.avgRPE > 0 ? String(format: "%.1f", data.avgRPE) : "—", energy: rpeColor(data.avgRPE), icon: "bolt.fill")
                ForgeStatTile(label: "Exercises", value: "\(data.exercisesCompleted)", energy: .ember, icon: "dumbbell.fill")
            }
        }
    }

    private var o2Color: Color {
        if data.minO2 > 0 && data.minO2 < 94 { return HudChrome.miss }
        return HudChrome.plate
    }

    /// A zero from the session means "not measured", so it reads as a dash.
    private func measured(_ value: Int, suffix: String = "") -> String {
        value > 0 ? "\(value)\(suffix)" : "—"
    }

    // MARK: - Personal records

    private var personalRecordsCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: "Personal Records", tint: .amber) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.amber)
                    .accessibilityHidden(true)
            }
            VStack(spacing: ForgeLayout.rowGap) {
                ForEach(data.personalRecords, id: \.self) { pr in
                    personalRecordRow(pr)
                }
            }
        }
        .forgeContentCard(accent: .amber)
    }

    private func personalRecordRow(_ pr: String) -> some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            Text(pr)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HudVibeChip(label: "New PR", energy: .amber)
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pr), new personal record")
    }

    // MARK: - ARIA dashboard

    private var dashboardRow: some View {
        Button {
            FDS.haptic(.press)
            showDashboard = true
        } label: {
            ForgeListRow(
                icon: "brain.head.profile",
                iconColor: .ember,
                title: "Open ARIA Dashboard",
                subtitle: "Muscle balance, auto-reg log & how to improve",
                showChevron: true
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .forgeContentCard(tint: .ember)
        .accessibilityLabel("Open ARIA Dashboard")
        .accessibilityHint("Shows muscle balance, the auto-regulation log and how to improve")
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            ForgePrimaryButton(title: "Done", icon: "checkmark", accent: .ember, action: onDismiss)
            ForgeSecondaryButton(title: "Send to ARIA", icon: "paperplane.fill", accent: .ember) {
                showDashboard = true
            }
        }
    }

    private func rpeColor(_ rpe: Double) -> Color {
        if rpe <= 0 { return .textMuted }
        if rpe <= 4 { return .vitality }
        if rpe <= 7 { return .amber }
        return HudChrome.miss
    }
    private func formatDuration(_ s: Int) -> String { let m = s / 60; let sec = s % 60; return m > 0 ? "\(m)m \(sec)s" : "\(sec)s" }
}

// MARK: - Heart-rate zones

private struct SummaryHRZone {
    let name: String
    let color: Color
    let range: ClosedRange<Int>
}

private enum SummaryHRZones {
    static let all: [SummaryHRZone] = [
        SummaryHRZone(name: "Z1", color: HudChrome.plate, range: 100...114),
        SummaryHRZone(name: "Z2", color: Color.vitality, range: 115...133),
        SummaryHRZone(name: "Z3", color: Color.amber, range: 134...152),
        SummaryHRZone(name: "Z4", color: Color.ember, range: 153...171),
        SummaryHRZone(name: "Z5", color: Color.emberDark, range: 172...220),
    ]
}

private struct SummaryZoneBar {
    let zone: String
    let color: Color
    var count: Int = 0
}

private struct ZoneStackedBar: View {
    let bars: [SummaryZoneBar]
    let total: Int

    var body: some View {
        let segmentGap: CGFloat = 2
        let active = bars.filter { $0.count > 0 }
        GeometryReader { geo in
            let usable = max(0, geo.size.width - segmentGap * CGFloat(max(0, active.count - 1)))
            HStack(spacing: segmentGap) {
                ForEach(active, id: \.zone) { bar in
                    Rectangle()
                        .fill(bar.color)
                        .frame(width: usable * CGFloat(bar.count) / CGFloat(max(1, total)))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct ZoneBreakdownCard: View {
    let hrHistory: [Int]

    private var zoneBars: [SummaryZoneBar] {
        var bars = SummaryHRZones.all.map { SummaryZoneBar(zone: $0.name, color: $0.color) }
        for hr in hrHistory {
            for i in SummaryHRZones.all.indices where SummaryHRZones.all[i].range.contains(hr) {
                bars[i].count += 1
            }
        }
        return bars
    }

    var body: some View {
        let bars = zoneBars
        let total = bars.reduce(0) { $0 + $1.count }
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header
            if hrHistory.isEmpty {
                ForgeEmptyNote(
                    title: "No heart-rate data this session",
                    message: "Wear your Watch next time.",
                    systemImage: "applewatch",
                    tint: .steel
                )
            } else {
                ZoneStackedBar(bars: bars, total: total)
                VStack(spacing: ForgeLayout.labelValueGap) {
                    ForEach(bars, id: \.zone) { bar in
                        zoneRow(bar, total: total)
                    }
                }
            }
        }
        .forgeContentCard(tint: .ember)
    }

    @ViewBuilder
    private var header: some View {
        if hrHistory.isEmpty {
            ForgeCardHeader("Heart Rate Zones")
        } else {
            ForgeCardHeader("Heart Rate Zones", meta: "\(hrHistory.count) samples")
        }
    }

    private func zoneRow(_ bar: SummaryZoneBar, total: Int) -> some View {
        let time = zoneTime(bar.count)
        let percent = total > 0 ? Int((Double(bar.count) / Double(total) * 100).rounded()) : 0
        return ForgeMetricRow(
            label: bar.zone,
            value: time.value,
            unit: time.unit,
            tint: bar.color,
            detail: "\(percent)%"
        )
        .accessibilityElement(children: .combine)
    }

    /// Samples arrive every 2 seconds.
    private func zoneTime(_ count: Int) -> (value: String, unit: String) {
        let secs = count * 2
        return secs < 60 ? ("\(secs)", "s") : ("\(secs / 60)", "m")
    }
}

// MARK: - Heart-rate line

private struct HRSparklineCard: View {
    let hrHistory: [Int]
    let peakHR: Int
    let avgHR:  Int

    private var smoothed: [Int] {
        guard hrHistory.count > 4 else { return hrHistory }
        let step = max(1, hrHistory.count / 60)
        return stride(from: 0, to: hrHistory.count, by: step).map { hrHistory[$0] }
    }

    private var chartSummary: String {
        "Heart rate over the session. Peak \(peakHR) beats per minute, average \(avgHR)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("Heart Rate")
            VStack(spacing: ForgeLayout.labelValueGap) {
                ForgeMetricRow(label: "Peak", value: peakHR > 0 ? "\(peakHR)" : "—", unit: peakHR > 0 ? "bpm" : nil, tint: .ember)
                ForgeMetricRow(label: "Avg", value: avgHR > 0 ? "\(avgHR)" : "—", unit: avgHR > 0 ? "bpm" : nil, tint: .steel)
            }
            chart
                .frame(height: 88)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartSummary)
        }
        .forgeContentCard(tint: .ember)
    }

    private var chart: some View {
        Canvas { ctx, size in
            let pts = smoothed
            guard pts.count > 1 else { return }
            let minV = Double(pts.min() ?? 60); let maxV = Double(pts.max() ?? 200); let rng = max(maxV - minV, 1)
            let xStep = size.width / Double(pts.count - 1)
            func y(_ v: Int) -> Double { size.height - (Double(v) - minV) / rng * size.height }
            func pt(_ i: Int) -> CGPoint { CGPoint(x: Double(i) * xStep, y: y(pts[i])) }
            for z in SummaryHRZones.all {
                let yT = max(0.0, size.height - (Double(z.range.upperBound) - minV) / rng * size.height)
                let yB = min(size.height, size.height - (Double(z.range.lowerBound) - minV) / rng * size.height)
                if yB > yT { ctx.fill(Path(CGRect(x: 0, y: yT, width: size.width, height: yB - yT)), with: .color(z.color.opacity(0.09))) }
            }
            var area = Path(); area.move(to: CGPoint(x: 0, y: size.height))
            for i in pts.indices { i == 0 ? area.move(to: pt(0)) : area.addLine(to: pt(i)) }
            area.addLine(to: CGPoint(x: size.width, y: size.height)); area.closeSubpath()
            ctx.fill(area, with: .color(Color.ember.opacity(0.10)))
            var line = Path(); for i in pts.indices { i == 0 ? line.move(to: pt(0)) : line.addLine(to: pt(i)) }
            ctx.stroke(line, with: .color(Color.ember.opacity(0.85)), lineWidth: 2)
        }
    }
}
