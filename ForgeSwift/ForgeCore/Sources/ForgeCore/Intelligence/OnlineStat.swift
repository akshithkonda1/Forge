import Foundation

/// Streaming mean/variance (Welford) plus EWMA.
///
/// Mirrors `backend/infra/lambda/services/biometrics/statistics.py` `OnlineStat`
/// so on-device sleep depth and the Lambda recovery path share one definition
/// of "unusual for you". Update once per sample; read `mean` / `std` / `ewma`
/// without retaining the series.
public struct OnlineStat: Codable, Equatable, Sendable {
    public private(set) var n: Int
    private var meanValue: Double
    private var m2: Double
    private var ewmaValue: Double
    public var alpha: Double
    public private(set) var last: Double?

    public init(alpha: Double = 0.3) {
        n = 0
        meanValue = 0
        m2 = 0
        ewmaValue = 0
        self.alpha = alpha
        last = nil
    }

    public mutating func update(_ value: Double) {
        n += 1
        let delta = value - meanValue
        meanValue += delta / Double(n)
        m2 += delta * (value - meanValue)
        ewmaValue = n == 1 ? value : alpha * value + (1 - alpha) * ewmaValue
        last = value
    }

    public var mean: Double { meanValue }

    public var variance: Double {
        n > 1 ? m2 / Double(n - 1) : 0
    }

    public var std: Double { variance.squareRoot() }

    public var ewma: Double { ewmaValue }

    public func zscore(_ value: Double) -> Double {
        if std > 1e-9 { return (value - meanValue) / std }
        if n == 0 { return 0 }
        let delta = value - meanValue
        if abs(delta) < 1e-9 { return 0 }
        return delta > 0 ? 1e3 : -1e3
    }
}
