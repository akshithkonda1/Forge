import SwiftUI

// MARK: - Cycle Health (premium surface)

/// Flagship menstrual intelligence UI — self tracking + family support.
struct MenstrualHealthView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case me, partner
        var id: String { rawValue }
        var label: String {
            switch self {
            case .me: return "My cycle"
            case .partner: return "Support"
            }
        }
        var icon: String {
            switch self {
            case .me: return "circle.hexagongrid.fill"
            case .partner: return "heart.circle.fill"
            }
        }
    }

    @EnvironmentObject private var store: AppStore
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared

    @State private var pane: Pane = .me
    @State private var selectedFlow: MenstrualFlowLevel = .medium
    @State private var selectedSymptoms: Set<CycleSymptom> = []
    @State private var bbtText = ""
    @State private var partnerFlow: MenstrualFlowLevel = .medium
    @State private var partnerNameDraft = ""
    @State private var partnerRelDraft = "partner"
    @State private var supportRole: CycleSupportRole = .romantic
    @State private var appeared = false
    @State private var ringPulse = false
    @State private var logExpanded = true
    @State private var historyExpanded = false

    private var accent: Color {
        let phase = pane == .me ? cycleStore.snapshot.phase : cycleStore.partnerSnapshot.phase
        return Color(hex: phase.accentHex)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    heroHeader
                    panePicker

                    switch pane {
                    case .me:
                        if !cycleStore.settings.enabled {
                            enableCard
                        } else {
                            phaseOrbitCard
                            dayStrip
                            predictionGrid
                            quickLogCard
                            if historyExpanded || !cycleStore.logs.isEmpty {
                                historyCard
                            }
                            insightsCard
                            ariaCoachCard
                            settingsCard
                            disclaimerFooter
                        }
                    case .partner:
                        partnerContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .background {
                cycleAmbientBackground
            }
        }
        .navigationTitle("Cycle Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if pane == .me, cycleStore.settings.enabled {
                        Button {
                            Task {
                                await cycleStore.syncFromHealthKit()
                                cycleStore.refresh(from: store)
                                FDS.notificationHaptic(.success)
                            }
                        } label: {
                            if cycleStore.isSyncing {
                                ProgressView().tint(accent)
                            } else {
                                Image(systemName: "heart.text.square.fill")
                                    .foregroundStyle(accent)
                            }
                        }
                        .accessibilityLabel("Sync Apple Health")
                    }
                }
            }
        }
        .onAppear {
            cycleStore.enableForFemaleProfileIfNeeded(gender: store.userProfile.gender)
            if store.userProfile.gender != .female, !cycleStore.settings.enabled {
                pane = .partner
            }
            partnerNameDraft = cycleStore.partnerSettings.partnerName
            partnerRelDraft = cycleStore.partnerSettings.relationshipLabel
            supportRole = cycleStore.partnerSettings.resolvedRole
            cycleStore.refresh(from: store)
            Task { await cycleStore.syncFromHealthKit() }
            withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                ringPulse = true
            }
        }
    }

    // MARK: Ambient

    private var cycleAmbientBackground: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            RadialGradient(
                colors: [accent.opacity(0.18), .clear],
                center: UnitPoint(x: 0.5, y: 0.08),
                startRadius: 20,
                endRadius: 320
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color.steel.opacity(0.06), .clear],
                center: UnitPoint(x: 0.9, y: 0.75),
                startRadius: 10,
                endRadius: 260
            )
            .ignoresSafeArea()
        }
    }

    // MARK: Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pane == .me ? "CYCLE INTELLIGENCE" : "FAMILY SUPPORT")
                .forgeSectionLabel()
                .foregroundStyle(accent.opacity(0.9))
            Text(pane == .me ? "Know your rhythm" : "Show up for them")
                .font(FDS.TypeScale.display(30))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color.white.opacity(0.78)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text(
                pane == .me
                    ? "Periods, fertile windows, and recovery — personal math from your signals. Lifestyle guidance only."
                    : "Partners, spouses, daughters — log what they share so ARIA can coach you with care."
            )
            .font(FDS.TypeScale.body(14))
            .foregroundColor(.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    private var panePicker: some View {
        HStack(spacing: 6) {
            ForEach(Pane.allCases) { p in
                Button {
                    withAnimation(FDS.Spring.snap) { pane = p }
                    FDS.selectionHaptic()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: p.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(p.label)
                            .font(FDS.TypeScale.label(13))
                    }
                    .foregroundColor(pane == p ? .white : .textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if pane == p {
                            Capsule().fill(
                                LinearGradient(
                                    colors: [accent, accent.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: accent.opacity(0.35), radius: 12, y: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.surfaceElevated.opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Enable self

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "EF4444").opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "drop.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(hex: "EF4444"))
            }
            Text("Track with precision")
                .font(FDS.TypeScale.title(20))
                .foregroundColor(.textPrimary)
            Text("Log flow, symptoms, and optional BBT. ARIA personalizes cycle length, ovulation estimates, and training bias — never medical diagnosis.")
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
            featureRow("drop.circle.fill", "Period episodes & predictions")
            featureRow("waveform.path.ecg", "Multi-signal confidence")
            featureRow("sparkles", "Phase-aware ARIA coaching")

            Button {
                cycleStore.updateSettings {
                    $0.enabled = true
                    $0.shareWithAria = true
                }
                FDS.haptic(.medium)
                Task { await cycleStore.syncFromHealthKit() }
            } label: {
                Text("Enable my cycle")
                    .font(FDS.TypeScale.label(16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "F87171"), Color(hex: "EF4444"), Color(hex: "DC2626")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color(hex: "EF4444").opacity(0.4), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .forgeGlassCard(accent: Color(hex: "EF4444"))
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "EF4444"))
                .frame(width: 22)
            Text(text)
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: Phase orbit

    private var phaseOrbitCard: some View {
        let snap = cycleStore.snapshot
        let phaseColor = Color(hex: snap.phase.accentHex)
        return VStack(spacing: 18) {
            ZStack {
                // Outer glow
                Circle()
                    .stroke(phaseColor.opacity(ringPulse ? 0.35 : 0.12), lineWidth: 18)
                    .frame(width: 200, height: 200)
                    .blur(radius: 2)
                // Track
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 14)
                    .frame(width: 188, height: 188)
                // Progress by day in cycle
                Circle()
                    .trim(from: 0, to: cycleProgress(snap))
                    .stroke(
                        AngularGradient(
                            colors: [
                                phaseColor.opacity(0.3),
                                phaseColor,
                                Color.white.opacity(0.5),
                                phaseColor.opacity(0.8),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 188, height: 188)
                    .rotationEffect(.degrees(-90))
                // Confidence ring
                Circle()
                    .trim(from: 0, to: CGFloat(snap.confidence))
                    .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Image(systemName: snap.phase.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(phaseColor)
                    if let day = snap.dayInCycle {
                        Text("Day \(day)")
                            .font(FDS.TypeScale.display(36))
                            .foregroundColor(.textPrimary)
                    } else {
                        Text("—")
                            .font(FDS.TypeScale.display(36))
                            .foregroundColor(.textTertiary)
                    }
                    Text(snap.phase.label.uppercased())
                        .font(FDS.TypeScale.micro(11))
                        .tracking(1.4)
                        .foregroundStyle(phaseColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            HStack(spacing: 10) {
                metricPill(
                    title: "CONFIDENCE",
                    value: "\(Int(snap.confidence * 100))%",
                    color: phaseColor
                )
                metricPill(
                    title: "CYCLE",
                    value: "\(Int(snap.cycleLengthMedian.rounded()))d",
                    color: .steel
                )
                metricPill(
                    title: "PERIOD",
                    value: "~\(Int(snap.periodLengthMedian.rounded()))d",
                    color: Color(hex: "F87171")
                )
            }

            if snap.isCurrentlyBleeding {
                Label("Bleeding logged today", systemImage: "drop.fill")
                    .font(FDS.TypeScale.label(13))
                    .foregroundStyle(Color(hex: "F87171"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "EF4444").opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(snap.trainingNote)
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(22)
        .forgeGlassCard(accent: phaseColor)
    }

    private func cycleProgress(_ snap: MenstrualCycleSnapshot) -> CGFloat {
        guard let day = snap.dayInCycle else { return 0.08 }
        let len = max(21, min(45, snap.cycleLengthMedian))
        return min(0.98, CGFloat(day) / CGFloat(len))
    }

    private func metricPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(FDS.TypeScale.micro(9))
                .tracking(1.2)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(FDS.TypeScale.label(15))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: Day strip

    private var dayStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LAST 14 DAYS")
                    .forgeSectionLabel()
                Spacer()
                Text(cycleStore.snapshot.dataQuality.capitalized)
                    .font(FDS.TypeScale.micro(10))
                    .foregroundColor(.textTertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentDayKeys(), id: \.self) { key in
                        dayCell(key)
                    }
                }
            }
        }
        .padding(18)
        .forgeGlassCard(accent: accent.opacity(0.6))
    }

    private func recentDayKeys() -> [String] {
        (0..<14).reversed().compactMap { offset in
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return CycleDayKey.key(for: d)
        }
    }

    private func dayCell(_ key: String) -> some View {
        let log = cycleStore.logs.first { $0.dayKey == key }
        let flow = log?.flow ?? .none
        let isToday = key == CycleDayKey.key()
        let dayNum: String = {
            guard let d = CycleDayKey.date(from: key) else { return "·" }
            return "\(Calendar.current.component(.day, from: d))"
        }()
        return VStack(spacing: 6) {
            Text(dayNum)
                .font(FDS.TypeScale.micro(10))
                .foregroundColor(isToday ? accent : .textTertiary)
            Circle()
                .fill(flowDotColor(flow))
                .frame(width: flow.isBleeding ? 14 : 8, height: flow.isBleeding ? 14 : 8)
                .overlay {
                    if isToday {
                        Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                    }
                }
            if !(log?.symptoms.isEmpty ?? true) {
                Circle().fill(Color.ember.opacity(0.7)).frame(width: 3, height: 3)
            } else {
                Circle().fill(Color.clear).frame(width: 3, height: 3)
            }
        }
        .frame(width: 36)
    }

    private func flowDotColor(_ flow: MenstrualFlowLevel) -> Color {
        switch flow {
        case .heavy: return Color(hex: "DC2626")
        case .medium: return Color(hex: "EF4444")
        case .light: return Color(hex: "F87171")
        case .spotting: return Color(hex: "FCA5A5")
        default: return Color.white.opacity(0.1)
        }
    }

    // MARK: Predictions

    private var predictionGrid: some View {
        let snap = cycleStore.snapshot
        return VStack(alignment: .leading, spacing: 12) {
            Text("AHEAD").forgeSectionLabel()
            HStack(spacing: 10) {
                predictionTile(
                    icon: "calendar",
                    title: "Next period",
                    value: snap.nextPeriod.map { shortDate($0.medianDayKey) } ?? "—",
                    sub: snap.nextPeriod.map { "\(shortDate($0.earliestDayKey))–\(shortDate($0.latestDayKey))" } ?? "Log starts to predict",
                    color: Color(hex: "EF4444")
                )
                predictionTile(
                    icon: "sparkles",
                    title: "Ovulation est.",
                    value: snap.ovulationDayInCycle.map { "Day \($0)" } ?? "—",
                    sub: snap.ovulationMethod?.replacingOccurrences(of: "_", with: " ") ?? "Learning",
                    color: Color(hex: "A855F7")
                )
            }
            if let fs = snap.fertileStartDayInCycle, let fe = snap.fertileEndDayInCycle {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(Color(hex: "F59E0B"))
                    Text("Fertile window · days \(fs)–\(fe)")
                        .font(FDS.TypeScale.label(13))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if snap.irregularityFlag {
                        Text("Variable")
                            .font(FDS.TypeScale.micro(10))
                            .foregroundStyle(Color.warning)
                    }
                }
                .padding(14)
                .background(Color(hex: "F59E0B").opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func predictionTile(icon: String, title: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(FDS.TypeScale.micro(9))
                .tracking(1.1)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(FDS.TypeScale.title(18))
                .foregroundColor(.textPrimary)
            Text(sub)
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: color)
    }

    // MARK: Quick log

    private var quickLogCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(FDS.Spring.snap) { logExpanded.toggle() }
            } label: {
                HStack {
                    Text("LOG TODAY")
                        .forgeSectionLabel()
                    Spacer()
                    Image(systemName: logExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if logExpanded {
                Text("Flow")
                    .font(FDS.TypeScale.label(12))
                    .foregroundColor(.textSecondary)
                flowSelector(selection: $selectedFlow, accent: Color(hex: "EF4444"))

                Text("Symptoms")
                    .font(FDS.TypeScale.label(12))
                    .foregroundColor(.textSecondary)
                    .padding(.top, 4)
                symptomGrid

                HStack {
                    Text("BBT °C")
                        .font(FDS.TypeScale.label(12))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    TextField("36.50", text: $bbtText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(FDS.TypeScale.label(15))
                        .foregroundColor(.textPrimary)
                        .frame(width: 72)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack(spacing: 10) {
                    Button { saveToday() } label: {
                        Text("Save log")
                            .font(FDS.TypeScale.label(15))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "F87171"), Color(hex: "EF4444")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        cycleStore.logPeriodStart(flow: selectedFlow == .none ? .medium : selectedFlow)
                        cycleStore.refresh(from: store)
                        FDS.notificationHaptic(.success)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 14))
                            Text("Period start")
                                .font(FDS.TypeScale.micro(10))
                        }
                        .foregroundStyle(Color(hex: "EF4444"))
                        .frame(width: 88)
                        .padding(.vertical, 12)
                        .background(Color(hex: "EF4444").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "EF4444"))
    }

    private var symptomGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 96), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(CycleSymptom.allCases) { symptom in
                let on = selectedSymptoms.contains(symptom)
                Button {
                    if on { selectedSymptoms.remove(symptom) } else { selectedSymptoms.insert(symptom) }
                    FDS.selectionHaptic()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: symptom.icon)
                            .font(.system(size: 10))
                        Text(symptom.label)
                            .font(FDS.TypeScale.micro(11))
                            .lineLimit(1)
                    }
                    .foregroundColor(on ? .white : .textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(on ? accent.opacity(0.85) : Color.surfaceElevated)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func flowSelector(selection: Binding<MenstrualFlowLevel>, accent: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([MenstrualFlowLevel.none, .spotting, .light, .medium, .heavy], id: \.self) { level in
                    Button {
                        selection.wrappedValue = level
                        FDS.selectionHaptic()
                    } label: {
                        Text(level.label)
                            .font(FDS.TypeScale.label(13))
                            .foregroundColor(selection.wrappedValue == level ? .white : .textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selection.wrappedValue == level ? accent : Color.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(FDS.Spring.snap) { historyExpanded.toggle() }
            } label: {
                HStack {
                    Text("RECENT LOGS")
                        .forgeSectionLabel()
                    Spacer()
                    Text("\(cycleStore.logs.suffix(30).count)")
                        .font(FDS.TypeScale.micro(11))
                        .foregroundColor(.textTertiary)
                    Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if historyExpanded {
                ForEach(cycleStore.logs.suffix(12).reversed()) { log in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(flowDotColor(log.flow))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortDate(log.dayKey))
                                .font(FDS.TypeScale.label(13))
                                .foregroundColor(.textPrimary)
                            Text(log.flow.label + (log.symptoms.isEmpty ? "" : " · \(log.symptoms.count) symptoms"))
                                .font(FDS.TypeScale.body(11))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer()
                        if let bbt = log.bbtCelsius {
                            Text(String(format: "%.2f°", bbt))
                                .font(FDS.TypeScale.micro(11))
                                .foregroundColor(.steel)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .forgeGlassCard(accent: .steel)
    }

    // MARK: Insights + ARIA

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSIGHTS").forgeSectionLabel()
            ForEach(cycleStore.snapshot.insights.prefix(5), id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(line)
                        .font(FDS.TypeScale.body(13))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(cycleStore.snapshot.readinessNote)
                .font(FDS.TypeScale.label(13))
                .foregroundColor(.textPrimary)
                .padding(.top, 4)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "6366F1"))
    }

    private var ariaCoachCard: some View {
        Button {
            let phase = cycleStore.snapshot.phase.label
            store.openChat(
                with: "I'm in \(phase) — how should I train and recover today?",
                voice: false
            )
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.premiumSurface)
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.ember)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask ARIA about today")
                        .font(FDS.TypeScale.label(15))
                        .foregroundColor(.textPrimary)
                    Text("Phase-aware training & recovery")
                        .font(FDS.TypeScale.body(12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ember)
            }
            .padding(18)
            .forgeGlassCard(accent: .ember)
        }
        .buttonStyle(.plain)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PRIVACY").forgeSectionLabel()
            Toggle(isOn: Binding(
                get: { cycleStore.settings.shareWithAria },
                set: { v in cycleStore.updateSettings { $0.shareWithAria = v } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share cycle with ARIA")
                        .foregroundColor(.textPrimary)
                    Text("Coaching & training bias — never clinical claims.")
                        .font(FDS.TypeScale.body(11))
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
            .font(FDS.TypeScale.body(11))
            .foregroundColor(.textTertiary)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
    }

    // MARK: Partner / support

    private var partnerContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !cycleStore.partnerSettings.enabled {
                partnerEnableCard
            } else if !cycleStore.partnerSettings.consentAcknowledged {
                partnerConsentCard
            } else {
                partnerPhaseHero
                if let brief = cycleStore.partnerSupportBrief {
                    partnerSupportCard(brief)
                }
                partnerLogger
                partnerSettingsCard
                Text(PartnerSupportBrief.disclaimer)
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var partnerEnableCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: "818CF8"), Color(hex: "6366F1")], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("Support someone you love")
                .font(FDS.TypeScale.title(20))
                .foregroundColor(.textPrimary)
            Text("Partners, spouses — and many fathers with daughters. Log period starts they share; ARIA coaches you on comfort, plans, and what not to say.")
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
            rolePicker
            Button {
                cycleStore.updatePartnerSettings {
                    $0.enabled = true
                    $0.shareWithAria = true
                    $0.supportRole = supportRole
                    $0.relationshipLabel = supportRole.suggestedLabels.first ?? "partner"
                }
                partnerRelDraft = supportRole.suggestedLabels.first ?? "partner"
                FDS.haptic(.medium)
            } label: {
                Text("Continue")
                    .font(FDS.TypeScale.label(16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "818CF8"), Color(hex: "6366F1")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .forgeGlassCard(accent: Color(hex: "6366F1"))
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHO")
                .forgeSectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CycleSupportRole.allCases) { role in
                        Button {
                            supportRole = role
                            partnerRelDraft = role.suggestedLabels.first ?? partnerRelDraft
                            FDS.selectionHaptic()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: role.icon)
                                Text(role.shortLabel)
                                    .font(FDS.TypeScale.label(13))
                            }
                            .foregroundColor(supportRole == role ? .white : .textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(supportRole == role ? Color(hex: "6366F1") : Color.surfaceElevated)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var partnerConsentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(supportRole == .child ? "Care first" : "Consent first")
                .font(FDS.TypeScale.title(18))
                .foregroundColor(.textPrimary)
            Text(
                supportRole == .child
                    ? "Only track what fits your caregiver role — preferably with her knowledge. Period starts are enough."
                    : "Only log what they’re comfortable sharing. Starts alone unlock strong support coaching."
            )
            .font(FDS.TypeScale.body(14))
            .foregroundColor(.textSecondary)
            rolePicker
            TextField(supportRole == .child ? "Name (optional)" : "Name (optional)", text: $partnerNameDraft)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField(
                supportRole == .child ? "Label (daughter / child…)" : "Label (partner / wife…)",
                text: $partnerRelDraft
            )
            .textFieldStyle(.plain)
            .padding(12)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                cycleStore.updatePartnerSettings {
                    $0.consentAcknowledged = true
                    $0.partnerName = partnerNameDraft
                    $0.supportRole = supportRole
                    $0.relationshipLabel = partnerRelDraft.isEmpty
                        ? (supportRole.suggestedLabels.first ?? "partner")
                        : partnerRelDraft
                    $0.shareWithAria = true
                }
                FDS.notificationHaptic(.success)
            } label: {
                Text(supportRole == .child ? "I’m supporting as a parent" : "I have their okay")
                    .font(FDS.TypeScale.label(15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.ember)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .forgeGlassCard(accent: .warning)
    }

    private var partnerPhaseHero: some View {
        let snap = cycleStore.partnerSnapshot
        let phaseColor = Color(hex: snap.phase.accentHex)
        let name = cycleStore.partnerSettings.displayName
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(phaseColor.opacity(0.25), lineWidth: 8)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: cycleProgress(snap))
                        .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: snap.phase.icon)
                        .foregroundStyle(phaseColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.uppercased())
                        .font(FDS.TypeScale.micro(10))
                        .tracking(1.3)
                        .foregroundStyle(phaseColor)
                    Text(snap.phase.label)
                        .font(FDS.TypeScale.title(22))
                        .foregroundColor(.textPrimary)
                    if let day = snap.dayInCycle {
                        Text("Day \(day) · \(Int(snap.confidence * 100))% confidence")
                            .font(FDS.TypeScale.body(13))
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
            }
            if let next = snap.nextPeriod {
                Text("Next period window · \(shortDate(next.earliestDayKey)) – \(shortDate(next.latestDayKey))")
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
            }
            Button {
                let role = cycleStore.partnerSettings.resolvedRole
                let prompt = role == .child
                    ? "Help me support my daughter \(name) — \(snap.phase.label). What should I do?"
                    : "Help me support \(name) — \(snap.phase.label). What should I do?"
                store.openChat(with: prompt, voice: false)
            } label: {
                Label("Ask ARIA how to show up", systemImage: "message.fill")
                    .font(FDS.TypeScale.label(14))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(phaseColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .forgeGlassCard(accent: phaseColor)
    }

    private func partnerSupportCard(_ brief: PartnerSupportBrief) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(brief.role == .child ? "PARENT PLAYBOOK" : "HOW YOU SHOW UP")
                .forgeSectionLabel()
            Text(brief.headline)
                .font(FDS.TypeScale.label(15))
                .foregroundColor(.textPrimary)
            ForEach(brief.supportMoves.prefix(4), id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "22C55E"))
                    Text(line)
                        .font(FDS.TypeScale.body(13))
                        .foregroundColor(.textSecondary)
                }
            }
            Text("Ease off")
                .font(FDS.TypeScale.label(13))
                .foregroundColor(.textPrimary)
                .padding(.top, 4)
            ForEach(brief.avoidMoves.prefix(3), id: \.self) { line in
                Text("• \(line)")
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
            }
            Text(brief.communicationTip)
                .font(FDS.TypeScale.label(13))
                .foregroundStyle(Color.ember)
                .padding(.top, 6)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "22C55E"))
    }

    private var partnerLogger: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOG FOR \(cycleStore.partnerSettings.displayName.uppercased())")
                .forgeSectionLabel()
            flowSelector(selection: $partnerFlow, accent: Color(hex: "6366F1"))
            HStack(spacing: 10) {
                Button {
                    cycleStore.logPartnerToday(flow: partnerFlow)
                    FDS.notificationHaptic(.success)
                } label: {
                    Text("Save today")
                        .font(FDS.TypeScale.label(14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "6366F1"))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    cycleStore.logPartnerPeriodStart(flow: partnerFlow == .none ? .medium : partnerFlow)
                    FDS.notificationHaptic(.success)
                } label: {
                    Text("Period start")
                        .font(FDS.TypeScale.label(13))
                        .foregroundStyle(Color(hex: "EF4444"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(Color(hex: "EF4444").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "6366F1"))
    }

    private var partnerSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SETTINGS").forgeSectionLabel()
            rolePicker
            TextField("Name", text: $partnerNameDraft)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField("Relationship label", text: $partnerRelDraft)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button("Save") {
                cycleStore.updatePartnerSettings {
                    $0.partnerName = partnerNameDraft
                    $0.supportRole = supportRole
                    $0.relationshipLabel = partnerRelDraft.isEmpty
                        ? (supportRole.suggestedLabels.first ?? "partner")
                        : partnerRelDraft
                }
                FDS.haptic(.light)
            }
            .font(FDS.TypeScale.label(14))
            .foregroundColor(.ember)
            Toggle(isOn: Binding(
                get: { cycleStore.partnerSettings.shareWithAria },
                set: { v in cycleStore.updatePartnerSettings { $0.shareWithAria = v } }
            )) {
                Text("Share with ARIA").foregroundColor(.textPrimary)
            }
            .tint(.ember)
            Toggle(isOn: Binding(
                get: { cycleStore.partnerSettings.enabled },
                set: { v in
                    cycleStore.updatePartnerSettings {
                        $0.enabled = v
                        if !v { $0.consentAcknowledged = false }
                    }
                }
            )) {
                Text("Support tracking on").foregroundColor(.textPrimary)
            }
            .tint(.ember)
        }
        .padding(18)
        .forgeGlassCard(accent: .steel)
    }

    // MARK: Actions

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

    private func shortDate(_ key: String) -> String {
        guard let d = CycleDayKey.date(from: key) else { return key }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

// MARK: - Home chip

struct CycleHealthChip: View {
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    var preferPartner: Bool = false
    var onTap: () -> Void

    private var showingPartner: Bool {
        preferPartner
            || (cycleStore.partnerSettings.enabled && cycleStore.partnerSettings.consentAcknowledged
                && !cycleStore.settings.enabled)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                let phase = showingPartner ? cycleStore.partnerSnapshot.phase : cycleStore.snapshot.phase
                ZStack {
                    Circle()
                        .fill(Color(hex: phase.accentHex).opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: showingPartner ? "heart.circle.fill" : phase.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: phase.accentHex))
                }
                VStack(alignment: .leading, spacing: 3) {
                    if showingPartner {
                        Text(cycleStore.partnerSettings.displayName)
                            .font(FDS.TypeScale.label(14))
                            .foregroundColor(.textPrimary)
                        if let day = cycleStore.partnerSnapshot.dayInCycle {
                            Text("\(phase.shortLabel) · day \(day)")
                                .font(FDS.TypeScale.body(12))
                                .foregroundColor(.textTertiary)
                        } else {
                            Text(cycleStore.partnerSettings.enabled ? "Partner cycle" : "Set up support")
                                .font(FDS.TypeScale.body(12))
                                .foregroundColor(.textTertiary)
                        }
                    } else {
                        Text(cycleStore.settings.enabled ? phase.label : "Cycle Health")
                            .font(FDS.TypeScale.label(14))
                            .foregroundColor(.textPrimary)
                        if cycleStore.settings.enabled, let day = cycleStore.snapshot.dayInCycle {
                            Text("Day \(day) · \(Int(cycleStore.snapshot.confidence * 100))% conf")
                                .font(FDS.TypeScale.body(12))
                                .foregroundColor(.textTertiary)
                        } else {
                            Text("Tap to set up your rhythm")
                                .font(FDS.TypeScale.body(12))
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(16)
            .forgeGlassCard(accent: Color(hex: (showingPartner ? cycleStore.partnerSnapshot.phase : cycleStore.snapshot.phase).accentHex))
        }
        .buttonStyle(.plain)
    }
}
