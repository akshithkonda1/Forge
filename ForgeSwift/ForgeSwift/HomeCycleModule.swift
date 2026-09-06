import SwiftUI
import ForgeCore

/// Primary entry into Cycle Health. Not a bottom tab — the shell presents the page.
struct HomeCycleModule: View {
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    @EnvironmentObject private var store: AppStore
    var onOpen: () -> Void

    /// Same rule `CycleHealthLaunch` uses so the tile and the opened pane match.
    private var preferPartner: Bool {
        !cycleStore.settings.enabled
            && store.userProfile.gender != .female
            && store.userProfile.biologicalSex?.cycleAutoEnabled != true
    }

    private var phase: MenstrualPhase {
        if stealthHome { return .unknown }
        if preferPartner || (!cycleStore.consentedPeople.isEmpty && !cycleStore.settings.enabled) {
            if let person = cycleStore.mostTimelyPerson,
               let snap = cycleStore.personSnapshots[person.id] {
                return snap.phase
            }
            return cycleStore.partnerSnapshot.phase
        }
        return cycleStore.snapshot.phase
    }

    private var accent: Color { Color(hex: phase.accentHex) }

    private var stealthHome: Bool {
        cycleStore.settings.enabled && cycleStore.settings.discretionMode == .stealth
    }

    private var kindHome: Bool {
        cycleStore.settings.enabled && cycleStore.settings.discretionMode == .kind
    }

    private var title: String {
        if stealthHome { return "Cycle Health" }
        if kindHome { return CycleDiscretionMode.kind.lockSafeLine }
        if cycleStore.settings.enabled, let day = cycleStore.snapshot.dayInCycle {
            return "\(cycleStore.snapshot.phase.label) · Day \(day)"
        }
        if cycleStore.consentedPeople.count > 1 {
            return "Supporting \(cycleStore.consentedPeople.count) people"
        }
        if let person = cycleStore.selectedPerson ?? cycleStore.consentedPeople.first,
           person.settings.enabled, person.settings.consentAcknowledged {
            let name = person.displayName
            if let day = (cycleStore.personSnapshots[person.id] ?? cycleStore.partnerSnapshot).dayInCycle {
                return "\(name) · Day \(day)"
            }
            return "Supporting \(name)"
        }
        return "Cycle Health"
    }

    private var subtitle: String {
        if stealthHome {
            return CyclePrivacy.shortPromise
        }
        if kindHome {
            return "Open Cycle Health for your log"
        }
        if cycleStore.settings.enabled {
            return cycleStore.snapshot.trainingNote
        }
        if !cycleStore.consentedPeople.isEmpty {
            if cycleStore.consentedPeople.count > 1 {
                return cycleStore.consentedPeople.map { $0.role.shortLabel }.joined(separator: " · ")
            }
            return "Family support · open to log or ask ARIA"
        }
        return "Private by design — invite someone only if you want support"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("CYCLE")
                        .forgeSectionLabel()
                    Spacer()
                    Text("Open")
                        .font(FDS.TypeScale.label(12))
                        .foregroundStyle(accent)
                }

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(accent.opacity(0.22), lineWidth: 6)
                            .frame(width: 56, height: 56)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                        Image(systemName: phase.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(FDS.TypeScale.title(17))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(FDS.TypeScale.body(12))
                            .foregroundColor(.textTertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }

                // Mini chips
                HStack(spacing: 8) {
                    if stealthHome {
                        miniChip("Private", Color.vitality)
                    } else if kindHome {
                        miniChip("Take it easy", Color.indigo)
                        miniChip("Private", Color.vitality)
                    } else if cycleStore.settings.enabled {
                        miniChip("\(Int(cycleStore.snapshot.confidence * 100))% conf", accent)
                        if let next = cycleStore.snapshot.nextPeriod {
                            miniChip("Next \(shortDate(next.medianDayKey))", Color.alert)
                        }
                    } else if !cycleStore.consentedPeople.isEmpty {
                        ForEach(cycleStore.consentedPeople.prefix(3)) { person in
                            miniChip(person.role.shortLabel, Color.indigo)
                        }
                        if let snap = cycleStore.mostTimelyPerson.flatMap({ cycleStore.personSnapshots[$0.id] }) {
                            miniChip(snap.phase.shortLabel, accent)
                        }
                    } else {
                        miniChip("My cycle", Color.alert)
                        miniChip("Support", Color.indigo)
                    }
                    miniChip("Private", Color.vitality)
                    Spacer()
                }

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.vitality)
                    Text(CyclePrivacy.shortPromise)
                        .font(FDS.TypeScale.body(11))
                        .foregroundColor(.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(HomeMetrics.cardPadding)
            .forgeGlassCard(accent: accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cycle Health, \(title). \(CyclePrivacy.shortPromise)")
        .accessibilityHint("Opens private cycle tracking from Home")
    }

    private var progress: CGFloat {
        let snap: MenstrualCycleSnapshot = {
            if preferPartner || !cycleStore.settings.enabled {
                if let person = cycleStore.mostTimelyPerson,
                   let s = cycleStore.personSnapshots[person.id] {
                    return s
                }
                return cycleStore.partnerSnapshot
            }
            return cycleStore.snapshot
        }()
        guard let day = snap.dayInCycle else { return 0.12 }
        let len = max(21, min(45, snap.cycleLengthMedian))
        return min(0.95, CGFloat(day) / CGFloat(len))
    }

    private func miniChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(FDS.TypeScale.micro(10))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
    }

    private func shortDate(_ key: String) -> String {
        guard let d = CycleDayKey.date(from: key) else { return key }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

struct HomeSupportPulseCard: View {
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared
    var onOpen: () -> Void

    /// One accent for the whole card. The icon used to take the live phase colour
    /// while the card border was hardcoded indigo, so the two fought each other.
    private var pulsePerson: SupportedPerson? { cycleStore.mostTimelyPerson }
    private var pulseSnapshot: MenstrualCycleSnapshot {
        if let id = pulsePerson?.id { return cycleStore.personSnapshots[id] ?? cycleStore.partnerSnapshot }
        return cycleStore.partnerSnapshot
    }
    private var accent: Color { Color(hex: pulseSnapshot.phase.accentHex) }
    private var pulseBriefLine: String {
        if let id = pulsePerson?.id, let brief = cycleStore.personBriefs[id] {
            return brief.headline
        }
        if cycleStore.consentedPeople.count > 1 {
            let others = cycleStore.consentedPeople
                .filter { $0.id != pulsePerson?.id }
                .prefix(2)
                .map(\.displayName)
            if !others.isEmpty {
                return "Also \(others.joined(separator: ", "))"
            }
        }
        return cycleStore.partnerSupportBrief?.headline ?? "Open cycle support"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: pulseSnapshot.phase.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.15))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(cycleStore.consentedPeople.count > 1 ? "SUPPORTING \(cycleStore.consentedPeople.count)" : "SUPPORTING")
                        .forgeSectionLabel()
                    Text("\(pulsePerson?.displayName ?? cycleStore.partnerSettings.displayName) · \(pulseSnapshot.phase.shortLabel)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(pulseBriefLine)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            .padding(HomeMetrics.cardPadding)
            .forgeGlassCard(accent: accent)
        }
        .buttonStyle(.plain)
    }
}
