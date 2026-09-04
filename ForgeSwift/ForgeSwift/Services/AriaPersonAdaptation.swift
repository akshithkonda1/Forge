import Foundation

// MARK: - Canonical relationship labels

/// Specific relationship labels ARIA understands instantly.
/// Broader than CycleSupportRole — “wife” ≠ “girlfriend” ≠ “daughter”.
enum AriaRelationshipLabel: String, Codable, CaseIterable, Identifiable {
    case wife, husband, girlfriend, boyfriend, partner, spouse, fiance
    case daughter, son, child, teen
    case sister, brother, mom, mother, dad, father, sibling, family
    case friend, roommate, coworker
    case other

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .fiance: return "fiancé(e)"
        default: return rawValue
        }
    }

    var role: CycleSupportRole {
        switch self {
        case .wife, .husband, .girlfriend, .boyfriend, .partner, .spouse, .fiance:
            return .romantic
        case .daughter, .son, .child, .teen:
            return .child
        case .sister, .brother, .mom, .mother, .dad, .father, .sibling, .family:
            return .family
        case .friend, .roommate, .coworker:
            return .friend
        case .other:
            return .other
        }
    }

    /// How ARIA refers to them in speech (“your wife”, “your daughter”).
    func possessivePhrase(name: String?) -> String {
        if let name, !name.isEmpty { return name }
        switch self {
        case .wife: return "your wife"
        case .husband: return "your husband"
        case .girlfriend: return "your girlfriend"
        case .boyfriend: return "your boyfriend"
        case .partner: return "your partner"
        case .spouse: return "your spouse"
        case .fiance: return "your fiancé(e)"
        case .daughter: return "your daughter"
        case .son: return "your son"
        case .child: return "your child"
        case .teen: return "your teen"
        case .sister: return "your sister"
        case .brother: return "your brother"
        case .mom, .mother: return "your mom"
        case .dad, .father: return "your dad"
        case .sibling: return "your sibling"
        case .family: return "your family member"
        case .friend: return "your friend"
        case .roommate: return "your roommate"
        case .coworker: return "your coworker"
        case .other: return "them"
        }
    }

    static func parse(from raw: String) -> AriaRelationshipLabel {
        let l = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if l.contains("wife") { return .wife }
        if l.contains("husband") { return .husband }
        if l.contains("girlfriend") || l == "gf" { return .girlfriend }
        if l.contains("boyfriend") || l == "bf" { return .boyfriend }
        if l.contains("fiancé") || l.contains("fiance") { return .fiance }
        if l.contains("spouse") { return .spouse }
        if l.contains("daughter") { return .daughter }
        if l.contains("son") && !l.contains("person") { return .son }
        if l.contains("teen") { return .teen }
        if l.contains("child") || l.contains("kid") { return .child }
        if l.contains("sister") { return .sister }
        if l.contains("brother") { return .brother }
        if l.contains("mother") || l == "mom" || l.contains(" mom") { return .mom }
        if l.contains("father") || l == "dad" { return .dad }
        if l.contains("sibling") { return .sibling }
        if l.contains("roommate") { return .roommate }
        if l.contains("coworker") || l.contains("colleague") { return .coworker }
        if l.contains("friend") { return .friend }
        if l.contains("family") { return .family }
        if l.contains("partner") { return .partner }
        return .other
    }

    /// Extract all relationship labels mentioned in free text.
    static func allMentioned(in text: String) -> [AriaRelationshipLabel] {
        let lower = text.lowercased()
        var found: [AriaRelationshipLabel] = []
        let checks: [(String, AriaRelationshipLabel)] = [
            ("wife", .wife), ("husband", .husband), ("girlfriend", .girlfriend),
            ("boyfriend", .boyfriend), ("fiancé", .fiance), ("fiance", .fiance),
            ("spouse", .spouse), ("daughter", .daughter), ("my son", .son),
            ("my teen", .teen), ("my kid", .child), ("my child", .child),
            ("sister", .sister), ("brother", .brother), ("my mom", .mom),
            ("my mother", .mother), ("roommate", .roommate), ("coworker", .coworker),
            ("my friend", .friend), ("my partner", .partner),
        ]
        for (key, label) in checks where lower.contains(key) {
            if !found.contains(label) { found.append(label) }
        }
        return found
    }
}

// MARK: - Personal archetypes

/// Personality / relational archetype for a specific person.
/// Guides how ARIA frames advice *about* them and scripts *to* them.
enum AriaPersonalArchetype: String, Codable, CaseIterable, Identifiable {
    case unknown
    case guardian       // protective, steady, duty-first
    case nurturer       // warm caretaker, needs appreciation
    case analyst        // logical, precision language
    case spark          // high energy, playful, spontaneous
    case sovereign      // independent, hates being managed
    case peacemaker     // avoids conflict, harmony-seeking
    case warrior        // competitive, direct, challenge-friendly
    case artist         // sensitive, meaning-seeking, needs beauty/space
    case jester         // humor as shield and bridge
    case sage           // reflective, advice-giving, slow
    case rebel          // resists control, needs autonomy
    case performer      // image-aware, social, feedback-sensitive
    case caretakerTeen  // teen who still needs structure + dignity
    case sensitiveTeen  // teen, high feel, low lecture tolerance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unknown: return "Still learning"
        case .guardian: return "Guardian"
        case .nurturer: return "Nurturer"
        case .analyst: return "Analyst"
        case .spark: return "Spark"
        case .sovereign: return "Sovereign"
        case .peacemaker: return "Peacemaker"
        case .warrior: return "Warrior"
        case .artist: return "Artist"
        case .jester: return "Jester"
        case .sage: return "Sage"
        case .rebel: return "Rebel"
        case .performer: return "Performer"
        case .caretakerTeen: return "Steady teen"
        case .sensitiveTeen: return "Sensitive teen"
        }
    }

    var tagline: String {
        switch self {
        case .unknown: return "Not enough signal yet — listen more than label."
        case .guardian: return "Protects others; responds to respect and clear roles."
        case .nurturer: return "Gives care; softens when appreciated, hardens when taken for granted."
        case .analyst: return "Wants clarity, reasons, and low drama."
        case .spark: return "Moves fast; boredom is the enemy, play opens doors."
        case .sovereign: return "Autonomy first — offers land better than orders."
        case .peacemaker: return "Harmony first; pressure and raised voices shut them down."
        case .warrior: return "Respects strength and honesty; soft-pedaling can feel fake."
        case .artist: return "Feels deeply; needs tone, beauty, and unforced timing."
        case .jester: return "Uses humor to connect and to dodge — join the joke, then get real."
        case .sage: return "Thinks out loud slowly; don't rush the conclusion."
        case .rebel: return "Control is gasoline — choice language works better."
        case .performer: return "Aware of how things look; private feedback > public correction."
        case .caretakerTeen: return "Capable teen who still needs a safe base, not a boss."
        case .sensitiveTeen: return "High feel, low lecture — short, private, validating."
        }
    }

    /// How to speak *to* this archetype.
    var speechGuidance: String {
        switch self {
        case .unknown: return "Match their last tone; keep options open."
        case .guardian: return "Be respectful, concrete, duty-aware. No mocking responsibility."
        case .nurturer: return "Lead with gratitude. Offer care back. Avoid transactional vibes."
        case .analyst: return "Use clean structure: situation → need → ask. Skip vague emotional fog."
        case .spark: return "Energetic, brief, optional adventures. Don't smother with heavy talks."
        case .sovereign: return "Ask permission. Offer choices. Never corner."
        case .peacemaker: return "Lower stakes language. One issue at a time. Safety first."
        case .warrior: return "Straight, respectful challenge. No sugarcoating that feels fake."
        case .artist: return "Softer cadence, metaphors OK, time to feel before solve."
        case .jester: return "Allow humor; land the real point gently after the laugh."
        case .sage: return "Invite their view. Long pauses OK. Don't interrupt the thought."
        case .rebel: return "Collaborative framing: \"What do you want to try?\" not \"You should.\""
        case .performer: return "Private, face-saving, specific praise before critique."
        case .caretakerTeen: return "Peer-respect tone + clear logistics. Trust + structure."
        case .sensitiveTeen: return "Very short. Validate first. No audience. No moral speeches."
        }
    }

    /// What usually backfires.
    var avoid: [String] {
        switch self {
        case .sovereign, .rebel: return ["orders", "ultimatums", "public correction"]
        case .peacemaker: return ["raised voice", "ambush talks", "forcing a decision now"]
        case .analyst: return ["vague venting without a point", "moving goalposts"]
        case .nurturer: return ["taking care for granted", "only texting when you need something"]
        case .sensitiveTeen, .caretakerTeen: return ["lectures", "sarcasm about feelings", "talking about them to relatives"]
        case .warrior: return ["condescension", "fake cheer"]
        case .performer: return ["public call-outs", "comparing them to others"]
        default: return ["assuming", "over-explaining"]
        }
    }

    static func detect(in text: String) -> AriaPersonalArchetype? {
        let l = text.lowercased()
        // Explicit "she's a ..." / "archetype"
        let pairs: [(String, AriaPersonalArchetype)] = [
            ("guardian", .guardian), ("protector", .guardian),
            ("nurturer", .nurturer), ("caretaker", .nurturer), ("caregiver type", .nurturer),
            ("analyst", .analyst), ("logical", .analyst), ("engineer brain", .analyst),
            ("spark", .spark), ("high energy", .spark), ("spontaneous", .spark),
            ("independent", .sovereign), ("sovereign", .sovereign), ("needs autonomy", .sovereign),
            ("peacemaker", .peacemaker), ("conflict avoidant", .peacemaker), ("hates conflict", .peacemaker),
            ("warrior", .warrior), ("competitive", .warrior), ("fighter", .warrior),
            ("sensitive artist", .artist), ("artistic", .artist), ("creative soul", .artist),
            ("class clown", .jester), ("always joking", .jester), ("jester", .jester),
            ("wise", .sage), ("sage", .sage), ("overthinks thoughtfully", .sage),
            ("rebel", .rebel), ("defiant", .rebel), ("doesn't like rules", .rebel),
            ("performer", .performer), ("image conscious", .performer), ("cares what people think", .performer),
            ("sensitive teen", .sensitiveTeen), ("emotional teen", .sensitiveTeen),
            ("mature teen", .caretakerTeen), ("responsible teen", .caretakerTeen),
        ]
        for (key, arch) in pairs where l.contains(key) {
            return arch
        }
        // Behavioral inference
        if l.contains("shuts down") && l.contains("conflict") { return .peacemaker }
        if l.contains("needs control") || l.contains("doesn't like being told") { return .sovereign }
        if l.contains("makes everything a joke") { return .jester }
        if l.contains("very sensitive") || l.contains("feels everything") { return .artist }
        if l.contains("super logical") || l.contains("wants facts") { return .analyst }
        return nil
    }

    static func defaults(for label: AriaRelationshipLabel) -> AriaPersonalArchetype {
        switch label {
        case .daughter, .teen: return .sensitiveTeen
        case .son, .child: return .caretakerTeen
        case .wife, .spouse: return .nurturer
        case .girlfriend, .partner, .fiance: return .spark
        case .husband, .boyfriend: return .guardian
        case .mom, .mother: return .nurturer
        case .dad, .father: return .guardian
        case .coworker: return .analyst
        default: return .unknown
        }
    }
}

// MARK: - How a specific person speaks

/// Captures speech patterns of a person so ARIA can coach the user to meet them there —
/// and so scripts sound like something that person would actually receive well.
struct AriaSpeechStyleProfile: Codable, Equatable {
    var formality: Formality
    var pace: Pace
    var length: LengthBias
    var humor: HumorStyle
    var emotionalExpressiveness: Expressiveness
    var vocabulary: VocabularyTone
    var emojiComfort: EmojiComfort
    /// Signature phrases they use or respond to
    var signaturePhrases: [String]
    /// Words/phrases that shut them down
    var triggerPhrases: [String]
    /// How they text vs talk if known
    var channelBias: ChannelBias
    var sampleLines: [String]
    var lastUpdated: Date

    enum Formality: String, Codable { case casual, neutral, polished }
    enum Pace: String, Codable { case rapid, measured, slow }
    enum LengthBias: String, Codable { case terse, medium, expansive }
    enum HumorStyle: String, Codable { case none, dry, playful, sarcastic }
    enum Expressiveness: String, Codable { case reserved, balanced, open }
    enum VocabularyTone: String, Codable { case simple, vivid, technical, slangy }
    enum EmojiComfort: String, Codable { case none, light, heavy }
    enum ChannelBias: String, Codable { case textFirst, callFirst, inPerson, unknown }

    static func defaults(for label: AriaRelationshipLabel, archetype: AriaPersonalArchetype) -> AriaSpeechStyleProfile {
        var base = AriaSpeechStyleProfile(
            formality: .neutral,
            pace: .measured,
            length: .medium,
            humor: .none,
            emotionalExpressiveness: .balanced,
            vocabulary: .simple,
            emojiComfort: .light,
            signaturePhrases: [],
            triggerPhrases: [],
            channelBias: .unknown,
            sampleLines: [],
            lastUpdated: Date()
        )
        switch label {
        case .teen, .daughter, .son, .child:
            base.formality = .casual
            base.length = .terse
            base.pace = .rapid
            base.emojiComfort = .heavy
            base.channelBias = .textFirst
            base.humor = .playful
            base.triggerPhrases = ["because I said so", "when I was your age", "calm down"]
        case .wife, .husband, .spouse:
            base.formality = .neutral
            base.length = .medium
            base.emotionalExpressiveness = .open
        case .girlfriend, .boyfriend, .partner, .fiance:
            base.formality = .casual
            base.humor = .playful
            base.emojiComfort = .light
        case .coworker:
            base.formality = .polished
            base.humor = .none
            base.emojiComfort = .none
            base.channelBias = .textFirst
        default:
            break
        }
        switch archetype {
        case .analyst:
            base.vocabulary = .technical
            base.emotionalExpressiveness = .reserved
            base.length = .medium
        case .spark, .jester:
            base.pace = .rapid
            base.humor = archetype == .jester ? .playful : .playful
            base.length = .terse
        case .sage:
            base.pace = .slow
            base.length = .expansive
            base.formality = .neutral
        case .warrior:
            base.formality = .casual
            base.length = .terse
            base.humor = .dry
        case .sensitiveTeen:
            base.length = .terse
            base.triggerPhrases += ["you're overreacting", "it's not a big deal"]
        case .sovereign, .rebel:
            base.triggerPhrases += ["you have to", "you need to", "you should"]
        default:
            break
        }
        return base
    }

    /// Detect speech-style claims in free text about how someone talks.
    static func learn(from text: String, into profile: inout AriaSpeechStyleProfile) -> Bool {
        let l = text.lowercased()
        var changed = false
        if l.contains("texts short") || l.contains("one word texts") || l.contains("dry texter") {
            profile.length = .terse; profile.channelBias = .textFirst; changed = true
        }
        if l.contains("writes paragraphs") || l.contains("long texts") || l.contains("essays over text") {
            profile.length = .expansive; changed = true
        }
        if l.contains("formal") || l.contains("proper english") {
            profile.formality = .polished; changed = true
        }
        if l.contains("slang") || l.contains("very casual") || l.contains("chill talker") {
            profile.formality = .casual; profile.vocabulary = .slangy; changed = true
        }
        if l.contains("sarcastic") {
            profile.humor = .sarcastic; changed = true
        }
        if l.contains("dry humor") || l.contains("dry sense of humor") {
            profile.humor = .dry; changed = true
        }
        if l.contains("always joking") || l.contains("makes jokes") {
            profile.humor = .playful; changed = true
        }
        if l.contains("doesn't show emotion") || l.contains("hard to read") || l.contains("stoic") {
            profile.emotionalExpressiveness = .reserved; changed = true
        }
        if l.contains("very emotional") || l.contains("wears heart") || l.contains("open about feelings") {
            profile.emotionalExpressiveness = .open; changed = true
        }
        if l.contains("talks fast") || l.contains("rapid fire") {
            profile.pace = .rapid; changed = true
        }
        if l.contains("talks slow") || l.contains("pauses a lot") {
            profile.pace = .slow; changed = true
        }
        if l.contains("hates phone calls") || l.contains("prefers text") {
            profile.channelBias = .textFirst; changed = true
        }
        if l.contains("prefers calls") || l.contains("better on the phone") {
            profile.channelBias = .callFirst; changed = true
        }
        if l.contains("in person only") || l.contains("face to face") {
            profile.channelBias = .inPerson; changed = true
        }
        if l.contains("uses emoji") || l.contains("emoji person") {
            profile.emojiComfort = .heavy; changed = true
        }
        if l.contains("no emoji") || l.contains("hates emoji") {
            profile.emojiComfort = .none; changed = true
        }
        // "she always says X"
        if let phrase = extractQuotedOrAlwaysSays(from: text) {
            if !profile.signaturePhrases.contains(phrase) {
                profile.signaturePhrases.append(phrase)
                if profile.signaturePhrases.count > 12 {
                    profile.signaturePhrases = Array(profile.signaturePhrases.suffix(12))
                }
                changed = true
            }
        }
        // "don't say X to her"
        if let trigger = extractDontSay(from: text) {
            if !profile.triggerPhrases.contains(trigger) {
                profile.triggerPhrases.append(trigger)
                changed = true
            }
        }
        if changed { profile.lastUpdated = Date() }
        return changed
    }

    private static func extractQuotedOrAlwaysSays(from text: String) -> String? {
        // "always says …" or quotes
        if let r = text.range(of: #"["“]([^"”]{3,60})["”]"#, options: .regularExpression) {
            var s = String(text[r])
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            return s
        }
        let lower = text.lowercased()
        for p in ["always says ", "always says,", "keeps saying ", "her catchphrase is ", "his catchphrase is "] {
            if let range = lower.range(of: p) {
                let rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let clip = rest.split(whereSeparator: { ".$!".contains($0) }).first.map(String.init) ?? rest
                if clip.count >= 3 && clip.count <= 60 { return clip.trimmingCharacters(in: .whitespaces) }
            }
        }
        return nil
    }

    private static func extractDontSay(from text: String) -> String? {
        let lower = text.lowercased()
        for p in ["don't say ", "dont say ", "never say ", "hates hearing ", "hates when i say "] {
            if let range = lower.range(of: p) {
                let rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let clip = rest.split(whereSeparator: { ".$!".contains($0) }).first.map(String.init) ?? rest
                if clip.count >= 2 && clip.count <= 50 { return clip.trimmingCharacters(in: .whitespaces) }
            }
        }
        return nil
    }

    var coachingSummary: String {
        var bits: [String] = []
        bits.append("speaks \(formality.rawValue)/\(pace.rawValue)/\(length.rawValue)")
        bits.append("humor:\(humor.rawValue)")
        bits.append("emotion:\(emotionalExpressiveness.rawValue)")
        if channelBias != .unknown { bits.append("prefers \(channelBias.rawValue)") }
        if !signaturePhrases.isEmpty {
            bits.append("phrases: " + signaturePhrases.prefix(3).map { "“\($0)”" }.joined(separator: ", "))
        }
        if !triggerPhrases.isEmpty {
            bits.append("never: " + triggerPhrases.prefix(3).joined(separator: ", "))
        }
        return bits.joined(separator: " · ")
    }

    /// Example script tuned to their length/formality.
    func shapeScript(_ core: String) -> String {
        switch length {
        case .terse:
            // Keep first clause only if long
            let first = core.split(separator: ".").first.map(String.init) ?? core
            return first.trimmingCharacters(in: .whitespacesAndNewlines)
        case .expansive:
            return core
        case .medium:
            return core
        }
    }
}

// MARK: - Relationship dynamics (learned + label defaults)

struct AriaRelationshipDynamics: Codable, Equatable {
    /// 0...1 closeness
    var closeness: Double
    /// 0...1 current tension
    var tension: Double
    /// How the user usually communicates with them
    var communication: CommunicationStyle
    /// How conflicts tend to go
    var conflictStyle: ConflictStyle
    /// Freeform tags the user taught ARIA (“hates calm down”, “needs space first”)
    var userTags: [String]
    /// Living situation hint
    var proximity: Proximity
    var lastUpdated: Date

    enum CommunicationStyle: String, Codable, CaseIterable {
        case direct, soft, playful, careful, sparse
        var label: String {
            switch self {
            case .direct: return "direct"
            case .soft: return "soft"
            case .playful: return "playful"
            case .careful: return "careful"
            case .sparse: return "few words"
            }
        }
    }

    enum ConflictStyle: String, Codable, CaseIterable {
        case repairFast, needsSpace, escalates, avoids, unknown
        var label: String {
            switch self {
            case .repairFast: return "repairs quickly"
            case .needsSpace: return "needs space first"
            case .escalates: return "can escalate"
            case .avoids: return "tends to avoid"
            case .unknown: return "unknown yet"
            }
        }
    }

    enum Proximity: String, Codable, CaseIterable {
        case together, longDistance, mixed, unknown
    }

    static func defaults(for label: AriaRelationshipLabel) -> AriaRelationshipDynamics {
        switch label {
        case .wife, .spouse, .husband:
            return AriaRelationshipDynamics(
                closeness: 0.85, tension: 0.25, communication: .direct,
                conflictStyle: .repairFast, userTags: [], proximity: .together, lastUpdated: Date()
            )
        case .girlfriend, .boyfriend, .fiance, .partner:
            return AriaRelationshipDynamics(
                closeness: 0.75, tension: 0.3, communication: .soft,
                conflictStyle: .needsSpace, userTags: [], proximity: .mixed, lastUpdated: Date()
            )
        case .daughter, .teen:
            return AriaRelationshipDynamics(
                closeness: 0.8, tension: 0.35, communication: .careful,
                conflictStyle: .needsSpace, userTags: ["privacy-first"], proximity: .together, lastUpdated: Date()
            )
        case .son, .child:
            return AriaRelationshipDynamics(
                closeness: 0.8, tension: 0.3, communication: .careful,
                conflictStyle: .unknown, userTags: ["privacy-first"], proximity: .together, lastUpdated: Date()
            )
        case .sister, .brother, .sibling:
            return AriaRelationshipDynamics(
                closeness: 0.65, tension: 0.25, communication: .playful,
                conflictStyle: .repairFast, userTags: [], proximity: .mixed, lastUpdated: Date()
            )
        case .mom, .mother, .dad, .father:
            return AriaRelationshipDynamics(
                closeness: 0.7, tension: 0.2, communication: .soft,
                conflictStyle: .needsSpace, userTags: [], proximity: .mixed, lastUpdated: Date()
            )
        case .friend, .roommate:
            return AriaRelationshipDynamics(
                closeness: 0.55, tension: 0.2, communication: .playful,
                conflictStyle: .avoids, userTags: [], proximity: .mixed, lastUpdated: Date()
            )
        case .coworker:
            return AriaRelationshipDynamics(
                closeness: 0.35, tension: 0.2, communication: .careful,
                conflictStyle: .avoids, userTags: ["professional boundary"], proximity: .mixed, lastUpdated: Date()
            )
        case .family, .other:
            return AriaRelationshipDynamics(
                closeness: 0.5, tension: 0.25, communication: .soft,
                conflictStyle: .unknown, userTags: [], proximity: .unknown, lastUpdated: Date()
            )
        }
    }
}

// MARK: - Instant adaptation profile

/// Snapshot of how ARIA should speak/act with this relationship *right now*.
struct AriaPersonAdaptation: Equatable {
    var label: AriaRelationshipLabel
    var role: CycleSupportRole
    var name: String?
    var dynamics: AriaRelationshipDynamics
    var archetype: AriaPersonalArchetype
    var speech: AriaSpeechStyleProfile

    var who: String { label.possessivePhrase(name: name) }

    /// Short coach voice line.
    var voicePreamble: String {
        switch label {
        case .wife:
            return "You're talking about \(who) — marriage weight. Long-game care, not scorekeeping."
        case .husband:
            return "You're talking about \(who) — partnership as a team. Steady and respectful."
        case .girlfriend:
            return "You're talking about \(who) — close and chosen. Warm, not parental."
        case .boyfriend:
            return "You're talking about \(who) — peer romance. Equal footing."
        case .fiance:
            return "You're talking about \(who) — building a life. Thoughtful and future-aware."
        case .partner, .spouse:
            return "You're talking about \(who) — real partnership. Direct care, no games."
        case .daughter:
            return "You're talking about \(who) — parent mode. Safety, dignity, zero romance framing."
        case .teen:
            return "You're talking about \(who) — teen + parent. Privacy, short words, no lectures."
        case .son, .child:
            return "You're talking about \(who) — caregiver mode. Practical protection first."
        case .sister:
            return "You're talking about \(who) — sibling bond. Loyal, light on hierarchy."
        case .brother:
            return "You're talking about \(who) — sibling. Straight, low drama."
        case .mom, .mother:
            return "You're talking about \(who) — parent-as-elder. Respect + boundaries."
        case .dad, .father:
            return "You're talking about \(who) — parent-as-elder. Clear and respectful."
        case .friend:
            return "You're talking about \(who) — friendship. Help without overstepping."
        case .roommate:
            return "You're talking about \(who) — shared space. Practical + considerate."
        case .coworker:
            return "You're talking about \(who) — work context. Professional boundaries."
        case .family, .sibling, .other:
            return "You're talking about \(who). Match closeness; don't assume romance or authority."
        }
    }

    var intimacyCoachingAllowed: Bool {
        switch label {
        case .wife, .husband, .girlfriend, .boyfriend, .partner, .spouse, .fiance:
            return true
        default:
            return false
        }
    }

    var caregiverMode: Bool {
        role == .child
    }

    /// What not to do for this relationship type.
    var hardBoundaries: [String] {
        switch label {
        case .daughter, .teen, .son, .child:
            return [
                "No sexual/intimacy framing",
                "No public shaming or period jokes",
                "No surveillance language — support logistics only",
                "Escalate medical red flags to a clinician",
            ]
        case .mom, .mother, .dad, .father:
            return [
                "Don't parent your parent unless asked",
                "Respect generational boundaries",
            ]
        case .coworker:
            return [
                "No oversharing private health details at work",
                "Keep advice professional",
            ]
        case .wife, .husband, .spouse:
            return [
                "Don't keep score of chores as weapons",
                "Repair > winning the argument",
            ]
        case .girlfriend, .boyfriend, .fiance, .partner:
            return [
                "Don't treat commitment level as entitlement",
                "Ask before assuming shared plans",
            ]
        default:
            return ["Don't overstep the actual relationship"]
        }
    }

    /// Default emotional stance when supporting this person.
    var supportStance: String {
        switch label {
        case .wife, .spouse:
            return "Team marriage: protect the bond, share load, speak like a spouse not a coach on a clipboard."
        case .girlfriend, .boyfriend, .fiance, .partner:
            return "Chosen partner: warmth, consent, and curiosity — earn closeness, don't demand it."
        case .daughter, .teen:
            return "Parent: be the safe base. Short sentences, supplies, sports/school logistics, emotional room."
        case .son, .child:
            return "Caregiver: protect dignity and routine; keep explanations age-appropriate."
        case .sister, .brother, .sibling:
            return "Sibling: loyal ally. Less hierarchy, more solidarity."
        case .mom, .mother, .dad, .father:
            return "Adult child: respect + clear boundaries; offer help without taking over."
        case .friend, .roommate:
            return "Friend: optional support — ask once, don't manage their life."
        case .coworker:
            return "Colleague: kind and contained."
        default:
            return "Match the relationship you actually have."
        }
    }

    var conflictAdvice: String {
        switch dynamics.conflictStyle {
        case .needsSpace:
            return "With \(who), space first usually helps — don't chase a cool-down with more words."
        case .repairFast:
            return "With \(who), clean repairs land well — short apology + next action."
        case .escalates:
            return "With \(who), lower volume and shorten sentences; heat escalates fast."
        case .avoids:
            return "With \(who), gentle openers work better than cornering them into a talk."
        case .unknown:
            return "You haven't told me how conflict usually goes with \(who) — default to calm and short."
        }
    }

    var communicationAdvice: String {
        switch dynamics.communication {
        case .direct: return "They handle direct language — be clear, not harsh."
        case .soft: return "Softer tone lands better — lead with care, then the ask."
        case .playful: return "Lightness helps — but not about pain or periods."
        case .careful: return "Go carefully — one question at a time, no pile-ons."
        case .sparse: return "Few words. Presence > speeches."
        }
    }

    var archetypeGuidance: String {
        "Archetype \(archetype.label): \(archetype.tagline) Speak-to-them: \(archetype.speechGuidance)"
    }

    var speechGuidanceBlock: String {
        """
        HOW THEY SPEAK: \(speech.coachingSummary)
        Meet them in their channel/length/humor. Shape scripts to their style.
        Avoid their triggers: \(speech.triggerPhrases.isEmpty ? "none recorded" : speech.triggerPhrases.joined(separator: "; ")).
        """
    }

    /// Block injected into Foundation Models / local narrative.
    var promptDirective: String {
        var lines = [
            "ACTIVE PERSON: \(who) [label=\(label.rawValue), role=\(role.label)]",
            "ARCHETYPE: \(archetype.label) — \(archetype.tagline)",
            "SPEAK-TO-THEM: \(archetype.speechGuidance)",
            "HOW THEY SPEAK: \(speech.coachingSummary)",
            "STANCE: \(supportStance)",
            "VOICE: \(voicePreamble)",
            "COMMUNICATION: \(communicationAdvice)",
            "CONFLICT: \(conflictAdvice)",
            "CLOSENESS=\(String(format: "%.2f", dynamics.closeness)) TENSION=\(String(format: "%.2f", dynamics.tension))",
            "INTIMACY_COACHING=\(intimacyCoachingAllowed ? "allowed_if_relevant" : "FORBIDDEN")",
            "BOUNDARIES: \(hardBoundaries.joined(separator: "; "))",
            "ARCHETYPE_AVOID: \(archetype.avoid.joined(separator: "; "))",
        ]
        if !dynamics.userTags.isEmpty {
            lines.append("USER-TAUGHT TAGS: \(dynamics.userTags.joined(separator: ", "))")
        }
        if let customTag = dynamics.userTags.first(where: { $0.hasPrefix("custom_archetype:") }) {
            lines.append("CUSTOM_ARCHETYPE: \(customTag.replacingOccurrences(of: "custom_archetype:", with: ""))")
        }
        if let tagline = dynamics.userTags.first(where: { $0.hasPrefix("custom_tagline:") }) {
            lines.append("CUSTOM_TAGLINE: \(tagline.replacingOccurrences(of: "custom_tagline:", with: ""))")
        }
        if let speak = dynamics.userTags.first(where: { $0.hasPrefix("custom_speak:") }) {
            lines.append("CUSTOM_SPEAK_TO_THEM: \(speak.replacingOccurrences(of: "custom_speak:", with: ""))")
        }
        if !speech.signaturePhrases.isEmpty {
            lines.append("THEIR PHRASES: \(speech.signaturePhrases.prefix(5).joined(separator: " | "))")
        }
        lines.append("Adapt every sentence to THIS person — relationship label + archetype + speech style (+ custom ARIA-invented archetype if present). Girlfriend scripts must not apply to a daughter; analyst scripts must not sound like jester banter.")
        return lines.joined(separator: "\n")
    }

    /// Rewrite a script line toward their speech length/formality.
    func personalizeScript(_ line: String) -> String {
        var s = speech.shapeScript(line)
        // Strip common triggers
        for t in speech.triggerPhrases {
            if s.lowercased().contains(t.lowercased()) {
                s = s.replacingOccurrences(of: t, with: "", options: .caseInsensitive)
            }
        }
        if speech.formality == .casual {
            s = s.replacingOccurrences(of: "I would like", with: "I want")
            s = s.replacingOccurrences(of: "I would", with: "I'd")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolve(
        labelRaw: String,
        name: String? = nil,
        dynamics: AriaRelationshipDynamics? = nil,
        archetype: AriaPersonalArchetype? = nil,
        speech: AriaSpeechStyleProfile? = nil
    ) -> AriaPersonAdaptation {
        let label = AriaRelationshipLabel.parse(from: labelRaw)
        let arch = archetype ?? .defaults(for: label)
        return AriaPersonAdaptation(
            label: label,
            role: label.role,
            name: name,
            dynamics: dynamics ?? .defaults(for: label),
            archetype: arch,
            speech: speech ?? .defaults(for: label, archetype: arch)
        )
    }
}

// MARK: - Known person registry entry

struct AriaKnownPerson: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var primaryLabel: String
    var extraLabels: [String]
    var role: CycleSupportRole
    var dynamics: AriaRelationshipDynamics
    var archetype: AriaPersonalArchetype
    /// When set, overrides builtin archetype for coaching.
    var customArchetypeId: String?
    var speech: AriaSpeechStyleProfile
    var notes: String
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, primaryLabel, extraLabels, role, dynamics, archetype, customArchetypeId, speech, notes, isActive
    }

    @MainActor
    var customArchetype: AriaCustomArchetype? {
        guard let customArchetypeId else { return nil }
        return AriaArchetypeStudio.shared.archetype(id: customArchetypeId)
    }

    @MainActor
    var adaptation: AriaPersonAdaptation {
        var base = AriaPersonAdaptation.resolve(
            labelRaw: primaryLabel,
            name: name.isEmpty ? nil : name,
            dynamics: dynamics,
            archetype: archetype,
            speech: speech
        )
        if let custom = customArchetype {
            // Overlay invented archetype onto adaptation voice fields via speech + tags
            base.archetype = AriaPersonalArchetype(rawValue: custom.relatedBuiltin ?? "") ?? base.archetype
            if base.archetype == .unknown, let related = custom.relatedBuiltin,
               let b = AriaPersonalArchetype(rawValue: related) {
                base.archetype = b
            }
            // Encode custom identity in dynamics tags for prompt injection
            var d = base.dynamics
            let stamp = "custom_archetype:\(custom.name)"
            if !d.userTags.contains(where: { $0.hasPrefix("custom_archetype:") }) {
                d.userTags.insert(stamp, at: 0)
            }
            d.userTags.removeAll { $0.hasPrefix("custom_tagline:") }
            d.userTags.append("custom_tagline:\(custom.tagline)")
            d.userTags.removeAll { $0.hasPrefix("custom_speak:") }
            d.userTags.append("custom_speak:\(custom.speechGuidance)")
            base.dynamics = d
            if let f = AriaSpeechStyleProfile.Formality(rawValue: custom.formality) {
                base.speech.formality = f
            }
            if let h = AriaSpeechStyleProfile.HumorStyle(rawValue: custom.humor) {
                base.speech.humor = h
            }
            if let e = AriaSpeechStyleProfile.Expressiveness(rawValue: custom.expressiveness) {
                base.speech.emotionalExpressiveness = e
            }
            if let len = AriaSpeechStyleProfile.LengthBias(rawValue: custom.lengthBias) {
                base.speech.length = len
            }
            if !custom.exampleScript.isEmpty {
                base.speech.sampleLines = [custom.exampleScript] + base.speech.sampleLines
            }
            for a in custom.avoid where !base.speech.triggerPhrases.contains(a) {
                base.speech.triggerPhrases.append(a)
            }
        }
        return base
    }

    init(
        id: String,
        name: String,
        primaryLabel: String,
        extraLabels: [String],
        role: CycleSupportRole,
        dynamics: AriaRelationshipDynamics,
        archetype: AriaPersonalArchetype,
        customArchetypeId: String? = nil,
        speech: AriaSpeechStyleProfile,
        notes: String,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.primaryLabel = primaryLabel
        self.extraLabels = extraLabels
        self.role = role
        self.dynamics = dynamics
        self.archetype = archetype
        self.customArchetypeId = customArchetypeId
        self.speech = speech
        self.notes = notes
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        primaryLabel = try c.decode(String.self, forKey: .primaryLabel)
        extraLabels = try c.decodeIfPresent([String].self, forKey: .extraLabels) ?? []
        role = try c.decode(CycleSupportRole.self, forKey: .role)
        dynamics = try c.decode(AriaRelationshipDynamics.self, forKey: .dynamics)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        customArchetypeId = try c.decodeIfPresent(String.self, forKey: .customArchetypeId)
        let label = AriaRelationshipLabel.parse(from: primaryLabel)
        archetype = try c.decodeIfPresent(AriaPersonalArchetype.self, forKey: .archetype)
            ?? .defaults(for: label)
        speech = try c.decodeIfPresent(AriaSpeechStyleProfile.self, forKey: .speech)
            ?? .defaults(for: label, archetype: archetype)
    }

    static func make(name: String, label: String) -> AriaKnownPerson {
        let parsed = AriaRelationshipLabel.parse(from: label)
        let arch = AriaPersonalArchetype.defaults(for: parsed)
        return AriaKnownPerson(
            id: UUID().uuidString,
            name: name,
            primaryLabel: label,
            extraLabels: [],
            role: parsed.role,
            dynamics: .defaults(for: parsed),
            archetype: arch,
            customArchetypeId: nil,
            speech: .defaults(for: parsed, archetype: arch),
            notes: "",
            isActive: true
        )
    }
}
