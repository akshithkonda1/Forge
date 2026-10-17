import Foundation

/// Versioned, cited public figures. Lockstep with `shared/population-baselines.json`.
///
/// Optional background reference only — never shown in the tutorial or as a
/// headline of how the person is doing. BMI is intentionally absent here;
/// standard BMI categories live as a quiet drill-in on ForgeHealthPotential.
/// HRV, hydration glasses, and stress scores have no honest national mean we
/// will show.
///
/// TODO: when Akshith's server-side population dataset ships, load it here
/// and keep this table as the offline fallback. Do not invent values.
public enum ForgePopulationBaselines: Sendable {
    public static let kind = "forge-population-baselines"
    public static let version = 1
    public static let serverDatasetStatus = "todo"

    public struct Metric: Equatable, Sendable {
        public var id: String
        public var unit: String
        public var value: Double
        public var year: Int
        public var population: String
        public var source: String
        public var url: String
        public var compareMode: String
        public var citation: String {
            "\(source) (\(year))"
        }
    }

    public static let shortSleepPrevalence = Metric(
        id: "shortSleepPrevalence",
        unit: "percent",
        value: 30.5,
        year: 2024,
        population: "US adults 18+",
        source: "NCHS Data Brief No. 559, National Health Interview Survey 2024",
        url: "https://www.cdc.gov/nchs/products/databriefs/db559.htm",
        compareMode: "prevalenceBelow7h"
    )

    public static let stepsPerDay = Metric(
        id: "stepsPerDay",
        unit: "steps",
        value: 6540,
        year: 2009,
        population: "US adults 20+",
        source: "Tudor-Locke C, Johnson WD, Katzmarzyk PT. Accelerometer-determined steps per day in US adults. Med Sci Sports Exerc. 2009;41(7):1384-1391. NHANES 2005–2006, steps censored below 500 activity counts/min (pedometer-comparable).",
        url: "https://pubmed.ncbi.nlm.nih.gov/19516163/",
        compareMode: "mean"
    )

    public static let metBothActivityGuidelines = Metric(
        id: "metBothActivityGuidelines",
        unit: "percent",
        value: 24.2,
        year: 2020,
        population: "US adults 18+",
        source: "NCHS Data Brief No. 443, National Health Interview Survey 2020",
        url: "https://www.cdc.gov/nchs/products/databriefs/db443.htm",
        compareMode: "prevalenceMetBoth"
    )

    public static let all: [Metric] = [
        shortSleepPrevalence, stepsPerDay, metBothActivityGuidelines,
    ]

    public static func metric(id: String) -> Metric? {
        all.first { $0.id == id }
    }
}
