import Foundation

// MARK: - Intent

/// What ARIA is trying to do in this turn — drives which phrase banks fire.
enum AriaSpeechIntent: String, CaseIterable {
    case greeting
    case trainingPlan
    case lowEnergy
    case sleep
    case pain
    case progress
    case gratitude
    case motivation
    case fallback
    case briefing
    case checkIn
    case themeLock
}

// MARK: - Voice axes (combinatorial space)

/// Formality / register of speech.
enum AriaRegister: String, CaseIterable {
    case street      // "yo", short, raw
    case peer        // friend-coach
    case pro         // polished coach
    case clinical    // metrics-first scientist
    case mythic      // theme-heavy (System, Corps, crew)
}

/// Emotional energy of delivery.
enum AriaEnergy: String, CaseIterable {
    case hype        // charged, short punches
    case steady      // calm confidence
    case soft        // gentle, spacious
    case razor       // sharp, zero fluff
    case warm        // encouraging, human
}

/// How much metaphor / theme vocabulary bleeds into copy.
enum AriaMetaphorDensity: String, CaseIterable {
    case none
    case light
    case saturated
}

/// How blunt ARIA is about hard truths.
enum AriaDirectness: String, CaseIterable {
    case blunt
    case straight
    case gentle
}

/// Humor dial.
enum AriaHumor: String, CaseIterable {
    case none
    case dry
    case playful
}

/// Response length bias.
enum AriaSpeechLength: String, CaseIterable {
    case tight       // 1–2 beats
    case medium      // 3–4 beats
    case expansive   // full coaching monologue
}

/// Resolved voice for a single turn — product of many independent axes.
struct AriaVoiceProfile: Equatable {
    var register: AriaRegister
    var energy: AriaEnergy
    var metaphor: AriaMetaphorDensity
    var directness: AriaDirectness
    var humor: AriaHumor
    var length: AriaSpeechLength
    var theme: AriaTrainingTheme
    var coaching: CoachingStyle
    var firstName: String
    var readiness: Int
    var relationshipLevel: Int
    var guidanceOnly: Bool
    var hour: Int
    /// Deterministic salt so the same inputs still rotate phrasing across turns.
    var salt: UInt64

    /// Compact description for Foundation Models system prompts.
    var promptDirective: String {
        """
        Speak as ARIA with this voice profile (follow it tightly):
        - Register: \(register.rawValue)
        - Energy: \(energy.rawValue)
        - Metaphor density: \(metaphor.rawValue) (theme: \(theme.label))
        - Directness: \(directness.rawValue)
        - Humor: \(humor.rawValue)
        - Length: \(length.rawValue)
        - Coaching style preference: \(coaching.label)
        - User: \(firstName.isEmpty ? "athlete" : firstName), readiness \(readiness)/100, relationship level \(relationshipLevel)
        - Never invent medical advice; lifestyle coaching only\(guidanceOnly ? " (guidance-only mode ON)" : "").
        - Adaptive: work inside their actual day. One small change. Compound interest. They choose.
        Vary phrasing — do not reuse stock lines. Sound like one continuous coach who knows this human.
        """
    }
}

// MARK: - Seeded picker

/// Tiny deterministic RNG so responses vary without pure chaos / flaky UI tests.
struct AriaSeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        // splitmix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(in range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        let span = UInt64(range.count)
        return range.lowerBound + Int(next() % span)
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(in: 0..<items.count)]
    }

    mutating func chance(_ p: Double) -> Bool {
        Double(next() % 10_000) / 10_000.0 < p
    }
}

// MARK: - Voice Engine

/// Composes ARIA speech across infinite-feeling combinations of style axes,
/// theme lexicon, coaching style, readiness, time, and relationship depth.
enum AriaVoiceEngine {

    // MARK: Profile resolution

    static func resolveProfile(
        context: TrainerContext,
        intent: AriaSpeechIntent,
        input: String = "",
        themeOverride: AriaTrainingTheme? = nil
    ) -> AriaVoiceProfile {
        let theme = themeOverride ?? AriaThemeResolver.resolve(
            input: input,
            preferred: context.userProfile.trainingTheme,
            lifestyleTags: context.lifestyleTags,
            freeTimeTags: context.userProfile.interestTags
        )
        let coaching = context.userProfile.coachingStyle
        let readiness = context.readiness.overall
        let name = context.userProfile.name.split(separator: " ").first.map(String.init) ?? ""
        let guidance = context.constraints.contains { $0.contains("guidance_only") || $0.hasPrefix("condition:") }
        let rel = max(1, relationshipLevel(from: context))

        let salt = hashSeed(
            name: name,
            intent: intent.rawValue,
            input: input,
            readiness: readiness,
            hour: context.hour,
            day: Calendar.current.ordinality(of: .day, in: .year, for: context.currentTime) ?? 0,
            msgCount: context.totalMessageCount
        )

        var rng = AriaSeededRNG(seed: salt)

        // Base axes from coaching style
        var register: AriaRegister
        var energy: AriaEnergy
        var directness: AriaDirectness
        var humor: AriaHumor
        var length: AriaSpeechLength

        switch coaching {
        case .pushHard:
            register = rng.pick([.street, .peer, .pro])
            energy = rng.pick([.hype, .razor, .steady])
            directness = .blunt
            humor = rng.pick([.dry, .none, .none])
            length = rng.pick([.tight, .medium])
        case .balanced:
            register = rng.pick([.peer, .pro, .peer])
            energy = rng.pick([.steady, .warm, .steady])
            directness = .straight
            humor = rng.pick([.dry, .playful, .none])
            length = .medium
        case .patient:
            register = rng.pick([.peer, .pro, .peer])
            energy = rng.pick([.soft, .warm, .steady])
            directness = .gentle
            humor = rng.pick([.playful, .none, .dry])
            length = rng.pick([.medium, .expansive])
        case .dataDriven:
            register = rng.pick([.clinical, .pro])
            energy = rng.pick([.steady, .razor])
            directness = .straight
            humor = .none
            length = rng.pick([.medium, .tight])
        case .ultraElite:
            register = rng.pick([.pro, .clinical, .mythic])
            energy = rng.pick([.razor, .steady, .hype])
            directness = rng.pick([.blunt, .straight])
            humor = rng.pick([.none, .dry])
            length = rng.pick([.tight, .medium])
        }

        // Readiness shifts energy
        if readiness < 50 {
            energy = rng.pick([.soft, .warm, .steady])
            if directness == .blunt && coaching != .pushHard {
                directness = .straight
            }
        } else if readiness >= 85 {
            if coaching == .pushHard || coaching == .ultraElite {
                energy = rng.pick([.hype, .razor, .hype])
            }
        }

        // Time-of-day
        if context.isEarlyMorning {
            energy = rng.pick([.soft, .steady, energy])
            length = length == .expansive ? .medium : length
        } else if context.isLateNight {
            energy = rng.pick([.soft, .warm, .steady])
            register = register == .street ? .peer : register
        }

        // Theme → metaphor density + mythic register
        var metaphor: AriaMetaphorDensity = .none
        if theme != .classic {
            metaphor = rng.pick([.light, .saturated, .light, .saturated])
            if metaphor == .saturated {
                register = rng.chance(0.65) ? .mythic : register
            }
        }

        // Intent overrides
        switch intent {
        case .pain:
            energy = .steady
            directness = .straight
            humor = .none
            metaphor = metaphor == .saturated ? .light : metaphor
            length = .medium
        case .lowEnergy:
            energy = rng.pick([.soft, .warm, .steady])
            directness = coaching == .pushHard ? .straight : .gentle
        case .motivation:
            energy = rng.pick([.hype, .razor, .warm])
            length = rng.pick([.medium, .expansive, .tight])
        case .gratitude:
            energy = .warm
            length = .tight
            humor = rng.pick([.dry, .playful, .none])
        case .sleep, .progress:
            if coaching == .dataDriven { register = .clinical }
            length = rng.pick([.medium, .expansive])
        case .fallback:
            length = .tight
            humor = rng.pick([.dry, .playful, .none])
        case .briefing:
            length = .tight
            energy = readiness >= 80 ? rng.pick([.steady, .hype]) : rng.pick([.steady, .soft])
        case .trainingPlan, .themeLock, .greeting, .checkIn:
            break
        }

        // Relationship: closer friends get more street/playful
        if rel >= 6 {
            if rng.chance(0.4), register == .pro { register = .peer }
            if humor == .none, rng.chance(0.35) { humor = .dry }
        } else if rel <= 2 {
            if register == .street { register = .peer }
            humor = humor == .playful ? .dry : humor
        }

        // Guidance-only softens everything
        if guidance {
            directness = directness == .blunt ? .straight : directness
            energy = energy == .hype ? .steady : energy
            humor = .none
        }

        // Input tone matching — mirror user energy lightly + explicit voice requests
        let lower = input.lowercased()
        if lower.contains("!!!") || lower.contains("let's go") || lower.contains("hype me") || lower.contains("be hype") {
            energy = .hype
        }
        if lower.contains("please") || lower.contains("gently") || lower.contains("soft") || lower.contains("be gentle") {
            energy = .soft
            directness = .gentle
        }
        if lower.contains("just the facts") || lower.contains("numbers only") || lower.contains("be clinical")
            || lower.contains("data mode") || lower.contains("talk data") {
            register = .clinical
            metaphor = .none
            humor = .none
            length = .tight
        }
        if lower.contains("be real") || lower.contains("no bs") || lower.contains("straight") || lower.contains("no fluff") {
            directness = .blunt
            length = .tight
        }
        if lower.contains("be funny") || lower.contains("joke") || lower.contains("lighten up") {
            humor = .playful
        }
        if lower.contains("keep it short") || lower.contains("tl;dr") || lower.contains("brief") {
            length = .tight
        }
        if lower.contains("go deep") || lower.contains("explain more") || lower.contains("in detail") {
            length = .expansive
        }
        if lower.contains("mythic") || lower.contains("in character") || lower.contains("full theme") {
            metaphor = .saturated
            register = .mythic
        }
        if lower.contains("no theme") || lower.contains("drop the bit") || lower.contains("serious coach") {
            metaphor = .none
            if register == .mythic { register = .pro }
        }

        // Sticky voice tags from living context (voice:hype, voice:clinical, …)
        for tag in context.lifestyleTags where tag.hasPrefix("voice:") {
            switch tag {
            case "voice:hype": energy = .hype
            case "voice:soft": energy = .soft; directness = .gentle
            case "voice:clinical": register = .clinical; humor = .none; metaphor = .none
            case "voice:street": register = .street
            case "voice:mythic": register = .mythic; metaphor = .saturated
            case "voice:tight": length = .tight
            case "voice:expansive": length = .expansive
            case "voice:playful": humor = .playful
            case "voice:blunt": directness = .blunt
            default: break
            }
        }

        return AriaVoiceProfile(
            register: register,
            energy: energy,
            metaphor: metaphor,
            directness: directness,
            humor: humor,
            length: length,
            theme: theme,
            coaching: coaching,
            firstName: name,
            readiness: readiness,
            relationshipLevel: rel,
            guidanceOnly: guidance,
            hour: context.hour,
            salt: salt
        )
    }

    private static func relationshipLevel(from context: TrainerContext) -> Int {
        // Infer from conversation depth + tags when full AriaContext isn't on TrainerContext.
        let chatDepth = min(8, context.totalMessageCount / 4)
        if context.lifestyleTags.contains(where: { $0.contains("onboarding:complete") }) {
            return max(2, chatDepth + 2)
        }
        return max(1, chatDepth + 1)
    }

    private static func hashSeed(
        name: String,
        intent: String,
        input: String,
        readiness: Int,
        hour: Int,
        day: Int,
        msgCount: Int
    ) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        let material = "\(name)|\(intent)|\(input.prefix(48))|\(readiness)|\(hour)|\(day)|\(msgCount)"
        for b in material.utf8 {
            h ^= UInt64(b)
            h &*= 1099511628211
        }
        return h
    }

    // MARK: - Compose

    /// Full multi-beat speech for an intent + factual payload.
    static func speak(
        intent: AriaSpeechIntent,
        context: TrainerContext,
        input: String = "",
        facts: AriaSpeechFacts = AriaSpeechFacts(),
        themeOverride: AriaTrainingTheme? = nil
    ) -> String {
        let profile = resolveProfile(
            context: context,
            intent: intent,
            input: input,
            themeOverride: themeOverride
        )
        return compose(intent: intent, profile: profile, context: context, facts: facts, input: input)
    }

    static func compose(
        intent: AriaSpeechIntent,
        profile: AriaVoiceProfile,
        context: TrainerContext,
        facts: AriaSpeechFacts,
        input: String
    ) -> String {
        var rng = AriaSeededRNG(seed: profile.salt)
        let beats: [String]

        switch intent {
        case .greeting:
            beats = greetingBeats(profile: profile, context: context, rng: &rng)
        case .trainingPlan:
            beats = trainingBeats(profile: profile, context: context, facts: facts, input: input, rng: &rng)
        case .lowEnergy:
            beats = lowEnergyBeats(profile: profile, context: context, facts: facts, rng: &rng)
        case .sleep:
            beats = sleepBeats(profile: profile, context: context, facts: facts, rng: &rng)
        case .pain:
            beats = painBeats(profile: profile, input: input, rng: &rng)
        case .progress:
            beats = progressBeats(profile: profile, context: context, facts: facts, rng: &rng)
        case .gratitude:
            beats = gratitudeBeats(profile: profile, rng: &rng)
        case .motivation:
            beats = motivationBeats(profile: profile, context: context, rng: &rng)
        case .fallback:
            beats = fallbackBeats(profile: profile, rng: &rng)
        case .briefing:
            beats = briefingBeats(profile: profile, context: context, facts: facts, rng: &rng)
        case .checkIn:
            beats = checkInBeats(profile: profile, context: context, rng: &rng)
        case .themeLock:
            beats = themeLockBeats(profile: profile, facts: facts, rng: &rng)
        }

        var filtered = beats.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        filtered = applyLength(filtered, profile: profile, rng: &rng)

        if profile.guidanceOnly, intent == .trainingPlan || intent == .lowEnergy || intent == .pain {
            filtered.append(guidanceLine(rng: &rng))
        }

        return joinBeats(filtered, profile: profile)
    }

    // MARK: Beat builders

    private static func greetingBeats(
        profile: AriaVoiceProfile,
        context: TrainerContext,
        rng: inout AriaSeededRNG
    ) -> [String] {
        let who = address(profile, rng: &rng)
        let time = timeFlavor(profile, rng: &rng)
        let metric = lightMetricHook(profile, context: context, rng: &rng)
        let invite = rng.pick(inviteBank(profile))

        var beats = [time.isEmpty ? "\(who)." : "\(time), \(who).", invite]
        if let metric, profile.length != .tight {
            beats.insert(metric, at: 1)
        }
        if profile.humor != .none, rng.chance(0.3) {
            beats.append(rng.pick(humorTag(profile)))
        }
        return beats
    }

    private static func trainingBeats(
        profile: AriaVoiceProfile,
        context: TrainerContext,
        facts: AriaSpeechFacts,
        input: String,
        rng: inout AriaSeededRNG
    ) -> [String] {
        var beats: [String] = []

        if facts.themeJustLocked {
            beats.append(rng.pick([
                "You asked for \(facts.themeLabel) — locked.",
                "\(facts.themeLabel) lens is on.",
                themeVerb(profile, rng: &rng) + " mode engaged.",
            ]))
        } else if profile.theme != .classic, profile.metaphor != .none {
            beats.append(rng.pick([
                "Running your \(profile.theme.label) frame.",
                "\(themeVerb(profile, rng: &rng)) day.",
                lexicon(profile, key: "lensOn", rng: &rng),
            ]))
        }

        beats.append(statusLine(profile, context: context, facts: facts, rng: &rng))

        if let flavor = facts.sessionFlavor, !flavor.isEmpty {
            beats.append(revoiceFlavor(flavor, profile: profile, rng: &rng))
        }

        if let title = facts.sessionTitle {
            let dur = facts.sessionDuration.map { "\($0) min" } ?? ""
            let inten = facts.sessionIntensity ?? ""
            beats.append(rng.pick([
                "Session: **\(title)**" + (dur.isEmpty ? "" : " · \(dur)") + (inten.isEmpty ? "" : " · \(inten)."),
                "Here's the work: **\(title)**" + (dur.isEmpty ? "" : " (\(dur))") + ".",
                lexicon(profile, key: "sessionName", rng: &rng, vars: ["title": title, "dur": dur]),
            ]))
        }

        if profile.length == .expansive || profile.coaching == .dataDriven {
            beats.append(whyLine(profile, context: context, rng: &rng))
        }

        if let goal = context.userProfile.fitnessGoals.first, profile.length != .tight {
            beats.append(rng.pick([
                "Still pointed at \(goal.label.lowercased()).",
                "This still serves \(goal.label.lowercased()).",
                "Goal thread: \(goal.label.lowercased()).",
            ]))
        }

        if profile.energy == .hype, rng.chance(0.5) {
            beats.append(rng.pick(["Let's move.", "Clock starts when you do.", "No warm-up excuses — we earn the first set."]))
        } else if profile.energy == .soft {
            beats.append(rng.pick(["Take it one block at a time.", "Easy pace into the first set.", "We're building, not breaking."]))
        }

        return beats
    }

    private static func lowEnergyBeats(
        profile: AriaVoiceProfile,
        context: TrainerContext,
        facts: AriaSpeechFacts,
        rng: inout AriaSeededRNG
    ) -> [String] {
        let empathy = rng.pick(empathyBank(profile))
        let reframe = rng.pick([
            "Skipping entirely wastes the day. Going hard anyway is how people break. We meet in the middle.",
            "We're not chasing glory — we're protecting tomorrow's capacity.",
            lexicon(profile, key: "lowEnergyReframe", rng: &rng),
            "Thirty honest minutes beats a heroic crash.",
        ])
        var beats = [empathy, reframe]
        if let title = facts.sessionTitle {
            beats.append("Plan: **\(title)** — light, useful, done.")
        } else {
            beats.append(rng.pick([
                "Recovery flow: mobility, blood flow, no ego.",
                "Think maintenance, not training.",
            ]))
        }
        return beats
    }

    private static func sleepBeats(
        profile: AriaVoiceProfile,
        context: TrainerContext,
        facts: AriaSpeechFacts,
        rng: inout AriaSeededRNG
    ) -> [String] {
        let hrs = facts.sleepHours.map { String(format: "%.1f" , $0) } ?? "—"
        let deep = facts.deepMinutes.map { "\($0)" } ?? "—"
        let avg = facts.sleepAvg.map { "\($0)" } ?? "—"

        var beats: [String] = []
        switch facts.sleepBand {
        case .strong:
            beats = rng.pick([
                [
                    "Last night: \(hrs)h, \(deep) min deep. That's real recovery currency.",
                    "Deep sleep is where you rebuild — keep guarding the wind-down.",
                ],
                [
                    "Sleep quality is working for you — \(hrs) hours, \(deep) deep.",
                    profile.register == .clinical
                        ? "Deep-sleep minutes in a high band. Protect latency to bed."
                        : "That's the kind of night that makes tomorrow's work feel lighter.",
                ],
            ])
        case .weak:
            beats = [
                rng.pick([
                    "\(hrs)h total but only \(deep) min deep — that's a thin rebuild.",
                    "Deep sleep undershot. \(deep) minutes isn't enough to pay back training stress.",
                ]),
                rng.pick([
                    "Stress, late caffeine, bright screens — pick a lever tonight.",
                    "Earlier lights-out by 30 minutes is the highest-ROI fix if life allows.",
                ]),
            ]
        case .ok, .unknown:
            beats = [
                "Slept \(hrs)h with \(deep) min deep — fine, not elite.",
                rng.pick([
                    "Consistency will move this more than one perfect night.",
                    "Weekly average is \(avg)/100 — that's the real scoreboard.",
                ]),
            ]
        }
        return beats
    }

    private static func painBeats(profile: AriaVoiceProfile, input: String, rng: inout AriaSeededRNG) -> [String] {
        let lower = input.lowercased()
        if lower.contains("sore") || lower.contains("doms") {
            return [
                rng.pick([
                    "Soreness or actual pain? Different playbooks.",
                    "DOMS from yesterday is noise. Sharp, local pain is signal.",
                ]),
                "Where is it, and does it change with a specific angle or load?",
            ]
        }
        return [
            rng.pick([
                "Stop the loaded work for a second — I need coordinates.",
                "Pain first. Ego second. Talk to me.",
            ]),
            "Sharp or dull? Only under load, or also at rest? We work around anything sharp.",
        ]
    }

    private static func progressBeats(
        profile: AriaVoiceProfile,
        context: TrainerContext,
        facts: AriaSpeechFacts,
        rng: inout AriaSeededRNG
    ) -> [String] {
        let sessions = facts.recentSessions ?? context.workoutHistory.count
        let streak = facts.streak
        var beats = [
            rng.pick([
                "You're stacking more consistency than you give yourself credit for.",
                "Progress isn't loud — it's the sessions that didn't get skipped.",
                profile.register == .clinical
                    ? "Adherence is the leading indicator. Output follows."
                    : "Showing up is the whole game. The numbers are catching up.",
            ])
        ]
        if sessions > 0 {
            beats.append("Recent log: \(sessions) sessions on record" + (streak.map { ", streak \($0)" } ?? "") + ".")
        }
        if profile.energy == .hype {
            beats.append(rng.pick(["Keep the chain unbroken.", "Don't negotiate with the standard."]))
        } else if profile.energy == .soft {
            beats.append("Steady beats spectacular. You're doing the quiet work.")
        }
        return beats
    }

    private static func gratitudeBeats(profile: AriaVoiceProfile, rng: inout AriaSeededRNG) -> [String] {
        [rng.pick([
            "You're doing the work — I just keep the map honest.",
            "Save the thanks for after the hard set.",
            "Appreciate it. Now go earn the next log.",
            "All you. I'm the mirror and the metronome.",
            profile.humor == .playful ? "Flattery noted. Bars still move the same." : "Respect. Back to the plan.",
        ])]
    }

    private static func motivationBeats(
        profile: AriaVoiceProfile,
        context: TrainerContext,
        rng: inout AriaSeededRNG
    ) -> [String] {
        let core = rng.pick(motivationBank(profile))
        var beats = [core]
        if profile.length != .tight {
            beats.append(rng.pick([
                "Discipline is showing up without the mood matching.",
                "The session you don't want is often the one that compounds.",
                lexicon(profile, key: "motivationExtra", rng: &rng),
            ]))
        }
        if context.readiness.overall >= 75 {
            beats.append(rng.pick(["Body's ready. Don't waste a green light.", "You have the capacity today — use it cleanly."]))
        }
        return beats
    }

    private static func fallbackBeats(profile: AriaVoiceProfile, rng: inout AriaSeededRNG) -> [String] {
        [rng.pick([
            "I want a real answer — give me a cleaner ask. Training, recovery, sleep, or something else?",
            "Lost the thread for a second. Rephrase? Workout, readiness, or life logistics?",
            "Say it straight: what do you need from me right now?",
            profile.humor != .none
                ? "That one bounced off my antenna. Try again in plain language?"
                : "Need a bit more context to coach you well.",
        ])]
    }

    private static func briefingBeats(
        profile: AriaVoiceProfile,
        context: TrainerContext,
        facts: AriaSpeechFacts,
        rng: inout AriaSeededRNG
    ) -> [String] {
        // Home briefing is already partly built; this path is for recomposition if used.
        var beats: [String] = []
        let who = profile.firstName.isEmpty ? "" : profile.firstName
        let time = timeFlavor(profile, rng: &rng)
        beats.append(who.isEmpty ? "\(time)." : "\(time), \(who).")
        beats.append(statusLine(profile, context: context, facts: facts, rng: &rng))
        if let title = facts.sessionTitle {
            beats.append(profile.readiness >= 70
                ? "Primary: \(title)."
                : "If you move, keep it light around \(title).")
        }
        return beats
    }

    private static func checkInBeats(
        profile: AriaVoiceProfile,
        context: TrainerContext,
        rng: inout AriaSeededRNG
    ) -> [String] {
        [
            rng.pick(inviteBank(profile)),
            lightMetricHook(profile, context: context, rng: &rng) ?? statusLine(profile, context: context, facts: .init(), rng: &rng),
        ]
    }

    private static func themeLockBeats(
        profile: AriaVoiceProfile,
        facts: AriaSpeechFacts,
        rng: inout AriaSeededRNG
    ) -> [String] {
        let label = facts.themeLabel.isEmpty ? profile.theme.label : facts.themeLabel
        return [
            rng.pick([
                "\(label) is your training language now.",
                "Locked \(label). Plans will speak that dialect until you change it.",
                "Got it — I'll coach through the \(label) lens.",
            ]),
            lexicon(profile, key: "themePromise", rng: &rng),
        ]
    }

    // MARK: Shared lines

    private static func address(_ profile: AriaVoiceProfile, rng: inout AriaSeededRNG) -> String {
        if profile.firstName.isEmpty {
            return rng.pick(["athlete", "champ", "friend", "you"])
        }
        switch profile.register {
        case .street:
            return rng.pick([profile.firstName, profile.firstName, "yo \(profile.firstName)"])
        case .mythic:
            return rng.pick([profile.firstName, "hunter \(profile.firstName)", profile.firstName])
        default:
            return profile.firstName
        }
    }

    private static func timeFlavor(_ profile: AriaVoiceProfile, rng: inout AriaSeededRNG) -> String {
        if profile.hour < 7 {
            return rng.pick(["Early", "Before the world wakes", "Dawn block"])
        } else if profile.hour < 12 {
            return rng.pick(["Morning", "AM", "Morning check-in"])
        } else if profile.hour < 17 {
            return rng.pick(["Afternoon", "Midday", "Afternoon"])
        } else if profile.hour < 22 {
            return rng.pick(["Evening", "PM", "Evening"])
        } else {
            return rng.pick(["Late", "Night block", "Late check-in"])
        }
    }

    private static func statusLine(
        _ profile: AriaVoiceProfile,
        context: TrainerContext,
        facts: AriaSpeechFacts,
        rng: inout AriaSeededRNG
    ) -> String {
        let r = profile.readiness
        let hrv = context.dailyMetrics.hrv
        let rhr = context.dailyMetrics.restingHR
        let rank = profile.theme.rankLabel(for: r)

        if profile.register == .clinical || profile.coaching == .dataDriven {
            return "Readiness \(r)/100 · HRV \(hrv) ms · RHR \(rhr) bpm — band: \(rank)."
        }
        if profile.metaphor != .none {
            return rng.pick([
                "\(address(profile, rng: &rng)) — \(r)/100. Status: \(rank).",
                "Signals: readiness \(r), HRV \(hrv). \(rank).",
                lexicon(profile, key: "status", rng: &rng, vars: [
                    "r": "\(r)", "hrv": "\(hrv)", "rank": rank,
                ]),
            ])
        }
        switch profile.energy {
        case .hype:
            return "You're at \(r)/100 — \(rank). HRV \(hrv), heart \(rhr)."
        case .soft, .warm:
            return "Readiness is sitting at \(r). HRV \(hrv), resting heart \(rhr). \(rank)."
        case .razor:
            return "\(r)/100. HRV \(hrv). RHR \(rhr). \(rank)."
        case .steady:
            return "\(address(profile, rng: &rng)) — readiness \(r)/100 · HRV \(hrv) · RHR \(rhr). \(rank)."
        }
    }

    private static func lightMetricHook(
        _ profile: AriaVoiceProfile,
        context: TrainerContext,
        rng: inout AriaSeededRNG
    ) -> String? {
        let r = profile.readiness
        if r < 55 {
            return rng.pick([
                "Numbers are soft today at \(r) — how do you actually feel?",
                "Recovery looks thin (\(r)). Checking in before we load anything.",
                "Body's asking for care more than glory right now.",
            ])
        }
        if r >= 85 {
            return rng.pick([
                "You're in a high window at \(r). Don't waste it on junk volume.",
                "Green lights everywhere — \(r) readiness.",
                lexicon(profile, key: "highReady", rng: &rng, vars: ["r": "\(r)"]),
            ])
        }
        if context.isLateNight {
            return rng.pick([
                "Late for a heavy ask — unless you need to talk.",
                "Night hours. Training or unloading the day?",
            ])
        }
        return nil
    }

    private static func whyLine(
        _ profile: AriaVoiceProfile,
        context: TrainerContext,
        rng: inout AriaSeededRNG
    ) -> String {
        if context.readiness.overall >= 80 {
            return rng.pick([
                "Why hard today: recovery debt is low enough to express force safely.",
                "Capacity is there — intensity is the scarce resource we spend now.",
            ])
        }
        if context.readiness.overall < 55 {
            return rng.pick([
                "Why easy today: nervous system load is elevated; stimulus without recovery is just damage.",
                "We're buying back capacity, not proving toughness.",
            ])
        }
        return rng.pick([
            "Why this dose: enough signal to adapt, not enough to dig a hole.",
            "Quality over heroics while readiness is middling.",
        ])
    }

    private static func revoiceFlavor(_ flavor: String, profile: AriaVoiceProfile, rng: inout AriaSeededRNG) -> String {
        // Keep the engine's structural flavor, optionally prefix with voice spice.
        if profile.metaphor == .none || profile.register == .clinical {
            // Strip some mythic words for clinical
            return flavor
                .replacingOccurrences(of: "System ", with: "")
                .replacingOccurrences(of: "S-Rank ", with: "top-end ")
        }
        if profile.energy == .hype, rng.chance(0.4) {
            return flavor + " " + rng.pick(["No half-reps.", "Make it clean.", "Earn the log."])
        }
        if profile.energy == .soft, rng.chance(0.4) {
            return flavor + " " + rng.pick(["Breathe between blocks.", "Unhurried quality.", "You're allowed to scale."])
        }
        return flavor
    }

    private static func guidanceLine(rng: inout AriaSeededRNG) -> String {
        rng.pick([
            "Reminder: guidance and structure only — lifestyle coach, not a clinician.",
            "Boundaries stay on: no diagnosis, no treatment claims. Structure and pacing only.",
            "If anything feels medically wrong, stop and talk to a professional — I'll stay in coaching lane.",
        ])
    }

    private static func joinBeats(_ beats: [String], profile: AriaVoiceProfile) -> String {
        switch profile.length {
        case .tight:
            return beats.joined(separator: " ")
        case .medium, .expansive:
            return beats.joined(separator: "\n\n")
        }
    }

    private static func applyLength(_ beats: [String], profile: AriaVoiceProfile, rng: inout AriaSeededRNG) -> [String] {
        switch profile.length {
        case .tight:
            return Array(beats.prefix(2))
        case .medium:
            if beats.count <= 4 { return beats }
            // Keep first, last, and one middle
            let mid = beats[1..<beats.count - 1]
            let pickMid = mid.isEmpty ? [] : [rng.pick(Array(mid))]
            return [beats[0]] + pickMid + [beats.last].compactMap { $0 }
        case .expansive:
            return beats
        }
    }

    // MARK: Banks

    private static func inviteBank(_ profile: AriaVoiceProfile) -> [String] {
        switch profile.register {
        case .street:
            return ["What's good?", "Talk to me.", "What do you need?", "Yo — what's the play?"]
        case .peer:
            return ["What do you need?", "How are we using this check-in?", "I'm here — what's on your mind?", "Where should we start?"]
        case .pro:
            return ["How can I help this block?", "What are we optimizing today?", "Ready when you are — training, recovery, or plan?"]
        case .clinical:
            return ["State the objective.", "What variable are we adjusting?", "Ready for inputs — session, sleep, or load?"]
        case .mythic:
            return [
                lexiconStatic(profile.theme, key: "invite"),
                "What quest are we clearing?",
                "Report in — training or recovery?",
            ]
        }
    }

    private static func empathyBank(_ profile: AriaVoiceProfile) -> [String] {
        switch profile.energy {
        case .soft, .warm:
            return [
                "Yeah — some days land heavier. You're not broken for feeling it.",
                "I hear you. We don't punish a tired nervous system.",
                "Low battery is data, not a character flaw.",
            ]
        case .hype:
            return [
                "Tired? Cool. We still move — smart, not stupid.",
                "Energy's low. We adapt and still get the win.",
            ]
        case .razor:
            return [
                "Low energy noted. Adjusting dose.",
                "Capacity is limited. Plan changes. Ego doesn't get a vote.",
            ]
        case .steady:
            return [
                "Got it. Days like this separate smart athletes from broken ones.",
                "Understood — we'll trade intensity for continuity.",
            ]
        }
    }

    private static func motivationBank(_ profile: AriaVoiceProfile) -> [String] {
        switch profile.coaching {
        case .pushHard:
            return [
                "Motivation is weather. Standards are climate. Show up.",
                "Stop waiting to feel ready. Ready is a side effect of reps.",
            ]
        case .patient:
            return [
                "You don't have to feel fire — you just have to take the next honest step.",
                "Small kept promises beat rare heroic days.",
            ]
        case .dataDriven:
            return [
                "Motivation is noisy. Adherence is the metric that predicts outcomes.",
                "Run the protocol. Mood is not an input to today's decision tree.",
            ]
        case .ultraElite:
            return [
                "Professionals train on schedule, not on vibe.",
                "Performance is a system — execute the next block.",
            ]
        case .balanced:
            return [
                "You don't need a speech. You need one clean session.",
                "The best workout is often the one you almost skipped — scaled sanely.",
            ]
        }
    }

    private static func humorTag(_ profile: AriaVoiceProfile) -> [String] {
        switch profile.humor {
        case .dry:
            return ["I'll keep the pep-talk short.", "No monologue — unless you ask for one.", "Coffee optional. Honesty isn't."]
        case .playful:
            return ["I left the megaphone at home today.", "Plot twist: the plan still works if we keep it simple.", "ARIA, reporting for duty — slightly dramatic on request."]
        case .none:
            return [""]
        }
    }

    private static func themeVerb(_ profile: AriaVoiceProfile, rng: inout AriaSeededRNG) -> String {
        switch profile.theme {
        case .soloLeveling: return rng.pick(["Hunter", "System", "Rank-up", "Gate"])
        case .demonSlayer: return rng.pick(["Breath", "Corps", "Form", "Concentration"])
        case .onePiece: return rng.pick(["Crew", "Grand Line", "Voyage", "Haki"])
        case .martialArts: return rng.pick(["Camp", "Round", "Dojo", "Spar"])
        case .military: return rng.pick(["Ops", "PT", "Mission", "Standard"])
        case .superhero: return rng.pick(["Hero", "Patrol", "Cave", "Call-up"])
        case .athlete: return rng.pick(["Block", "Phase", "Camp", "Peak"])
        case .classic: return rng.pick(["Training", "Session", "Block"])
        }
    }

    /// Theme-aware micro lexicon with variable substitution.
    private static func lexicon(
        _ profile: AriaVoiceProfile,
        key: String,
        rng: inout AriaSeededRNG,
        vars: [String: String] = [:]
    ) -> String {
        var line = lexiconStatic(profile.theme, key: key)
        if line.isEmpty {
            line = fallbackLexicon(key: key, profile: profile)
        }
        // If multiple options separated by ||
        if line.contains("||") {
            line = rng.pick(line.components(separatedBy: "||"))
        }
        for (k, v) in vars {
            line = line.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return line
    }

    private static func lexiconStatic(_ theme: AriaTrainingTheme, key: String) -> String {
        switch (theme, key) {
        case (.soloLeveling, "invite"):
            return "Daily quest ready when you are.||What gate are we opening?||Report, hunter."
        case (.soloLeveling, "lensOn"):
            return "System overlay active.||Hunter protocol online.||Rank window checked."
        case (.soloLeveling, "status"):
            return "Player status {r}/100 · HRV {hrv}. {rank}."
        case (.soloLeveling, "sessionName"):
            return "Quest loaded: **{title}** · {dur}||Daily quest card: **{title}** ({dur})"
        case (.soloLeveling, "lowEnergyReframe"):
            return "Safe zone rules: complete something small, live to rank up.||The System scales quests for a reason — don't force a wipe."
        case (.soloLeveling, "motivationExtra"):
            return "E-ranks stay E-ranks when easy volume gets skipped.||XP is logged sessions, not hype."
        case (.soloLeveling, "highReady"):
            return "S-window energy at {r}. Don't AFK this."
        case (.soloLeveling, "themePromise"):
            return "Daily quests, rank windows from readiness, no fake gates when you're cooked."

        case (.demonSlayer, "invite"):
            return "Breath first — what do you need?||Forms or recovery?"
        case (.demonSlayer, "lensOn"):
            return "Total concentration framing on.||Corps training cadence."
        case (.demonSlayer, "status"):
            return "Breath & body: {r}/100. {rank}."
        case (.demonSlayer, "lowEnergyReframe"):
            return "Even Hashira rest. Soft forms today."
        case (.demonSlayer, "themePromise"):
            return "Breath control, clean form, relentless but sane intensity."

        case (.onePiece, "invite"):
            return "Crew check — what's the move?||Sail or dock?"
        case (.onePiece, "lensOn"):
            return "Voyage strength mode.||Adventure block locked."
        case (.onePiece, "status"):
            return "Crew status {r}. {rank}."
        case (.onePiece, "themePromise"):
            return "Power, grit, and sea-legs conditioning — scaled to the day."

        case (.military, "invite"):
            return "Report.||PT or admin?"
        case (.military, "lensOn"):
            return "Standards online.||Ops framing set."
        case (.military, "status"):
            return "Readiness {r}. {rank}."
        case (.military, "themePromise"):
            return "Discipline blocks, calisthenics, ruck-ready legs when capacity allows."

        case (.martialArts, "invite"):
            return "Round start — what do you need?||Technique or engine?"
        case (.martialArts, "themePromise"):
            return "Rounds, rotation, hips that can change levels."

        case (.superhero, "invite"):
            return "Call-up. What does the city need — wait, what do *you* need?"
        case (.superhero, "themePromise"):
            return "Strength, agility, presence — hero work without reckless damage."

        case (.athlete, "invite"):
            return "What's the performance question?||Session or recovery?"
        case (.athlete, "themePromise"):
            return "Power, speed, and regeneration — program like a season."

        default:
            return ""
        }
    }

    private static func fallbackLexicon(key: String, profile: AriaVoiceProfile) -> String {
        switch key {
        case "invite": return "What do you need?"
        case "lensOn": return "Theme locked in."
        case "status": return "Readiness {r}. {rank}."
        case "sessionName": return "**{title}** · {dur}"
        case "lowEnergyReframe": return "We scale the work so you still show up."
        case "motivationExtra": return "Consistency is the edge."
        case "highReady": return "High readiness at {r}."
        case "themePromise": return "I'll coach in that style while respecting readiness."
        default: return ""
        }
    }
}

// MARK: - Facts payload

/// Structured facts the voice layer can mention without hardcoding prose in engines.
struct AriaSpeechFacts {
    var sessionTitle: String? = nil
    var sessionDuration: Int? = nil
    var sessionIntensity: String? = nil
    var sessionFlavor: String? = nil
    var themeJustLocked: Bool = false
    var themeLabel: String = ""
    var sleepHours: Double? = nil
    var deepMinutes: Int? = nil
    var sleepAvg: Int? = nil
    var sleepBand: SleepSpeechBand = .unknown
    var recentSessions: Int? = nil
    var streak: Int? = nil

    enum SleepSpeechBand {
        case strong, ok, weak, unknown
    }
}
