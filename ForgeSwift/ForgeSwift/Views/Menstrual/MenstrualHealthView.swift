import SwiftUI

/// Premium menstrual cycle tracker — multi-signal accuracy surface for ARIA + the user.
struct MenstrualHealthView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFlow: MenstrualFlowLevel = .medium
    @State private var selectedSymptoms: Set<CycleSymptom> = []
    @State private var bbtText = ""
    @State private var showDisclaimer = false
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !cycleStore.settings.enabled {
                    enableCard
                } else {
                    phaseHero
                    predictionCard
                    accuracyCard
                    todayLogger
                    insightsCard
                    settingsCard
                    disclaimerFooter
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("Cycle Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await cycleStore.syncFromHealthKit() }
                } label: {
                    if cycleStore.isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(!cycleStore.settings.enabled)
            }
        }
        .onAppear {
            cycleStore.enableForFemaleProfileIfNeeded(gender: store.userProfile.gender)
            cycleStore.refresh(from: store)
            Task { await cycleStore.syncFromHealthKit() }
            withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Menstrual intelligence")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.textPrimary)
            Text("Multi-signal engine: period starts, BBT, OPK, mucus, symptoms, and personal cycle math.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(appeared ? 1 : 0)
    }

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Turn on cycle tracking")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("Optional. Data stays on-device unless you share with ARIA for training guidance. Never used as birth control or medical diagnosis.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
            Button {
                cycleStore.updateSettings {
                    $0.enabled = true
                    $0.shareWithAria = true
                }
                FDS.haptic(.medium)
                Task { await cycleStore.syncFromHealthKit() }
            } label: {
                Text("Enable cycle health")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "EF4444"))
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "EF4444"))
    }

    private var phaseHero: some View {
        let snap = cycleStore.snapshot
        let accent = Color(hex: snap.phase.accentHex)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: snap.phase.icon)
                    .font(.system(size: 22))
                    .foregroundColor(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.phase.label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundColor(accent)
                    if let day = snap.dayInCycle {
                        Text("Day \(day)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                    } else {
                        Text("Building your baseline")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                }
                Spacer()
                confidenceRing(snap.confidence, accent: accent)
            }

            Text(snap.trainingNote)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if snap.isCurrentlyBleeding {
                Label("Bleeding logged today", systemImage: "drop.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "EF4444"))
            }

            cycleStrip(snap)
        }
        .padding(18)
        .forgeGlassCard(accent: accent)
    }

    private func confidenceRing(_ value: Double, accent: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(value))
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(value * 100))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("%")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
        .frame(width: 54, height: 54)
        .accessibilityLabel("Confidence \(Int(value * 100)) percent")
    }

    private func cycleStrip(_ snap: MenstrualCycleSnapshot) -> some View {
        let length = max(21, min(40, Int(snap.cycleLengthMedian.rounded())))
        let day = snap.dayInCycle ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    // Phase bands (approx)
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(hex: "EF4444").opacity(0.35))
                            .frame(width: w * CGFloat(min(5, length)) / CGFloat(length))
                        Rectangle().fill(Color(hex: "22C55E").opacity(0.28))
                            .frame(width: w * 0.28)
                        Rectangle().fill(Color(hex: "F59E0B").opacity(0.3))
                            .frame(width: w * 0.14)
                        Rectangle().fill(Color(hex: "6366F1").opacity(0.28))
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                    // Today marker
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, min(w - 10, w * CGFloat(day - 1) / CGFloat(length))))
                }
            }
            .frame(height: 12)

            HStack {
                Text("Median cycle \(Int(snap.cycleLengthMedian.rounded()))d")
                Spacer()
                Text("Period ~\(Int(snap.periodLengthMedian.rounded()))d")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.textTertiary)
        }
    }

    private var predictionCard: some View {
        let snap = cycleStore.snapshot
        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PREDICTIONS")
            if let next = snap.nextPeriod {
                predRow(title: "Next period window", value: "\(shortDate(next.earliestDayKey)) – \(shortDate(next.latestDayKey))")
                predRow(title: "Most likely start", value: shortDate(next.medianDayKey))
            } else {
                Text("Log at least one period start to unlock predictions.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            }
            if let ovu = snap.ovulationDayInCycle {
                predRow(
                    title: "Ovulation estimate",
                    value: "Day \(ovu)" + (snap.ovulationMethod.map { " · \($0.replacingOccurrences(of: "_", with: " "))" } ?? "")
                )
            }
            if let fs = snap.fertileStartDayInCycle, let fe = snap.fertileEndDayInCycle {
                predRow(title: "Fertile window (est.)", value: "Days \(fs)–\(fe)")
            }
            if snap.irregularityFlag {
                Label("Higher variability — wider windows on purpose", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.warning)
            }
        }
        .padding(18)
        .forgeGlassCard(accent: .steel)
    }

    private var accuracyCard: some View {
        let snap = cycleStore.snapshot
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ACCURACY ENGINE")
            accuracyRow("Cycles observed", "\(snap.cyclesObserved)")
            accuracyRow("Length MAD", String(format: "%.1f days", snap.cycleLengthMAD))
            accuracyRow("Data quality", snap.dataQuality.capitalized)
            accuracyRow("Signals", "Flow · BBT · OPK · Mucus · Symptoms · HRV context")
            Text("Hierarchy: LH surge → BBT 3-over-6 → peak mucus → personalized calendar.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "A855F7"))
    }

    private var todayLogger: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("LOG TODAY")

            Text("Flow")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([MenstrualFlowLevel.none, .spotting, .light, .medium, .heavy], id: \.self) { level in
                        Button {
                            selectedFlow = level
                            FDS.selectionHaptic()
                        } label: {
                            Text(level.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selectedFlow == level ? .white : .textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedFlow == level ? Color(hex: "EF4444") : Color.surfaceElevated)
                                .cornerRadius(100)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Symptoms")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
            FlowLayout(spacing: 8) {
                ForEach(CycleSymptom.allCases) { symptom in
                    Button {
                        if selectedSymptoms.contains(symptom) {
                            selectedSymptoms.remove(symptom)
                        } else {
                            selectedSymptoms.insert(symptom)
                        }
                        FDS.selectionHaptic()
                    } label: {
                        Text(symptom.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(selectedSymptoms.contains(symptom) ? .white : .textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedSymptoms.contains(symptom) ? Color.ember.opacity(0.85) : Color.surfaceElevated)
                            .cornerRadius(100)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("BBT °C (optional)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                TextField("36.5", text: $bbtText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            Button {
                saveToday()
            } label: {
                Text("Save today's log")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.ember)
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)

            Button {
                cycleStore.logPeriodStart(flow: selectedFlow == .none ? .medium : selectedFlow)
                FDS.notificationHaptic(.success)
            } label: {
                Text("Mark period start today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "EF4444"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(accent: .ember)
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("INSIGHTS")
            ForEach(cycleStore.snapshot.insights, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Color(hex: cycleStore.snapshot.phase.accentHex)).frame(width: 6, height: 6).padding(.top, 6)
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(cycleStore.snapshot.readinessNote)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textPrimary)
                .padding(.top, 4)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "6366F1"))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PRIVACY & ARIA")
            Toggle(isOn: Binding(
                get: { cycleStore.settings.shareWithAria },
                set: { v in cycleStore.updateSettings { $0.shareWithAria = v } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share cycle with ARIA")
                        .foregroundColor(.textPrimary)
                    Text("Lets coaching adapt intensity & language. Never clinical advice.")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
            }
            .tint(.ember)

            Toggle(isOn: Binding(
                get: { cycleStore.settings.usesHormonalContraception },
                set: { v in cycleStore.updateSettings { $0.usesHormonalContraception = v } }
            )) {
                Text("On hormonal contraception")
                    .foregroundColor(.textPrimary)
            }
            .tint(.ember)

            Toggle(isOn: Binding(
                get: { cycleStore.settings.enabled },
                set: { v in cycleStore.updateSettings { $0.enabled = v } }
            )) {
                Text("Tracking enabled")
                    .foregroundColor(.textPrimary)
            }
            .tint(.ember)
        }
        .padding(18)
        .forgeGlassCard(accent: .steel)
    }

    private var disclaimerFooter: some View {
        Text(MenstrualCycleEngine.disclaimer)
            .font(.system(size: 11))
            .foregroundColor(.textTertiary)
            .padding(.horizontal, 4)
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1.6)
            .foregroundColor(.textTertiary)
    }

    private func predRow(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundColor(.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
        }
    }

    private func accuracyRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 13)).foregroundColor(.textSecondary)
            Spacer()
            Text(v).font(.system(size: 13, weight: .medium)).foregroundColor(.textPrimary)
        }
    }

    private func shortDate(_ key: String) -> String {
        guard let d = CycleDayKey.date(from: key) else { return key }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func saveToday() {
        let bbt = Double(bbtText.replacingOccurrences(of: ",", with: "."))
        cycleStore.logToday(
            flow: selectedFlow,
            symptoms: Array(selectedSymptoms),
            bbtCelsius: bbt
        )
        cycleStore.refresh(from: store)
        FDS.notificationHaptic(.success)
    }
}

// MARK: - Compact home / lifestyle chip

struct CycleHealthChip: View {
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: cycleStore.snapshot.phase.icon)
                    .foregroundColor(Color(hex: cycleStore.snapshot.phase.accentHex))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cycleStore.settings.enabled ? cycleStore.snapshot.phase.shortLabel : "Cycle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    if cycleStore.settings.enabled, let day = cycleStore.snapshot.dayInCycle {
                        Text("Day \(day) · \(Int(cycleStore.snapshot.confidence * 100))% conf")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    } else {
                        Text("Tap to set up")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(14)
            .forgeGlassCard(accent: Color(hex: cycleStore.snapshot.phase.accentHex))
        }
        .buttonStyle(.plain)
    }
}
