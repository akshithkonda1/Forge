import Foundation

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
        - Adaptive: work inside their actual day. One small change. Compound interest — over time they see and appreciate the difference. They choose.
        Vary phrasing — do not reuse stock lines. Sound like one continuous coach who knows this human.
        """
    }
}

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

    /// `items` must be non-empty — every call site in this codebase passes a
    /// literal or the result of an exhaustive `switch`, both always non-empty,
    /// verified by hand across every bank in `AriaVoiceEngine`,
    /// `AriaEmotionalSupportCoach` and `AriaRelationalCoach`.
    ///
    /// That is an invariant enforced by review, not by the type system, and
    /// nothing stops a future bank from building its array dynamically and
    /// landing here empty. Without this precondition, `int(in: 0..<0)`
    /// degrades to `lowerBound` (0) and `items[0]` traps with a bare "index
    /// out of range" — accurate, but it tells you nothing about which bank was
    /// empty or why. The precondition fires at the exact same moment (so no
    /// currently-safe call site changes behavior) but names the actual defect.
    mutating func pick<T>(_ items: [T]) -> T {
        precondition(!items.isEmpty, "AriaSeededRNG.pick called with an empty array — every voice bank must return at least one line.")
        return items[int(in: 0..<items.count)]
    }

    mutating func chance(_ p: Double) -> Bool {
        Double(next() % 10_000) / 10_000.0 < p
    }
}

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
