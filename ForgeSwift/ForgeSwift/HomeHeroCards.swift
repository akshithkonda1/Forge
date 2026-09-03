import SwiftUI

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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(HomeReadiness.color(store.readiness.overall))
                }
                Spacer()
                Button {
                    FDS.haptic(.light)
                    withAnimation(FDS.Spring.standard) { showDetails.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showDetails ? "Less" : "Details")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(showDetails ? 180 : 0))
                    }
                    .foregroundColor(.ember)
                }
            }
            .padding(.bottom, 20)

            ReadinessRingView(score: store.readiness.overall, size: 112, strokeWidth: 10)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Readiness \(store.readiness.overall) out of 100, \(HomeReadiness.label(store.readiness.overall))")
                .onTapGesture {
                    if store.readiness.overall >= 85 { onCelebrate() }
                }

            Text("\(store.readiness.overall) · \(homeStatusLine(store: store))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, showDetails ? 16 : 0)

            if showDetails {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    BreakdownCardView(label: "Sleep", value: store.readiness.sleepQuality, inverted: false, index: 0)
                    BreakdownCardView(label: "Recovery", value: store.readiness.recoveryScore, inverted: false, index: 1)
                    BreakdownCardView(label: "Stress", value: store.readiness.stressLevel, inverted: true, index: 2)
                    BreakdownCardView(label: "Energy", value: store.readiness.energyBank, inverted: false, index: 3)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))

                VStack(alignment: .leading, spacing: 8) {
                    Text("WHY THIS SCORE")
                        .forgeSectionLabel()
                        .padding(.top, 4)
                    Text(readinessWhyCopy(store: store))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ReadinessInsightRow(
                        icon: "moon.stars.fill",
                        title: "Deep Sleep",
                        value: "\(store.dailyMetrics.deepSleep / 60)h \(store.dailyMetrics.deepSleep % 60)m",
                        color: .steel
                    )
                    ReadinessInsightRow(
                        icon: "waveform.path.ecg.rectangle.fill",
                        title: "HRV",
                        value: "\(store.dailyMetrics.hrv)ms",
                        color: .danger
                    )

                    Button {
                        FDS.haptic(.light)
                        store.openChat(
                            with: "Explain my readiness score of \(store.readiness.overall). Sleep \(store.readiness.sleepQuality), recovery \(store.readiness.recoveryScore), stress \(store.readiness.stressLevel), energy \(store.readiness.energyBank).",
                            voice: false
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Explain my readiness")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.ember)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.ember.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.top, 12)
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

        let hours = store.sleepData.first?.totalHours
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

/// One card: how they live, the session it wrote, the one thing to do.
struct HomeTodayHero: View {
    @EnvironmentObject var store: AppStore
    let action: HomePrimaryAction
    @State private var showScore = false

    private var recovery: Bool { action.usesRecoveryChrome(store: store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today")
                        .forgeSectionLabel()

                    HomeLifeChipRow(chips: HomeLifeSentence.chips(store: store))

                    if let session = store.todayWorkout {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displaySessionName(session.name))
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundColor(.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(homeStatusLine(store: store))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                            Text("\(session.duration) min · \(session.intensity.label)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textTertiary)
                        }
                    } else {
                        Text(homeStatusLine(store: store))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                if store.hasMeaningfulLifeSignal || store.readiness.overall > 0 {
                    Button {
                        FDS.haptic(.light)
                        withAnimation(FDS.Spring.standard) { showScore.toggle() }
                    } label: {
                        VStack(spacing: 4) {
                            ReadinessRingView(
                                score: store.readiness.overall,
                                size: 72,
                                strokeWidth: 7,
                                showLabel: false
                            )
                            .overlay {
                                Text("\(store.readiness.overall)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.textPrimary)
                            }
                            Text(homeStatusLine(store: store))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(HomeReadiness.color(store.readiness.overall))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 80)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Readiness \(store.readiness.overall) out of 100, \(homeStatusLine(store: store))")
                    .accessibilityHint("Shows sleep and recovery detail")
                }
            }

            if showScore {
                HomeReadinessDetailStrip()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HomePrimaryCTA(action: action)
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: recovery ? .steel : .ember)
        .homeEntrance(delay: 0.06)
    }
}

private struct HomeReadinessDetailStrip: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                readinessFact("Sleep", store.readiness.sleepQuality)
                readinessFact("Recovery", store.readiness.recoveryScore)
                readinessFact("HRV", store.dailyMetrics.hrv, unit: "ms")
            }
            Text(readinessWhyCopy(store: store))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func readinessFact(_ label: String, _ value: Int, unit: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.textTertiary)
                .tracking(0.6)
            Text(unit.isEmpty ? "\(value)" : "\(value)\(unit)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeLifeChipRow: View {
    let chips: [HomeLifeSentence.Chip]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(chips) { chip in
                HStack(spacing: 5) {
                    Image(systemName: chip.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(chip.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
        }
    }
}

private struct HomePrimaryCTA: View {
    @EnvironmentObject var store: AppStore
    let action: HomePrimaryAction
    @State private var pressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                FDS.haptic(.medium)
                perform()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: action.icon)
                        .font(.system(size: 16, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let subtitle = action.subtitle(store: store) {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack {
                        if action.usesRecoveryChrome(store: store) {
                            FDS.Gradient.steel
                        } else {
                            FDS.Gradient.ember
                        }
                        LinearGradient.premiumChrome
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.lg, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(
                    color: (action.usesRecoveryChrome(store: store) ? Color.steel : Color.ember).opacity(0.32),
                    radius: 12,
                    y: 5
                )
            }
            .buttonStyle(.plain)
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(FDS.Spring.snap, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
            .accessibilityLabel(action.title)
            .accessibilityHint(action.subtitle(store: store) ?? "Double tap to activate")

            HStack(spacing: 10) {
                Button {
                    FDS.haptic(.light)
                    let sentence = HomeLifeSentence.build(store: store)
                    store.openChat(
                        with: "Why this session today? \(sentence.text). \(sentence.detail ?? "") Adjust it if my life doesn't match.",
                        voice: false
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Why this session")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    FDS.haptic(.light)
                    store.activeTab = .lifestyle
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Lifestyle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color.vitality)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                            .stroke(Color.vitality.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func perform() {
        switch action {
        case .startWorkout, .continueWorkout, .recoveryDay, .buildPlan:
            store.startLifeShapedSession()
        }
    }
}
