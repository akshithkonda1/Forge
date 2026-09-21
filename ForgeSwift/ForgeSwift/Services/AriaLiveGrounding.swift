import Foundation

/// One instantaneous snapshot of on-device life signals Dummy / local ARIA
/// may coach from. Built from AppStore (HealthKit hydrate or Test-Ready pack)
/// — never invented at speak time.
struct AriaLiveGroundingSnapshot: Equatable, Sendable {
    enum GroundSource: String, Sendable {
        /// Fresh HealthKit samples applied this process.
        case healthKit = "healthkit"
        /// Simulator / tester FakeHealthPack still filling the board.
        case testReadyPack = "pack"
        /// In-memory AppStore values without a pack or live HK stamp.
        case store = "store"
        /// Nothing usable yet.
        case empty = "empty"
    }

    var capturedAt: Date
    var sleepHours: Double?
    var deepMinutes: Int?
    var hrvMs: Int?
    var restingHR: Int?
    var steps: Int?
    var activeCalories: Int?
    var readiness: Int
    var source: GroundSource

    static let empty = AriaLiveGroundingSnapshot(
        capturedAt: .distantPast,
        sleepHours: nil,
        deepMinutes: nil,
        hrvMs: nil,
        restingHR: nil,
        steps: nil,
        activeCalories: nil,
        readiness: 0,
        source: .empty
    )

    var hasLifeSignal: Bool {
        (sleepHours ?? 0) > 0
            || (hrvMs ?? 0) > 0
            || (steps ?? 0) > 0
            || (activeCalories ?? 0) > 0
            || readiness > 0
    }

    /// Short tag for Dummy confidenceReason — proves the turn used the stream.
    var reasonTag: String {
        switch source {
        case .healthKit: return "live-stream · healthkit"
        case .testReadyPack: return "live-stream · pack"
        case .store: return "live-stream · store"
        case .empty: return "live-stream · empty"
        }
    }

    @MainActor
    static func from(store: AppStore) -> AriaLiveGroundingSnapshot {
        let night = store.sleepData.first
        let sleepHours: Double? = {
            if let night, night.totalHours > 0 { return night.totalHours }
            if store.dailyMetrics.totalSleep > 0 {
                return Double(store.dailyMetrics.totalSleep) / 60.0
            }
            return nil
        }()
        let hrv = store.dailyMetrics.hrv > 0 ? store.dailyMetrics.hrv : nil
        let rhr = store.dailyMetrics.restingHR > 0 ? store.dailyMetrics.restingHR : nil
        let steps = store.dailyMetrics.steps > 0 ? store.dailyMetrics.steps : nil
        let cal = store.dailyMetrics.activeCalories > 0 ? store.dailyMetrics.activeCalories : nil
        let deep = night.map(\.deepMinutes).flatMap { $0 > 0 ? $0 : nil }
            ?? (store.dailyMetrics.deepSleep > 0 ? store.dailyMetrics.deepSleep : nil)

        let source: GroundSource = {
            let hasSignal = (sleepHours ?? 0) > 0 || hrv != nil || steps != nil || cal != nil
                || store.readiness.overall > 0
            guard hasSignal else { return .empty }
            if store.healthKitLive, !store.usingTestReadyHealthPack { return .healthKit }
            if store.usingTestReadyHealthPack { return .testReadyPack }
            return .store
        }()

        return AriaLiveGroundingSnapshot(
            capturedAt: Date(),
            sleepHours: sleepHours,
            deepMinutes: deep,
            hrvMs: hrv,
            restingHR: rhr,
            steps: steps,
            activeCalories: cal,
            readiness: store.readiness.overall,
            source: source
        )
    }
}

/// Instantaneous on-device feed into Dummy. Chat turns and HealthKit hydrates
/// publish here so ARIA pulls from data that is already on the phone instead
/// of inventing vitals. Network-free — no SSE, no cloud.
@MainActor
final class AriaLiveGroundingHub {
    static let shared = AriaLiveGroundingHub()

    /// Latest snapshot Dummy / tests can read without awaiting the stream.
    private(set) var latest: AriaLiveGroundingSnapshot = .empty

    /// Drop duplicate publishes closer than this (observer bursts + chat).
    static let coalesceSeconds: TimeInterval = 0.35

    /// Turn hydrate may skip HealthKit if a fresh publish landed inside this window.
    static let turnHydrateCoalesceSeconds: TimeInterval = 20

    private var continuations: [UUID: AsyncStream<AriaLiveGroundingSnapshot>.Continuation] = [:]
    private var lastPublishAt: Date?

    private init() {}

    /// Subscribe to instantaneous snapshot updates for a Dummy turn or test.
    func snapshots() -> AsyncStream<AriaLiveGroundingSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(latest)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    func publish(_ snapshot: AriaLiveGroundingSnapshot, force: Bool = false) {
        if !force,
           let last = lastPublishAt,
           Date().timeIntervalSince(last) < Self.coalesceSeconds,
           snapshot.source == latest.source,
           snapshot.sleepHours == latest.sleepHours,
           snapshot.hrvMs == latest.hrvMs,
           snapshot.readiness == latest.readiness {
            return
        }
        latest = snapshot
        lastPublishAt = Date()
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    func publish(from store: AppStore, force: Bool = false) {
        publish(.from(store: store), force: force)
    }

    /// Test helper — clears stream state between XCTest cases.
    func resetForTests() {
        latest = .empty
        lastPublishAt = nil
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
