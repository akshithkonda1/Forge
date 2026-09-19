import Foundation

/// What Forge already reads — four bullets, then stop.
///
/// Stolen from the Oura membership insert's scannability, not its paywall
/// or its six-room museum. Women's health stays rhythm + support, not a
/// period-prediction add-on. Metabolic glucose is an accessory.
public struct TranslationPillar: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var symbolName: String
    public var bullets: [String]
    /// Honest hardware language. Nil unless the pillar needs an accessory.
    public var accessoryNote: String?

    public init(
        id: String,
        title: String,
        symbolName: String,
        bullets: [String],
        accessoryNote: String? = nil
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.bullets = bullets
        self.accessoryNote = accessoryNote
    }
}

public enum TranslationCatalog: Sendable {
    public static let tagline = "Your body talks. Forge translates."

    public static let metabolicAccessoryNote =
        "Glucose via Stelo, Dexcom, Lingo, or Libre — sold separately. Forge reads it after you share it into Apple Health."

    public static let sleep = TranslationPillar(
        id: "sleep",
        title: "Sleep",
        symbolName: "moon.zzz.fill",
        bullets: [
            "Last night and stages",
            "Chronotype",
            "Sleep debt",
            "Wind-down and smart wake",
        ]
    )

    public static let train = TranslationPillar(
        id: "train",
        title: "Train",
        symbolName: "figure.strengthtraining.traditional",
        bullets: [
            "Today’s session",
            "Workout heart rate",
            "Steps and active calories",
            "Training load",
        ]
    )

    public static let metabolic = TranslationPillar(
        id: "metabolic",
        title: "Metabolic",
        symbolName: "fork.knife",
        bullets: [
            "Meals you logged",
            "Nutritional breakdown",
            "Hydration",
            "Glucose from a CGM",
        ],
        accessoryNote: metabolicAccessoryNote
    )

    public static let stress = TranslationPillar(
        id: "stress",
        title: "Stress",
        symbolName: "brain.head.profile",
        bullets: [
            "Daytime load",
            "Mindfulness minutes",
            "Recovery",
            "Night wind-down",
        ]
    )

    public static let heart = TranslationPillar(
        id: "heart",
        title: "Heart",
        symbolName: "heart.fill",
        bullets: [
            "Cardiovascular age vs calendar age",
            "VO₂ max",
            "Heart rate variability",
            "All-day heart rate",
        ]
    )

    public static let cycle = TranslationPillar(
        id: "cycle",
        title: "Cycle",
        symbolName: "circle.dotted",
        bullets: [
            "Phase and day",
            "Period as a range",
            "Training by phase",
            "Support for the people around you",
        ]
    )

    public static var all: [TranslationPillar] {
        [sleep, train, metabolic, stress, heart, cycle]
    }

    public static func pillar(id: String) -> TranslationPillar? {
        all.first { $0.id == id }
    }
}
