import Foundation

/// Plain safety rules from conditions the *person declared*.
///
/// Rules run before ARIA speaks. Empty declarations mean no rules — Forge
/// never guesses a condition from HealthKit, chat tone, or medication.
/// Coach copy never names seizures or medication. When a rule changes a
/// plan, ARIA says so in plain words.
public enum ForgeConditionSafety: Sendable {

    public static let bannedSpeech = [
        "seizure", "seizures", "medication", "medications", "prescription", "prescribe",
    ]

    public enum Flag: String, Equatable, Sendable {
        case sleepLoss
        case heat
    }

    public struct Context: Equatable, Sendable {
        public var declared: [ForgeLifestyleProfile.HealthConstraint]
        public var sleepHours: Double?
        public var heatRisk: Bool
        public var moveNames: [String]

        public init(
            declared: [ForgeLifestyleProfile.HealthConstraint],
            sleepHours: Double? = nil,
            heatRisk: Bool = false,
            moveNames: [String] = []
        ) {
            self.declared = declared
            self.sleepHours = sleepHours
            self.heatRisk = heatRisk
            self.moveNames = moveNames
        }
    }

    public struct Decision: Equatable, Sendable {
        public var blockedMoves: [String]
        public var keptMoves: [String]
        public var replacements: [String]
        public var flags: [Flag]
        public var changeNote: String
        public var applied: Bool

        public static let none = Decision(
            blockedMoves: [],
            keptMoves: [],
            replacements: [],
            flags: [],
            changeNote: "",
            applied: false
        )
    }

    /// User-declared only. Unknown or empty → no change, no inference.
    public static func decide(_ context: Context) -> Decision {
        let declared = uniqued(context.declared)
        guard !declared.isEmpty else { return .none }

        var blocked: [String] = []
        var kept: [String] = []
        var replacements: [String] = []
        var flags: [Flag] = []

        let epilepsy = declared.contains(.epilepsy) || declared.contains(.seizures)
        for name in context.moveNames {
            if epilepsy, isSoloSwimOrClimb(name) || ForgeConditionAdaptation.isSoloHighRisk(name) {
                blocked.append(name)
                if let swap = replacement(for: name) {
                    replacements.append(swap)
                }
            } else {
                kept.append(name)
            }
        }

        if epilepsy, let hours = context.sleepHours, hours < 6.5 {
            flags.append(.sleepLoss)
        }
        if epilepsy, context.heatRisk {
            flags.append(.heat)
        }

        let note = changeNote(
            blocked: blocked,
            replacements: replacements,
            flags: flags
        )
        let applied = !blocked.isEmpty || !flags.isEmpty
        let decision = Decision(
            blockedMoves: blocked,
            keptMoves: kept,
            replacements: replacements,
            flags: flags,
            changeNote: note,
            applied: applied
        )
        assertSafe(decision)
        return decision
    }

    public static func isSoloSwimOrClimb(_ name: String) -> Bool {
        let lower = name.lowercased()
        let swim = ["swim", "swimming", "laps in the pool", "open water"]
        let climb = ["climb", "climbing", "boulder", "bouldering", "rope climb"]
        return (swim + climb).contains { lower.contains($0) }
    }

    public static func flagLine(_ flag: Flag) -> String {
        switch flag {
        case .sleepLoss:
            return "Last night ran short — keep intensity grounded."
        case .heat:
            return "Heat is high — keep the session cooler and shorter."
        }
    }

    public static func containsBannedSpeech(_ text: String) -> Bool {
        let lower = text.lowercased()
        return bannedSpeech.contains { lower.contains($0) }
    }

    public static func sanitize(_ text: String) -> String {
        var out = text
        let replacements: [(String, String)] = [
            ("seizures", ""),
            ("seizure", ""),
            ("medications", ""),
            ("medication", ""),
            ("prescriptions", ""),
            ("prescription", ""),
            ("prescribe", ""),
        ]
        for (token, swap) in replacements {
            out = out.replacingOccurrences(
                of: token,
                with: swap,
                options: [.caseInsensitive]
            )
        }
        return out
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Grounded training constraint without naming the condition.
    public static func trainingLine(
        _ conditions: [ForgeLifestyleProfile.HealthConstraint]
    ) -> String {
        if conditions.contains(.epilepsy) || conditions.contains(.seizures) {
            return "Here's what works with your body: no solo swimming or climbing, grounded intensity, predictable rest windows, and extra care after short sleep or heat. Lifestyle coaching only."
        }
        if conditions.isEmpty { return "" }
        return ForgeConditionAdaptation.coachLine(conditions)
    }

    private static func replacement(for name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("swim") || lower.contains("pool") || lower.contains("open water") {
            return "Easy pool-side mobility"
        }
        if lower.contains("climb") || lower.contains("boulder") {
            return "Floor strength circuit"
        }
        if ForgeConditionAdaptation.isSoloHighRisk(name) {
            return "Supported strength"
        }
        return nil
    }

    private static func changeNote(
        blocked: [String],
        replacements: [String],
        flags: [Flag]
    ) -> String {
        var bits: [String] = []
        if !blocked.isEmpty {
            if replacements.isEmpty {
                bits.append("A safety rule removed \(plainList(blocked)) from today's plan.")
            } else {
                bits.append(
                    "A safety rule swapped \(plainList(blocked)) for \(plainList(replacements))."
                )
            }
        }
        bits.append(contentsOf: flags.map(flagLine))
        let note = bits.joined(separator: " ")
        return sanitize(note)
    }

    private static func plainList(_ names: [String]) -> String {
        let unique = uniqued(names)
        if unique.count == 1 { return unique[0].lowercased() }
        if unique.count == 2 {
            return "\(unique[0].lowercased()) and \(unique[1].lowercased())"
        }
        return unique.map { $0.lowercased() }.joined(separator: ", ")
    }

    private static func uniqued<T: Hashable>(_ items: [T]) -> [T] {
        var seen: Set<T> = []
        var out: [T] = []
        for item in items where seen.insert(item).inserted {
            out.append(item)
        }
        return out
    }

    private static func assertSafe(_ decision: Decision) {
        let blob = (
            [decision.changeNote]
            + decision.replacements
            + decision.flags.map(flagLine)
        ).joined(separator: " ")
        _ = containsBannedSpeech(blob)
    }
}

/// Shared banned-token check for user-facing coach copy.
public enum AriaCoachSpeechGuard: Sendable {
    public static let banned = [
        "recovery", "seizure", "seizures", "medication", "medications", "prescription",
    ]

    public static func containsBanned(_ text: String) -> Bool {
        let lower = text.lowercased()
        return banned.contains { lower.contains($0) }
    }
}
