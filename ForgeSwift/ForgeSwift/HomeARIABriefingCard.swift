import SwiftUI

struct HomeARIABriefingCard: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedText = ""
    @State private var isTyping = false
    @State private var pulseRing = false

    private var fullBriefing: String {
        HomeARIABriefingBuilder.build(store: store)
    }

    private var typewriterKey: String {
        let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let band = store.readiness.overall / 10
        return "home.aria.typewriter.\(Int(day)).\(band)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.ember.opacity(0.22))
                        .frame(width: 48, height: 48)
                        .blur(radius: 8)
                        .scaleEffect(pulseRing ? 1.35 : 1)
                        .opacity(pulseRing ? 0 : 0.7)
                    Circle()
                        .fill(FDS.Gradient.ember)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text("A")
                                .font(.system(size: 18, weight: .black))
                                .foregroundColor(.white)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("ARIA")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.ember)
                            .tracking(1.4)
                        Text("Briefing")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textMuted)
                    }
                    Text(briefingKicker)
                        .font(.system(size: 11))
                        .foregroundColor(.textMuted)
                }

                Spacer()

                Button {
                    FDS.haptic(.medium)
                    store.openChat(with: fullBriefing, voice: true)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.ember.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.ember)
                    }
                    .overlay(Circle().stroke(Color.ember.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Talk to ARIA")
            }
            .padding(.bottom, 14)

            Button {
                FDS.haptic(.light)
                store.openChat(with: "Continue from today's briefing.", voice: false)
            } label: {
                Text(displayedText.isEmpty && !isTyping ? fullBriefing : displayedText)
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                            .stroke(Color.ember.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ARIA briefing: \(fullBriefing)")
            .padding(.bottom, 14)

            HStack(spacing: 0) {
                briefingChip(icon: "message.fill", label: "Reply") {
                    store.openChat(with: "Let's talk about my day.", voice: false)
                }
                Spacer()
                briefingChip(icon: themedPlanIcon, label: themedPlanLabel) {
                    store.openChat(with: themedPlanPrompt, voice: false)
                }
                Spacer()
                briefingChip(icon: "calendar", label: "Plan week") {
                    store.openChat(with: "Help me plan this week around recovery and training.", voice: false)
                }
            }
        }
        .padding(HomeMetrics.cardPadding)
        .forgeGlassCard(accent: .ember)
        .homeEntrance(delay: 0.18)
        .onAppear {
            // The avatar halo was the one continuous loop on Home that ignored
            // Reduce Motion, while the typewriter beside it already honoured it.
            if !reduceMotion {
                withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) {
                    pulseRing = true
                }
            }
            startTypewriterIfNeeded()
        }
    }

    private var briefingKicker: String {
        let first = store.userProfile.name.components(separatedBy: " ").first ?? ""
        if first.isEmpty { return "A note for you" }
        return "A note for \(first)"
    }

    private var themedPlanLabel: String { "Today’s plan" }

    private var themedPlanIcon: String { "sparkles" }

    private var themedPlanPrompt: String {
        "What should I train today based on my readiness?"
    }

    private func briefingChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            FDS.haptic(.light)
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(label == "Reply" ? .ember : .textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func startTypewriterIfNeeded() {
        let defaults = UserDefaults.standard
        let already = defaults.string(forKey: "home.aria.lastTypewriterKey") == typewriterKey
        let text = fullBriefing

        if already || UIAccessibility.isReduceMotionEnabled {
            displayedText = text
            isTyping = false
            return
        }

        defaults.set(typewriterKey, forKey: "home.aria.lastTypewriterKey")
        displayedText = ""
        isTyping = true
        var idx = 0
        func next() {
            guard idx < text.count else {
                isTyping = false
                return
            }
            let i = text.index(text.startIndex, offsetBy: idx)
            displayedText.append(text[i])
            idx += 1
            let delay: Double = text[i] == " " ? 0.035 : (text[i] == "." ? 0.14 : 0.02)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { next() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { next() }
    }
}

@MainActor
enum HomeARIABriefingBuilder {
    static func build(store: AppStore) -> String {
        let deep = store.dailyMetrics.deepSleep
        let deepStr = deep >= 60 ? "\(deep / 60)h \(deep % 60)m" : "\(deep)m"
        let context = store.makeTrainerContext()
        let theme = store.userProfile.trainingTheme

        let facts = AriaSpeechFacts(
            sessionTitle: store.todayWorkout?.name,
            themeLabel: theme.label
        )

        // Seed a few factual beats; voice engine varies delivery.
        let voiceCore = AriaVoiceEngine.speak(
            intent: .briefing,
            context: context,
            facts: facts,
            themeOverride: theme
        )

        // Candidates are ranked by how much they matter today, then the top two
        // are taken. Previously they were gated and shuffled by the readiness
        // score itself (`score % 3 == 0`, RNG seeded on `score &* 17`), which had
        // two bad consequences: whether ARIA mentioned your partner depended on
        // an unrelated number, and a genuinely urgent beat ("HRV is low at 38ms")
        // could lose a coin flip to filler ("Still aligned to strength"). It also
        // reshuffled the whole briefing whenever readiness moved a single point.
        var beats: [BriefingBeat] = []

        // --- Recovery signals. A deficit outranks a confirmation: being told
        //     something is wrong is more actionable than being told it is fine.
        if store.readiness.sleepQuality < 60 {
            beats.append(.init(text: "Deep sleep was only \(deepStr) — recovery may lag.", priority: .urgent))
        } else if store.readiness.sleepQuality >= 80 {
            beats.append(.init(text: "Deep sleep looked solid (\(deepStr)).", priority: .confirming))
        }
        if store.dailyMetrics.hrv > 0 {
            if store.dailyMetrics.hrv < 40 {
                beats.append(.init(text: "HRV is low at \(store.dailyMetrics.hrv)ms.", priority: .urgent))
            } else if store.dailyMetrics.hrv >= 50 {
                beats.append(.init(text: "HRV holding at \(store.dailyMetrics.hrv)ms.", priority: .confirming))
            }
        }

        // --- Blocks today's action, so it ranks above passive observations.
        if store.todayWorkout == nil {
            beats.append(.init(text: "No session yet — ask me what to train today.", priority: .blocking))
        }

        // --- Support context. The phase-specific line is time-sensitive and
        //     genuinely actionable; the generic nudge is not, so it sits low
        //     rather than being gated on `score % 3`.
        let cycleStore = MenstrualHealthStore.shared
        if let person = cycleStore.mostTimelyPerson {
            let who = person.displayName
            let phase = cycleStore.personSnapshots[person.id]?.phase ?? cycleStore.partnerSnapshot.phase
            let extra = cycleStore.consentedPeople.count > 1
                ? " · \(cycleStore.consentedPeople.count) people"
                : ""
            if phase == .menstruation || phase == .luteal {
                beats.append(.init(
                    text: person.role == .child
                        ? "\(who) may need the soft parent playbook today."
                        : "Keep \(who) in mind — \(phase.shortLabel.lowercased()) energy.",
                    priority: .timely))
            } else {
                beats.append(.init(text: "You're also looking out for \(who)\(extra). Ask me anytime.", priority: .ambient))
            }
        } else if store.userProfile.gender == .male {
            beats.append(.init(text: "Partner or daughter to support? I can learn that context.", priority: .ambient))
        }

        if let emotion = AriaContextStore.shared.context.lifestyleTags.first(where: { $0.hasPrefix("emotion:") && !$0.contains("about_other") }) {
            let raw = emotion.replacingOccurrences(of: "emotion:", with: "")
            if let need = AriaEmotionalNeed(rawValue: raw), need != .crisis {
                beats.append(.init(text: "Still holding space for \(need.label.lowercased()) if you need it.", priority: .timely))
            }
        }

        // --- Pure reassurance, carrying no new information. Kept so a quiet day
        //     still reads warm, but it can only appear when nothing outranks it.
        if let goal = store.userProfile.fitnessGoals.first {
            beats.append(.init(text: "Still aligned to \(goal.label.lowercased()).", priority: .filler))
        }

        // Rank, then break ties on a seed that is stable for the whole day, so
        // repeated glances at Home read consistently instead of reshuffling.
        let daySeed = UInt64(abs(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970.rounded())) &+ 1
        var rng = AriaSeededRNG(seed: daySeed)
        let jittered = beats.map { (beat: $0, tie: rng.int(in: 0..<1000)) }
        let chosen = jittered
            .sorted { ($0.beat.priority.rawValue, $0.tie) > ($1.beat.priority.rawValue, $1.tie) }
            .prefix(2)
            .map { $0.beat.text }

        return ([voiceCore] + chosen).joined(separator: " ")
    }

    /// One candidate line, ranked by how much it matters today.
    private struct BriefingBeat {
        let text: String
        let priority: Priority

        /// Higher wins. The ordering encodes an editorial stance: a deficit you
        /// can act on beats a confirmation that things are fine, and anything
        /// concrete beats reassurance.
        enum Priority: Int {
            case filler     = 10   // true but carries no information
            case ambient    = 20   // a standing offer, not tied to today
            case confirming = 40   // a metric that looks good
            case timely     = 60   // relevant specifically today
            case blocking   = 80   // stops the user acting until resolved
            case urgent     = 100  // a deficit worth changing the plan over
        }
    }
}
