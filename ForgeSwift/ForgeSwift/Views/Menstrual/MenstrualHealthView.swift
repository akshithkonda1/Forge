import SwiftUI

/// Premium menstrual cycle tracker — self tracking + partner relationship sync.
struct MenstrualHealthView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case me, partner
        var id: String { rawValue }
        var label: String {
            switch self {
            case .me: return "My cycle"
            case .partner: return "Partner"
            }
        }
    }

    @EnvironmentObject private var store: AppStore
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pane: Pane = .me
    @State private var selectedFlow: MenstrualFlowLevel = .medium
    @State private var selectedSymptoms: Set<CycleSymptom> = []
    @State private var bbtText = ""
    @State private var partnerFlow: MenstrualFlowLevel = .medium
    @State private var partnerNameDraft = ""
    @State private var partnerRelDraft = "partner"
    @State private var showDisclaimer = false
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                panePicker

                switch pane {
                case .me:
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
                case .partner:
                    partnerContent
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
                .disabled(!cycleStore.settings.enabled || pane != .me)
            }
        }
        .onAppear {
            cycleStore.enableForFemaleProfileIfNeeded(gender: store.userProfile.gender)
            // Males (and anyone) default to Partner pane when self-cycle is off.
            if store.userProfile.gender == .male || store.userProfile.gender != .female {
                if !cycleStore.settings.enabled {
                    pane = .partner
                }
            }
            partnerNameDraft = cycleStore.partnerSettings.partnerName
            partnerRelDraft = cycleStore.partnerSettings.relationshipLabel
            cycleStore.refresh(from: store)
            Task { await cycleStore.syncFromHealthKit() }
            withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pane == .me ? "Menstrual intelligence" : "Partner cycle sync")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(
                pane == .me
                    ? "Multi-signal engine: period starts, BBT, OPK, mucus, symptoms, and personal cycle math."
                    : "Log your partner's period starts (with consent). ARIA coaches you on support, dates, and training together — many couples use this."
            )
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(appeared ? 1 : 0)
    }

    private var panePicker: some View {
        HStack(spacing: 0) {
            ForEach(Pane.allCases) { p in
                Button {
                    withAnimation(FDS.Spring.snap) { pane = p }
                    FDS.selectionHaptic()
                } label: {
                    Text(p.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(pane == p ? .white : .textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(pane == p ? Color.ember : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Partner pane

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
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var partnerEnableCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Support your partner")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("For boyfriends, husbands, and partners who want to show up better. You log period starts she shares with you — ARIA tells you how to plan dates, train together, and communicate by phase.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                cycleStore.updatePartnerSettings {
                    $0.enabled = true
                    $0.shareWithAria = true
                }
                FDS.haptic(.medium)
            } label: {
                Text("Enable partner cycle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "6366F1"))
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "6366F1"))
    }

    private var partnerConsentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Consent first")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("Only track what your partner is comfortable sharing. Period start dates are enough for solid support coaching.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)

            TextField("Partner's name (optional)", text: $partnerNameDraft)
                .textFieldStyle(.roundedBorder)
            TextField("Relationship label (partner / girlfriend / wife…)", text: $partnerRelDraft)
                .textFieldStyle(.roundedBorder)

            Button {
                cycleStore.updatePartnerSettings {
                    $0.consentAcknowledged = true
                    $0.partnerName = partnerNameDraft
                    $0.relationshipLabel = partnerRelDraft.isEmpty ? "partner" : partnerRelDraft
                    $0.shareWithAria = true
                }
                FDS.notificationHaptic(.success)
            } label: {
                Text("I have their okay — continue")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.ember)
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(accent: .warning)
    }

    private var partnerPhaseHero: some View {
        let snap = cycleStore.partnerSnapshot
        let accent = Color(hex: snap.phase.accentHex)
        let name = cycleStore.partnerSettings.displayName
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: snap.phase.icon)
                    .foregroundColor(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(accent)
                    Text(snap.phase.label)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.textPrimary)
                    if let day = snap.dayInCycle {
                        Text("Day \(day) · \(Int(snap.confidence * 100))% confidence")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
            }
            if let next = snap.nextPeriod {
                Text("Next period window: \(shortDate(next.earliestDayKey)) – \(shortDate(next.latestDayKey))")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            }
            Button {
                store.openChat(
                    with: "Help me support \(name) — she's in \(snap.phase.label). What should I do?",
                    voice: false
                )
            } label: {
                Label("Ask ARIA how to show up", systemImage: "message.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(accent)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(accent: accent)
    }

    private func partnerSupportCard(_ brief: PartnerSupportBrief) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOW YOU SHOW UP")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundColor(.textTertiary)
            Text(brief.headline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
            ForEach(brief.supportMoves.prefix(4), id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "22C55E"))
                        .font(.system(size: 12))
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
            }
            Text("Ease off")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
                .padding(.top, 4)
            ForEach(brief.avoidMoves.prefix(3), id: \.self) { line in
                Text("• \(line)")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            }
            Text(brief.communicationTip)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.ember)
                .padding(.top, 6)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "22C55E"))
    }

    private var partnerLogger: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOG FOR \(cycleStore.partnerSettings.displayName.uppercased())")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundColor(.textTertiary)
            Text("Flow today")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([MenstrualFlowLevel.none, .spotting, .light, .medium, .heavy], id: \.self) { level in
                        Button {
                            partnerFlow = level
                            FDS.selectionHaptic()
                        } label: {
                            Text(level.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(partnerFlow == level ? .white : .textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(partnerFlow == level ? Color(hex: "6366F1") : Color.surfaceElevated)
                                .cornerRadius(100)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                cycleStore.logPartnerToday(flow: partnerFlow)
                FDS.notificationHaptic(.success)
            } label: {
                Text("Save partner log for today")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "6366F1"))
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)

            Button {
                cycleStore.logPartnerPeriodStart(flow: partnerFlow == .none ? .medium : partnerFlow)
                FDS.notificationHaptic(.success)
            } label: {
                Text("Mark her period start today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "EF4444"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .forgeGlassCard(accent: Color(hex: "6366F1"))
    }

    private var partnerSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PARTNER SETTINGS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundColor(.textTertiary)
            TextField("Name", text: $partnerNameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    cycleStore.updatePartnerSettings { $0.partnerName = partnerNameDraft }
                }
            TextField("Relationship label", text: $partnerRelDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    cycleStore.updatePartnerSettings {
                        $0.relationshipLabel = partnerRelDraft.isEmpty ? "partner" : partnerRelDraft
                    }
                }
            Button("Save name & label") {
                cycleStore.updatePartnerSettings {
                    $0.partnerName = partnerNameDraft
                    $0.relationshipLabel = partnerRelDraft.isEmpty ? "partner" : partnerRelDraft
                }
                FDS.haptic(.light)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.ember)

            Toggle(isOn: Binding(
                get: { cycleStore.partnerSettings.shareWithAria },
                set: { v in cycleStore.updatePartnerSettings { $0.shareWithAria = v } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share partner cycle with ARIA")
                        .foregroundColor(.textPrimary)
                    Text("ARIA coaches you on support — never medical advice for her.")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
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
                Text("Partner tracking enabled")
                    .foregroundColor(.textPrimary)
            }
            .tint(.ember)
        }
        .padding(18)
        .forgeGlassCard(accent: .steel)
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
    var preferPartner: Bool = false
    var onTap: () -> Void

    private var showingPartner: Bool {
        preferPartner
            || (cycleStore.partnerSettings.enabled && cycleStore.partnerSettings.consentAcknowledged
                && !cycleStore.settings.enabled)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                let phase = showingPartner ? cycleStore.partnerSnapshot.phase : cycleStore.snapshot.phase
                Image(systemName: showingPartner ? "heart.circle.fill" : phase.icon)
                    .foregroundColor(Color(hex: phase.accentHex))
                VStack(alignment: .leading, spacing: 2) {
                    if showingPartner {
                        Text(cycleStore.partnerSettings.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        if let day = cycleStore.partnerSnapshot.dayInCycle {
                            Text("\(phase.shortLabel) · day \(day)")
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        } else {
                            Text(cycleStore.partnerSettings.enabled ? "Partner cycle" : "Set up partner cycle")
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        }
                    } else {
                        Text(cycleStore.settings.enabled ? phase.shortLabel : "Cycle")
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
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(14)
            .forgeGlassCard(accent: Color(hex: (showingPartner ? cycleStore.partnerSnapshot.phase : cycleStore.snapshot.phase).accentHex))
        }
        .buttonStyle(.plain)
    }
}
