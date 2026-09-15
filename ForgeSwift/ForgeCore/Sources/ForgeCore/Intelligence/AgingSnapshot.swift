import Foundation

/// Calendar age vs fused training / biological age.
///
/// Lifestyle comparison only — never a medical biological-age diagnosis.
/// Mirrors `backend/infra/lambda/services/biometrics/estimators.py` so iOS
/// and ARIA reason over the same numbers.
public struct AgingVendorAge: Sendable, Equatable {
    public var kind: Kind
    public var years: Double
    public var confidence: Double
    public var source: String

    public enum Kind: String, Sendable, CaseIterable {
        case biological
        case fitness
        case phenotypic
        case vascular
        case metabolic
        case inner
        case cardio
        case hrv
    }

    public init(kind: Kind, years: Double, confidence: Double = 0.85, source: String) {
        self.kind = kind
        self.years = years
        self.confidence = confidence
        self.source = source
    }

    /// Map a health-batch / vendor identifier onto a captured age. Calendar age
    /// is not a vendor age — that comes from the profile.
    public init?(metricType: String, years: Double, source: String, confidence: Double = 0.85) {
        guard years >= 13, years <= 120 else { return nil }
        let key = metricType.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let kind: Kind?
        switch key {
        case "biological-age", "bio-age", "true-age", "real-age":
            kind = .biological
        case "fitness-age", "garmin-fitness-age", "physio-age":
            kind = .fitness
        case "phenotypic-age", "pheno-age":
            kind = .phenotypic
        case "vascular-age", "heart-age", "arterial-age":
            kind = .vascular
        case "metabolic-age", "body-age":
            kind = .metabolic
        case "inner-age", "oura-age":
            kind = .inner
        case "cardio-age", "vo2-age":
            kind = .cardio
        case "hrv-age", "recovery-age", "autonomic-age":
            kind = .hrv
        default:
            kind = nil
        }
        guard let kind else { return nil }
        self.init(kind: kind, years: years, confidence: confidence, source: source)
    }
}

public struct AgingComponent: Sendable, Equatable {
    public var name: String
    public var years: Double
    public var state: AgingDeltaState
    public var source: String
}

public enum AgingDeltaState: String, Sendable, Equatable {
    case younger
    case matched
    case older
    case unknown
}

public struct AgingSnapshot: Sendable, Equatable {
    public var chronologicalAge: Double?
    public var biologicalAge: Double?
    public var fitnessAge: Double?
    public var vascularAge: Double?
    public var autonomicAge: Double?
    /// biological − chronological. Negative means younger training age.
    public var deltaYears: Double?
    public var confidence: Double
    public var state: AgingDeltaState
    public var sources: [String]
    public var components: [AgingComponent]
    /// Lifestyle copy for Train / Life. Never a diagnosis.
    public var comparisonLine: String
    public var trainingHint: String

    public var hasComparison: Bool {
        chronologicalAge != nil && biologicalAge != nil
    }

    public var showsOnTrain: Bool {
        chronologicalAge != nil
    }

    public static let empty = AgingSnapshot(
        chronologicalAge: nil,
        biologicalAge: nil,
        fitnessAge: nil,
        vascularAge: nil,
        autonomicAge: nil,
        deltaYears: nil,
        confidence: 0,
        state: .unknown,
        sources: [],
        components: [],
        comparisonLine: "",
        trainingHint: ""
    )

    public static func evaluate(
        chronologicalAge: Double?,
        sexFemale: Bool? = nil,
        vo2Max: Double? = nil,
        hrv: Double? = nil,
        restingHR: Double? = nil,
        sleepHours: Double? = nil,
        vendorAges: [AgingVendorAge] = []
    ) -> AgingSnapshot {
        let chrono = chronologicalAge.flatMap { $0 >= 13 && $0 <= 120 ? $0 : nil }
        var estimated: [String: (Double, Double, String)] = [:]
        var components: [AgingComponent] = []

        if let chrono, let vo2 = positive(vo2Max) {
            let years = fitnessAge(fromVO2: vo2, chronologicalAge: chrono, sexFemale: sexFemale)
            estimated["fitness_age_est"] = (years, 0.55, "vo2")
            components.append(AgingComponent(name: "Cardio", years: years, state: deltaState(years - chrono), source: "VO₂"))
        }
        if let chrono, let rhr = positive(restingHR) {
            let years = vascularAge(fromRHR: rhr, chronologicalAge: chrono)
            estimated["vascular_age_est"] = (years, 0.45, "rhr")
            components.append(AgingComponent(name: "Resting HR", years: years, state: deltaState(years - chrono), source: "RHR"))
        }
        if let chrono, let hrvMs = positive(hrv) {
            let years = autonomicAge(fromHRV: hrvMs, chronologicalAge: chrono)
            estimated["autonomic_age_est"] = (years, 0.5, "hrv")
            components.append(AgingComponent(name: "Recovery", years: years, state: deltaState(years - chrono), source: "HRV"))
        }
        if let chrono, let hours = positive(sleepHours) {
            let years = sleepAge(fromHours: hours, chronologicalAge: chrono)
            estimated["sleep_age_est"] = (years, 0.35, "sleep")
            components.append(AgingComponent(name: "Sleep", years: years, state: deltaState(years - chrono), source: "Sleep"))
        }

        var parts: [(Double, Double, String)] = []
        let vendorWeights: [AgingVendorAge.Kind: Double] = [
            .biological: 0.40, .fitness: 0.22, .phenotypic: 0.18, .vascular: 0.12,
            .metabolic: 0.10, .inner: 0.12, .cardio: 0.14, .hrv: 0.10
        ]
        for vendor in vendorAges where vendor.years >= 13 && vendor.years <= 120 {
            let weight = (vendorWeights[vendor.kind] ?? 0.1) * max(0.2, min(1.0, vendor.confidence))
            parts.append((vendor.years, weight, "\(vendor.source):\(vendor.kind.rawValue)"))
            components.insert(
                AgingComponent(
                    name: vendor.kind.rawValue.capitalized,
                    years: vendor.years,
                    state: chrono.map { deltaState(vendor.years - $0) } ?? .unknown,
                    source: vendor.source
                ),
                at: 0
            )
        }
        let estWeights: [String: Double] = [
            "fitness_age_est": 0.18, "vascular_age_est": 0.12,
            "autonomic_age_est": 0.14, "sleep_age_est": 0.08
        ]
        for (key, weight) in estWeights {
            guard let est = estimated[key] else { continue }
            parts.append((est.0, weight * est.1, est.2))
        }

        let fused: Double?
        let confidence: Double
        if parts.isEmpty {
            fused = chrono
            confidence = chrono == nil ? 0 : 0.2
        } else {
            let total = parts.reduce(0.0) { $0 + $1.1 }
            fused = clampAge(parts.reduce(0.0) { $0 + $1.0 * $1.1 } / total, chronological: chrono)
            confidence = min(0.92, max(0.2, total))
        }

        let delta = zipOptional(fused, chrono).map { $0 - $1 }
        let state = delta.map(deltaState) ?? .unknown
        let sources = parts.map(\.2)
        let roundedBio = fused.map { ($0 * 10).rounded() / 10 }
        let roundedChrono = chrono.map { ($0 * 10).rounded() / 10 }
        let roundedDelta = delta.map { ($0 * 10).rounded() / 10 }

        return AgingSnapshot(
            chronologicalAge: roundedChrono,
            biologicalAge: roundedBio,
            fitnessAge: estimated["fitness_age_est"]?.0 ?? vendorAges.first(where: { $0.kind == .fitness })?.years,
            vascularAge: estimated["vascular_age_est"]?.0 ?? vendorAges.first(where: { $0.kind == .vascular })?.years,
            autonomicAge: estimated["autonomic_age_est"]?.0 ?? vendorAges.first(where: { $0.kind == .hrv })?.years,
            deltaYears: roundedDelta,
            confidence: (confidence * 100).rounded() / 100,
            state: state,
            sources: sources,
            components: components,
            comparisonLine: comparisonLine(chrono: roundedChrono, bio: roundedBio, delta: roundedDelta, state: state, confidence: confidence),
            trainingHint: trainingHint(state: state, delta: roundedDelta)
        )
    }

    public static func expectedVO2(age: Double, sexFemale: Bool?) -> Double {
        let intercept: Double
        let slope: Double
        if sexFemale == true {
            intercept = 41.0; slope = 0.32
        } else if sexFemale == false {
            intercept = 48.0; slope = 0.37
        } else {
            intercept = 44.5; slope = 0.345
        }
        return ((intercept - slope * max(0, age - 20)) * 10).rounded() / 10
    }
}

private func fitnessAge(fromVO2 vo2: Double, chronologicalAge: Double, sexFemale: Bool?) -> Double {
    let expected = AgingSnapshot.expectedVO2(age: chronologicalAge, sexFemale: sexFemale)
    return clampAge(chronologicalAge + (expected - vo2) * 0.7, chronological: chronologicalAge)
}

private func vascularAge(fromRHR rhr: Double, chronologicalAge: Double) -> Double {
    let expected = 60.0 + 0.1 * max(0, chronologicalAge - 25)
    return clampAge(chronologicalAge + (rhr - expected) * 0.5, chronological: chronologicalAge)
}

private func autonomicAge(fromHRV hrv: Double, chronologicalAge: Double) -> Double {
    let expected = max(20.0, 55.0 - 0.4 * max(0, chronologicalAge - 25))
    return clampAge(chronologicalAge + (expected - hrv) * 0.2, chronological: chronologicalAge)
}

private func sleepAge(fromHours hours: Double, chronologicalAge: Double) -> Double {
    let need = 8.0 - 0.015 * max(0, chronologicalAge - 25)
    return clampAge(chronologicalAge + (need - hours) * 2.0, chronological: chronologicalAge)
}

private func clampAge(_ value: Double, chronological: Double? = nil) -> Double {
    var lo = 18.0
    var hi = 90.0
    if let chronological {
        lo = max(lo, chronological - 12)
        hi = min(hi, chronological + 12)
    }
    return min(hi, max(lo, (value * 10).rounded() / 10))
}

private func deltaState(_ delta: Double) -> AgingDeltaState {
    if delta <= -2 { return .younger }
    if delta >= 2 { return .older }
    return .matched
}

private func positive(_ value: Double?) -> Double? {
    guard let value, value > 0 else { return nil }
    return value
}

private func zipOptional<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

private func comparisonLine(chrono: Double?, bio: Double?, delta: Double?, state: AgingDeltaState, confidence: Double) -> String {
    guard let chrono else { return "" }
    guard let bio, let delta, confidence > 0.25 else {
        return "\(Int(chrono.rounded())) · calendar age"
    }
    if state == .matched {
        return "\(Int(bio.rounded())) vs \(Int(chrono.rounded())) · on pace"
    }
    let years = Int(abs(delta).rounded())
    let word = state == .younger ? "younger" : "older"
    return "\(Int(bio.rounded())) vs \(Int(chrono.rounded())) · \(years)y \(word)"
}

private func trainingHint(state: AgingDeltaState, delta: Double?) -> String {
    switch state {
    case .younger:
        return "Training age is younger than the calendar. Protect the sleep and aerobic work that got you here."
    case .older:
        let years = delta.map { Int(abs($0).rounded()) } ?? 2
        return "Training age is running about \(years) years older. Recovery, sleep, and easy aerobic work move this more than grinding volume."
    case .matched:
        return "Training age is tracking calendar age. Keep the week honest."
    case .unknown:
        return ""
    }
}
