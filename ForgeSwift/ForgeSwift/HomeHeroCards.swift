import SwiftUI
import ForgeCore

private struct HomeHeroReadinessCard: View {
    @EnvironmentObject var store: AppStore
    var onCelebrate: () -> Void = {}
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("READINESS")
                        .forgeSectionLabel()
                    Text(homeStatusLine(store: store))
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(HomeReadiness.color(store.readiness.overall))
                }
                Spacer()
                Button {
                    withForgeMotion(ForgeMotion.smooth) { showDetails.toggle() }
                } label: {
                    HStack(spacing: FDS.Spacing.xs) {
                        Text(showDetails ? "Less" : "Details")
                            .font(FDS.TypeScale.Dynamic.caption)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(showDetails ? 180 : 0))
                    }
                    .foregroundColor(.ember)
                }
            }
            .padding(.bottom, FDS.Spacing.lg)

            ReadinessRingView(score: store.readiness.overall, size: 112, strokeWidth: 10)
                .frame(maxWidth: .infinity)
                .padding(.bottom, FDS.Spacing.md)
                .onTapGesture {
                    if store.readiness.overall >= 85 { onCelebrate() }
                }

            Text("\(store.readiness.overall) · \(homeStatusLine(store: store))")
                .font(ForgeType.bodyStrong)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, showDetails ? 16 : 0)

            if showDetails {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FDS.Spacing.sm) {
                    BreakdownCardView(label: "Sleep", value: lastNightSleepMeasured(store: store) ? store.readiness.sleepQuality : nil, inverted: false, index: 0)
                    BreakdownCardView(label: "Recovery", value: store.readiness.recoveryScore, inverted: false, index: 1)
                    BreakdownCardView(label: "Stress", value: store.readiness.stressLevel, inverted: true, index: 2)
                    BreakdownCardView(label: "Energy", value: store.readiness.energyBank, inverted: false, index: 3)
                }
                .forgeTransition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))

                VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
                    Text("WHY THIS SCORE")
                        .forgeSectionLabel()
                        .padding(.top, FDS.Spacing.xs)
                    Text(readinessWhyCopy(store: store))
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ReadinessInsightRow(
                        icon: "moon.stars.fill",
                        title: "Deep Sleep",
                        value: lastNightSleepMeasured(store: store)
                            ? "\(store.dailyMetrics.deepSleep / 60)h \(store.dailyMetrics.deepSleep % 60)m"
                            : "—",
                        color: .steel
                    )
                    ReadinessInsightRow(
                        icon: "waveform.path.ecg.rectangle.fill",
                        title: "HRV",
                        value: "\(store.dailyMetrics.hrv)ms",
                        color: .danger
                    )

                    Button {
                        // Don't ask ARIA to explain a sleep number nobody measured.
                        let sleep = lastNightSleepMeasured(store: store)
                            ? "Sleep \(store.readiness.sleepQuality), recovery"
                            : "No sleep recorded last night. Recovery"
                        store.openChat(
                            with: "Explain my readiness score of \(store.readiness.overall). \(sleep) \(store.readiness.recoveryScore), stress \(store.readiness.stressLevel), energy \(store.readiness.energyBank).",
                            voice: false
                        )
                    } label: {
                        HStack(spacing: FDS.Spacing.xs) {
                            ARIAIdentityMark(state: .idle, mood: .energized, size: 14, amplitude: 0.22)
                            Text("Explain my readiness")
                                .font(FDS.TypeScale.Dynamic.caption)
                        }
                        .foregroundColor(.ember)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FDS.Spacing.sm)
                        .background(Color.ember.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, FDS.Spacing.xs)
                }
                .padding(.top, FDS.Spacing.md)
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: HomeReadiness.color(store.readiness.overall))
        .homeEntrance(delay: 0.12)
    }
}

/// Reads `AppStore` and `MenstrualHealthStore.shared`, both of which are
/// `@MainActor`, so this is too. Without the annotation the two static functions
/// below are nonisolated and every property access is an error — eleven of them.
/// Both call sites are already on the main actor (a `View` body and a Button
/// action), so nothing at the call sites changes.
@MainActor
enum HomeLifeSentence {
    struct Line {
        let text: String
        let detail: String?
    }

    struct Chip: Identifiable {
        let id: String
        let icon: String
        let label: String
    }

    static func chips(store: AppStore) -> [Chip] {
        var chips: [Chip] = []

        let hours = SleepData.lastNight(in: store.sleepData)?.totalHours
            ?? (store.dailyMetrics.totalSleep > 0 ? Double(store.dailyMetrics.totalSleep) / 60.0 : nil)
        if let hours {
            chips.append(.init(id: "sleep", icon: "moon.fill", label: String(format: "%.1fh sleep", hours)))
        }

        let cycle = MenstrualHealthStore.shared
        if cycle.settings.enabled, cycle.snapshot.phase != .unknown {
            let label = cycle.snapshot.dayInCycle.map { "\(cycle.snapshot.phase.shortLabel) · \($0)" }
                ?? cycle.snapshot.phase.shortLabel
            chips.append(.init(id: "cycle", icon: cycle.snapshot.phase.icon, label: label))
        }

        let gear: String = {
            switch store.userProfile.trainingEquipment {
            case .commercialGym: return "Gym"
            case .homeGym: return "Home"
            case .bodyweight: return "No gear"
            case .hotelGym: return "Travel"
            case .crossfitBox: return "Box"
            }
        }()
        chips.append(.init(id: "gear", icon: store.userProfile.trainingEquipment.icon, label: gear))
        return chips
    }

    static func build(store: AppStore) -> Line {
        let text = chips(store: store).map(\.label).joined(separator: " · ")
        let detail: String?
        if let session = store.todayWorkout {
            detail = "\(session.name) · \(session.duration) min · \(session.intensity.label)"
        } else {
            detail = "Today’s session will be written from this — not a catalog."
        }
        return Line(text: text, detail: detail)
    }
}

/// One card: today's progress ring, readiness vibe, the session, the one thing to do.
struct HomeTodayHero: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let action: HomePrimaryAction
    @State private var showScore = false
    @State private var eventGlow = false

    private var recovery: Bool { action.usesRecoveryChrome(store: store) }
    private var showInArcMeta: Bool {
        HomeReadinessTokens.showsInArcMeta(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    private var aging: AgingSnapshot {
        AgingBridge.snapshot(store: store)
    }

    private var progress: TodayProgress.Snapshot {
        let habits = LifestyleWellbeingStore.loadHabits()
        let water = HealthKitManager.shared.todayStats?.water ?? 0
        return TodayProgress.snapshot(.from(store: store, waterGlasses: water, habits: habits))
    }

    var body: some View {
        let snap = progress
        let energy = HudChrome.energy(for: snap.vibeScore)
        VStack(alignment: .leading, spacing: HomeMetrics.heroStackGap) {
            HStack {
                Text(TodayProgress.headerTitle)
                    .forgeSectionLabel()
                    .foregroundStyle(HudChrome.plate)
                Spacer()
                HudVibeChip(label: snap.vibeLabel, energy: energy)
            }

            HudProgressRing(
                progress: snap.percent,
                energy: energy,
                almostThere: snap.almostThere,
                eventGlow: eventGlow
            ) {
                VStack(spacing: 2) {
                    Text("\(snap.percent)")
                        .font(HomeType.heroScore)
                        .foregroundStyle(Color.textPrimary)
                        .hudInArcText()
                        .contentTransition(.numericText(value: Double(snap.percent)))
                        .forgeAnimation(ForgeMotion.smooth, value: snap.percent)
                    if showInArcMeta {
                        Text(snap.vibeLabel.uppercased())
                            .font(HomeType.micro)
                            .foregroundColor(energy)
                            .tracking(1.6)
                            .hudInArcText()
                        Text("\(snap.completed)/\(snap.total)")
                            .font(HomeType.micro)
                            .foregroundColor(HudChrome.plate.opacity(0.72))
                            .hudInArcText()
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snap.voiceOverLabel)

            if !showInArcMeta {
                Text("\(snap.vibeLabel) · \(snap.completed)/\(snap.total)")
                    .font(HomeType.micro)
                    .foregroundColor(energy)
                    .hudInArcText()
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }

            Text(snap.vibeLine)
                .font(HomeType.status)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)

            TodayTrackRow(tracks: snap.tracks, closingTrackID: snap.closingTrackID)

            if store.hasMeaningfulLifeSignal || store.readiness.overall > 0 {
                HomeVitalsRow(
                    sleep: store.readiness.sleepQuality,
                    recovery: store.readiness.recoveryScore,
                    load: store.readiness.stressLevel
                ) {
                    withForgeMotion(ForgeMotion.smooth) { showScore.toggle() }
                }
            }

            HomeLifeChipRow(chips: HomeLifeSentence.chips(store: store))

            if let session = store.todayWorkout {
                VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                    Text(displaySessionName(session.name))
                        .font(HomeType.sessionTitle)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(session.duration) min · \(session.intensity.label)")
                        .font(HomeType.label)
                        .foregroundColor(.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(displaySessionName(session.name)), \(session.duration) minutes, \(session.intensity.label)"
                )
            }

            if !aging.oneBreathLine.isEmpty {
                Button {
                    store.activeTab = .lifestyle
                    store.pendingLifestyleSegment = "lifetime"
                } label: {
                    Text(aging.oneBreathLine)
                        .font(HomeType.status)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(aging.oneBreathLine)
                .accessibilityHint("Opens Lifestyle Lifetime for the age comparison")
            }

            if showScore {
                HomeReadinessDetailStrip()
                    .forgeTransition(.opacity.combined(with: .move(edge: .top)))
            }

            HomePrimaryCTA(action: action)
        }
        .hudPlate(energy: recovery ? .steel : energy)
        .homeEntrance(delay: 0.06)
        .accessibilityElement(children: .contain)
        // Closing the day is the goal; a single track ticking over is not.
        .forgeHaptic(.success, trigger: snap.completed) { old, new in
            new > old && new >= snap.total
        }
        .onChange(of: snap.completed) { old, new in
            guard new > old else { return }
            eventGlow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                eventGlow = false
            }
        }
    }
}

private struct TodayTrackRow: View {
    let tracks: [TodayProgress.Track]
    var closingTrackID: String? = nil

    var body: some View {
        HStack(spacing: FDS.Spacing.xs) {
            ForEach(tracks) { track in
                let closing = track.id == closingTrackID
                VStack(spacing: FDS.Spacing.xs) {
                    ZStack {
                        Circle()
                            .fill(
                                track.done
                                    ? HudChrome.plate.opacity(0.16)
                                    : (closing ? HudChrome.plate.opacity(0.12) : HudChrome.miss.opacity(0.10))
                            )
                            .frame(width: 28, height: 28)
                        if closing {
                            Circle()
                                .stroke(HudChrome.plate.opacity(0.55), lineWidth: 1)
                                .frame(width: 28, height: 28)
                        }
                        Image(systemName: track.done ? "checkmark" : track.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                track.done
                                    ? HudChrome.plate
                                    : (closing ? HudChrome.plate : HudChrome.miss)
                            )
                    }
                    Text(track.title)
                        .font(HomeType.micro)
                        .foregroundColor(
                            track.done || closing ? .textPrimary : .textTertiary
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    closing
                        ? "\(track.title), \(track.detail). One left — close the ring."
                        : "\(track.title), \(track.detail)"
                )
            }
        }
    }
}

private struct HomeReadinessDetailStrip: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            HStack(spacing: FDS.Spacing.sm) {
                readinessFact("Sleep", lastNightSleepMeasured(store: store) ? store.readiness.sleepQuality : nil)
                readinessFact("Recovery", store.readiness.recoveryScore)
                readinessFact("HRV", store.dailyMetrics.hrv, unit: "ms")
            }
            Text(readinessWhyCopy(store: store))
                .font(HomeType.body)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FDS.Spacing.md)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// A nil value (nothing measured) shows "—" rather than a fallback number.
    private func readinessFact(_ label: String, _ value: Int?, unit: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(HomeType.micro)
                .foregroundColor(.textTertiary)
                .tracking(0.6)
            Text(value.map { unit.isEmpty ? "\($0)" : "\($0)\(unit)" } ?? "—")
                .font(HomeType.metric)
                .foregroundColor(.textPrimary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.map { unit.isEmpty ? "\(label) \($0)" : "\(label) \($0) \(unit)" } ?? "\(label) not recorded")
    }
}

private struct HomeLifeChipRow: View {
    let chips: [HomeLifeSentence.Chip]

    var body: some View {
        FlowLayout(spacing: ForgeLayout.chipGap) {
            ForEach(chips) { chip in
                HStack(spacing: FDS.Spacing.xs) {
                    Image(systemName: chip.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(chip.label)
                        .font(HomeType.label)
                }
                .foregroundColor(.textPrimary)
                .padding(.horizontal, FDS.Spacing.sm)
                .padding(.vertical, FDS.Spacing.sm)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chips.map(\.label).joined(separator: ", "))
    }
}

private struct HomePrimaryCTA: View {
    @EnvironmentObject var store: AppStore
    let action: HomePrimaryAction

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text(HomeCoachCopy.nextNowEyebrow(isLighter: action.usesRecoveryChrome(store: store)))
                .font(HomeType.micro)
                .foregroundColor(.textTertiary)
                .tracking(1.2)
                .accessibilityAddTraits(.isHeader)

            Button(action: perform) {
                HStack(spacing: FDS.Spacing.md) {
                    Image(systemName: action.icon)
                        .font(.system(size: 16, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(HomeType.cta)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let subtitle = action.subtitle(store: store) {
                            Text(subtitle)
                                .font(HomeType.micro)
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: FDS.Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .accessibilityHidden(true)
                }
                .foregroundColor(.white)
                .padding(.vertical, FDS.Spacing.md)
                .padding(.horizontal, FDS.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack {
                        FDS.Gradient.ember
                        LinearGradient.premiumChrome
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                )
            }
            .buttonStyle(ForgePressStyle(pressHaptic: true))
            .accessibilityLabel(action.title)
            .accessibilityHint(action.subtitle(store: store) ?? "Opens today's session")

            HStack(spacing: FDS.Spacing.sm) {
                Button {
                    let sentence = HomeLifeSentence.build(store: store)
                    store.openChat(
                        with: "Why this session today? \(sentence.text). \(sentence.detail ?? "") Adjust it if my life doesn't match.",
                        voice: false
                    )
                } label: {
                    HStack(spacing: FDS.Spacing.xs) {
                        // One live mark per screen: Today chrome is the HUD
                        // ring, so this 14pt Nest mark stays still.
                        ARIAIdentityMark(state: .idle, mood: .energized, size: 14, amplitude: 0.22)
                            .environment(\.forgeMinimalAnimation, true)
                        Text("Why this session")
                            .font(HomeType.label)
                    }
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FDS.Spacing.sm)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Why this session")
                .accessibilityHint("Asks ARIA why today's session looks like this")

                Button {
                    store.activeTab = .lifestyle
                } label: {
                    HStack(spacing: FDS.Spacing.xs) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Lifestyle")
                            .font(HomeType.label)
                    }
                    .foregroundColor(Color.vitality)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FDS.Spacing.sm)
                    .background(Color.vitality.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                            .stroke(Color.vitality.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lifestyle")
                .accessibilityHint("Opens the Lifestyle tab")
            }
        }
    }

    private func perform() {
        switch action {
        case .startWorkout, .recoveryDay, .buildPlan:
            store.openTrainHome()
        case .continueWorkout:
            store.startExistingWorkout()
        }
    }
}
