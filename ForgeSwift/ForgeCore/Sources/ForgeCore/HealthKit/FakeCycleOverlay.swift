import Foundation

/// One synthetic cycle day the Test-Ready pack and the in-app cycle logs share.
///
/// Strings, not ForgeSwift enums — ForgeCore stays UI-framework-light. The iOS
/// layer maps `flow` / `ovulationTest` / `cervicalMucus` / `symptoms` onto the
/// HealthKit and `CycleDayLog` types.
public struct FakeCycleDayFacts: Sendable, Equatable {
    public var dayInCycle: Int
    public var isCycleStart: Bool
    public var flow: String
    public var bbtCelsius: Double?
    public var ovulationTest: String?
    public var cervicalMucus: String?
    public var painScale: Int?
    public var symptoms: [String]
    public var phase: String

    public init(
        dayInCycle: Int,
        isCycleStart: Bool,
        flow: String,
        bbtCelsius: Double?,
        ovulationTest: String?,
        cervicalMucus: String?,
        painScale: Int?,
        symptoms: [String],
        phase: String
    ) {
        self.dayInCycle = dayInCycle
        self.isCycleStart = isCycleStart
        self.flow = flow
        self.bbtCelsius = bbtCelsius
        self.ovulationTest = ovulationTest
        self.cervicalMucus = cervicalMucus
        self.painScale = painScale
        self.symptoms = symptoms
        self.phase = phase
    }

    public var isBleeding: Bool {
        flow != "none" && flow != "unspecified" && !flow.isEmpty
    }
}

/// Deterministic cycle overlay so sleep/HRV and menstrual samples tell the same
/// month. Seed-pinned: tests stay reproducible; a new session seed changes the
/// body (pain, BBT jitter, which symptoms) without moving today's phase band.
public enum FakeCycleOverlay {
    public static let cycleLength = 28
    public static let periodLength = 5
    public static let cycleCount = 4

    /// Day-in-cycle for today, 10...16, so testers land in a named phase instead of bleeding.
    public static func currentDayInCycle(seed: Int) -> Int {
        10 + abs(seed % 7)
    }

    /// Facts for a day `offsetFromToday` days ago (0 = today).
    public static func facts(offsetFromToday: Int, seed: Int) -> FakeCycleDayFacts {
        let today = currentDayInCycle(seed: seed)
        let raw = today - offsetFromToday
        let wrapped = ((raw - 1) % cycleLength + cycleLength) % cycleLength + 1
        return facts(dayInCycle: wrapped, seed: seed, salt: offsetFromToday)
    }

    public static func facts(dayInCycle: Int, seed: Int, salt: Int) -> FakeCycleDayFacts {
        let dic = max(1, min(cycleLength, dayInCycle))
        let mix = mixer(seed, salt, dic)
        let isStart = dic == 1
        let flow = flow(onPeriodDay: dic)
        let phase = phaseLabel(dayInCycle: dic)
        let bbt = bbtCelsius(dayInCycle: dic, mix: mix)
        let opk = ovulationTest(dayInCycle: dic, mix: mix)
        let mucus = cervicalMucus(dayInCycle: dic, mix: mix)
        let pain = painScale(dayInCycle: dic, flow: flow, mix: mix)
        let symptoms = symptoms(dayInCycle: dic, flow: flow, mix: mix)
        return FakeCycleDayFacts(
            dayInCycle: dic,
            isCycleStart: isStart,
            flow: flow,
            bbtCelsius: bbt,
            ovulationTest: opk,
            cervicalMucus: mucus,
            painScale: pain,
            symptoms: symptoms,
            phase: phase
        )
    }

    public static func phaseLabel(dayInCycle: Int) -> String {
        switch dayInCycle {
        case 1...5: return "menstruation"
        case 6...9: return "follicular"
        case 10...13: return "fertileWindow"
        case 14: return "ovulation"
        default: return "luteal"
        }
    }

    public static func flow(onPeriodDay day: Int) -> String {
        switch day {
        case 1: return "medium"
        case 2: return "heavy"
        case 3: return "medium"
        case 4: return "light"
        case 5: return "spotting"
        default: return "none"
        }
    }

    private static func bbtCelsius(dayInCycle: Int, mix: Int) -> Double {
        let jitter = Double((mix % 9) - 4) / 100.0
        let base: Double
        if dayInCycle >= 15 {
            base = 36.68
        } else if dayInCycle == 14 {
            base = 36.52
        } else {
            base = 36.38
        }
        return (base + jitter).rounded(toPlaces: 2)
    }

    private static func ovulationTest(dayInCycle: Int, mix: Int) -> String? {
        switch dayInCycle {
        case 13:
            return "lhSurge"
        case 12:
            return mix % 3 == 0 ? "positive" : "negative"
        case 11, 14:
            return "negative"
        default:
            return nil
        }
    }

    private static func cervicalMucus(dayInCycle: Int, mix: Int) -> String? {
        switch dayInCycle {
        case 1...5:
            return mix % 2 == 0 ? "dry" : nil
        case 10...13:
            return mix % 2 == 0 ? "eggWhite" : "watery"
        case 14...16:
            return "creamy"
        case 6...9:
            return mix % 3 == 0 ? "sticky" : "dry"
        default:
            return mix % 4 == 0 ? "sticky" : "dry"
        }
    }

    private static func painScale(dayInCycle: Int, flow: String, mix: Int) -> Int? {
        switch flow {
        case "heavy":
            return 6 + (mix % 3)
        case "medium":
            return 4 + (mix % 3)
        case "light", "spotting":
            return 2 + (mix % 3)
        default:
            if dayInCycle >= 22 { return mix % 5 == 0 ? 3 : nil }
            return nil
        }
    }

    private static func symptoms(dayInCycle: Int, flow: String, mix: Int) -> [String] {
        var out: [String] = []
        if flow != "none" {
            out.append("cramps")
            if mix % 2 == 0 { out.append("fatigue") }
            if mix % 3 == 0 { out.append("backache") }
            if flow == "heavy" { out.append("pelvicPain") }
        } else if dayInCycle >= 22 {
            out.append("bloating")
            if mix % 2 == 0 { out.append("moodLow") }
            if mix % 3 == 0 { out.append("breastTenderness") }
        } else if (10...14).contains(dayInCycle) {
            if mix % 2 == 0 { out.append("libidoHigh") }
            if mix % 3 == 0 { out.append("energyHigh") }
        } else if (6...9).contains(dayInCycle) {
            if mix % 2 == 0 { out.append("energyHigh") }
        }
        return out
    }

    /// Order-independent mixer — must not share FakeHealthPack's SplitMix64 cursor.
    private static func mixer(_ seed: Int, _ salt: Int, _ day: Int) -> Int {
        var x = UInt64(truncatingIfNeeded: seed)
        x &+= UInt64(truncatingIfNeeded: salt) &* 0x9E3779B97F4A7C15
        x &+= UInt64(truncatingIfNeeded: day) &* 0xBF58476D1CE4E5B9
        x ^= x >> 30
        x &*= 0xBF58476D1CE4E5B9
        x ^= x >> 27
        x &*= 0x94D049BB133111EB
        x ^= x >> 31
        return Int(truncatingIfNeeded: x & 0x7FFF_FFFF)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
