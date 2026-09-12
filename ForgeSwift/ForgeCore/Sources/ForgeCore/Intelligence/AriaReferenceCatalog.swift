import Foundation

/// Curated, keyless public-health pages ARIA may fetch over the device's
/// (or Simulator host's) default network route.
///
/// Pure catalog — no `URLSession`. Fetch lives in `AriaWebResearch` so
/// `LocalTestingOrchestrator` stays grep-clean of network transport.
/// Question + salt pick which page and which excerpt window, so two
/// people asking related questions do not get the identical paragraph.
public enum AriaReferenceTopic: String, Sendable, CaseIterable {
    case training
    case nutrition
    case progress
    case sleep
    case readiness
    case lifestyle
    case activity
    case body
    case cycle
    case fever
}

public struct AriaReferenceSource: Sendable, Equatable {
    public var title: String
    public var url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }

    public var pageURL: URL? { URL(string: url) }
}

public struct AriaReferencePick: Sendable, Equatable {
    public var source: AriaReferenceSource
    /// Character offset into stripped page text so two questions citing the
    /// same CDC page still surface different sentences.
    public var excerptStart: Int
    public var voiceLead: String

    public init(source: AriaReferenceSource, excerptStart: Int, voiceLead: String) {
        self.source = source
        self.excerptStart = excerptStart
        self.voiceLead = voiceLead
    }
}

public enum AriaReferenceCatalog {

    public static let sources: [AriaReferenceTopic: [AriaReferenceSource]] = [
        .training: [
            AriaReferenceSource(title: "MedlinePlus: Exercise and Physical Fitness", url: "https://medlineplus.gov/exerciseandphysicalfitness.html"),
            AriaReferenceSource(title: "CDC: Adult Physical Activity Guidelines", url: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html"),
            AriaReferenceSource(title: "NIH: Benefits of Exercise", url: "https://www.nih.gov/health-information/benefits-exercise"),
        ],
        .nutrition: [
            AriaReferenceSource(title: "NIH: Protein Fact Sheet", url: "https://ods.od.nih.gov/factsheets/Protein-Consumer/"),
            AriaReferenceSource(title: "MedlinePlus: Healthy Eating", url: "https://medlineplus.gov/healthyeating.html"),
            AriaReferenceSource(title: "CDC: Nutrition", url: "https://www.cdc.gov/nutrition/index.html"),
        ],
        .progress: [
            AriaReferenceSource(title: "CDC: Physical Activity Guidelines", url: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html"),
            AriaReferenceSource(title: "NIH: Benefits of Exercise", url: "https://www.nih.gov/health-information/benefits-exercise"),
        ],
        .sleep: [
            AriaReferenceSource(title: "CDC: Sleep and Health", url: "https://www.cdc.gov/sleep/about/index.html"),
            AriaReferenceSource(title: "MedlinePlus: Healthy Sleep", url: "https://medlineplus.gov/healthysleep.html"),
            AriaReferenceSource(title: "NIH: Sleep Deprivation and Deficiency", url: "https://www.nhlbi.nih.gov/health/sleep-deprivation"),
        ],
        .readiness: [
            AriaReferenceSource(title: "MedlinePlus: Exercise and Physical Fitness", url: "https://medlineplus.gov/exerciseandphysicalfitness.html"),
            AriaReferenceSource(title: "CDC: Sleep and Health", url: "https://www.cdc.gov/sleep/about/index.html"),
        ],
        .lifestyle: [
            AriaReferenceSource(title: "CDC: Healthy Eating & Activity", url: "https://www.cdc.gov/nutrition/index.html"),
            AriaReferenceSource(title: "MedlinePlus: Healthy Living", url: "https://medlineplus.gov/healthy-living.html"),
            AriaReferenceSource(title: "MedlinePlus: Stress", url: "https://medlineplus.gov/stress.html"),
        ],
        .activity: [
            AriaReferenceSource(title: "CDC: Adult Activity Guidelines", url: "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html"),
            AriaReferenceSource(title: "MedlinePlus: Exercise and Physical Fitness", url: "https://medlineplus.gov/exerciseandphysicalfitness.html"),
        ],
        .body: [
            AriaReferenceSource(title: "MedlinePlus: Vital Signs", url: "https://medlineplus.gov/ency/article/002341.htm"),
            AriaReferenceSource(title: "MedlinePlus: Body Temperature", url: "https://medlineplus.gov/ency/article/003090.htm"),
        ],
        .cycle: [
            AriaReferenceSource(title: "MedlinePlus: Menstruation", url: "https://medlineplus.gov/menstruation.html"),
            AriaReferenceSource(title: "OASH: Menstrual Cycle", url: "https://www.womenshealth.gov/menstrual-cycle"),
        ],
        .fever: [
            AriaReferenceSource(title: "MedlinePlus: Fever", url: "https://medlineplus.gov/fever.html"),
            AriaReferenceSource(title: "MedlinePlus: Body Temperature", url: "https://medlineplus.gov/ency/article/003090.htm"),
            AriaReferenceSource(title: "CDC: Caring for Someone Sick", url: "https://www.cdc.gov/flu/treatment/caring-for-someone.html"),
        ],
    ]

    /// Stable mix so Simulator and device agree for a given question + salt.
    /// `Hasher` is not process-stable; this is.
    public static func stableMix(_ text: String, salt: UInt64) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in text.lowercased().utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash ^ salt
    }

    public static func questionSuggestsFever(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["fever", "temperature", "too hot", "running hot", "chills", "thermometer", "100.", "99.5"]
            .contains { lower.contains($0) }
    }

    /// Event clothing / prep. Curated public-health pages only — never a shop.
    public static func questionSuggestsEventPrep(_ text: String) -> Bool {
        let lower = text.lowercased()
        if ["tuxedo", "tux ", "black tie", "what to wear", "what should i wear",
            "wedding attire", "suit for", "dress for a wedding", "outfit for"].contains(where: { lower.contains($0) }) {
            return true
        }
        return lower.contains("wedding") && (lower.contains("wear") || lower.contains("suit") || lower.contains("dress"))
    }

    public static func resolvedTopic(domainRawValue: String, question: String) -> AriaReferenceTopic {
        if questionSuggestsFever(question) { return .fever }
        if let topic = AriaReferenceTopic(rawValue: domainRawValue) {
            return topic
        }
        return .lifestyle
    }

    /// Ordered tries: keyword overlays first, then the domain table, rotated
    /// by question + salt so the primary page is not always the same CDC URL.
    public static func picks(
        topic: AriaReferenceTopic,
        question: String,
        salt: UInt64,
        limit: Int = 3
    ) -> [AriaReferencePick] {
        var pool = sources[topic] ?? []
        let lower = question.lowercased()
        if lower.contains("protein") || lower.contains("eat") || lower.contains("calorie") {
            pool = (sources[.nutrition] ?? []) + pool
        }
        if lower.contains("sleep") || lower.contains("insomnia") {
            pool = (sources[.sleep] ?? []) + pool
        }
        if questionSuggestsFever(question) {
            pool = (sources[.fever] ?? []) + pool
        }
        if questionSuggestsEventPrep(question) {
            pool = (sources[.lifestyle] ?? []) + pool
        }

        var unique: [AriaReferenceSource] = []
        var seen: Set<String> = []
        for source in pool where seen.insert(source.url).inserted {
            unique.append(source)
        }
        guard !unique.isEmpty else { return [] }

        let mix = stableMix(question, salt: salt)
        let rotation = slot(mix, modulo: unique.count)
        let rotated = Array(unique[rotation...]) + Array(unique[..<rotation])
        let leads = [
            "I checked —",
            "Looked it up live —",
            "Cross-checked a public source —",
            "Pulled a current page —",
        ]
        let lead = leads[slot(mix, modulo: leads.count)]
        let windows = [0, 180, 360, 540]

        return Array(rotated.prefix(limit)).enumerated().map { offset, source in
            AriaReferencePick(
                source: source,
                excerptStart: windows[slot(mix &+ UInt64(offset), modulo: windows.count)],
                voiceLead: "\(lead) \(source.title) notes"
            )
        }
    }

    /// `Int(UInt64)` traps when the value is above `Int.max`. Always reduce
    /// first so a high-bit djb2 mix cannot crash a lookup.
    private static func slot(_ mix: UInt64, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        return Int(mix % UInt64(modulo))
    }
}
