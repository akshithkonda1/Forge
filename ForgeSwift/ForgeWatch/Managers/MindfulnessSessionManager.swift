import Foundation
import WatchKit
import Observation
import ForgeCore

// MARK: - MindfulnessSessionManager
//
// Owns the full session lifecycle: countdown of phases, haptic guidance,
// pause/resume bookkeeping, HealthKit logging, biofeedback, and the
// debrief. Haptics are scheduled here (not in the view) so the eyes-free
// experience works with the wrist down and the screen off.

@MainActor
@Observable
final class MindfulnessSessionManager {

    enum State: Equatable {
        case idle
        case active
        case paused
        case debrief
    }

    enum HapticIntensity: String, CaseIterable {
        case gentle
        case strong

        var label: String { self == .gentle ? "Gentle" : "Strong" }
    }

    struct Debrief: Equatable {
        var practice: PracticeType
        var minutesLogged: Double
        var message: String
        var biofeedbackLine: String?
        var heartRateSettleBPM: Double?
        var healthKitSaved: Bool
    }

    private(set) var state: State = .idle
    private(set) var activePractice: PracticeType?
    private(set) var plannedDuration: TimeInterval = 180
    private(set) var startedAt: Date?
    private(set) var debrief: Debrief?
    private(set) var lastSkipAcknowledgement: String?

    var hapticIntensity: HapticIntensity {
        didSet { defaults?.set(hapticIntensity.rawValue, forKey: Keys.haptics) }
    }

    /// Completed-session records for the local consistency view. Kept small
    /// (last 50) — the long-term record lives in HealthKit.
    private(set) var recentSessions: [MindfulnessSessionRecord] = []

    var sessionsCompletedToday: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return recentSessions.filter { $0.completed && $0.startedAt >= startOfDay }.count
    }

    // Pause bookkeeping lives in ForgeCore's SessionClock, where it is tested.
    // It used to be two mutable fields updated from five call sites, none of
    // which anything checked.
    private var clock = SessionClock()
    private var runner: Task<Void, Never>?

    private let defaults = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)
    private enum Keys {
        static let haptics = "forge.watch.mindfulness.hapticIntensity"
        static let sessions = "forge.watch.mindfulness.recentSessions.v1"
    }

    init() {
        hapticIntensity = defaults?.string(forKey: Keys.haptics)
            .flatMap(HapticIntensity.init(rawValue:)) ?? .gentle
        if let data = defaults?.data(forKey: Keys.sessions),
           let records = try? JSONDecoder().decode([MindfulnessSessionRecord].self, from: data) {
            recentSessions = records
        }
    }

    var activePattern: BreathingPattern? { activePractice?.pattern }

    /// Seconds of actual practice completed at `date` (frame-accurate for
    /// the BreathingOrb, pause-aware).
    func elapsed(at date: Date) -> TimeInterval {
        clock.elapsed(at: date)
    }

    func remaining(at date: Date) -> TimeInterval {
        clock.remaining(at: date, of: plannedDuration)
    }

    // MARK: Lifecycle

    func start(practice: PracticeType, duration: TimeInterval, health: WatchHealthKitManager) {
        guard state == .idle || state == .debrief else { return }
        activePractice = practice
        plannedDuration = duration
        let now = Date()
        startedAt = now
        clock = .started(at: now)
        debrief = nil
        lastSkipAcknowledgement = nil
        state = .active

        WKInterfaceDevice.current().play(.start)
        Task { await health.beginMindfulHeartRateCapture() }
        runner = Task { [weak self, weak health] in
            await self?.run(health: health)
        }
    }

    func pause() {
        guard state == .active else { return }
        clock = clock.paused(at: Date())
        runner?.cancel()
        runner = nil
        state = .paused
        WKInterfaceDevice.current().play(.stop)
    }

    func resume(health: WatchHealthKitManager) {
        guard state == .paused else { return }
        clock = clock.resumed(at: Date())
        state = .active
        WKInterfaceDevice.current().play(.start)
        runner = Task { [weak self, weak health] in
            await self?.run(health: health)
        }
    }

    /// Ends now. Anything ≥ 30s of practice still counts — partial resets
    /// are real resets, not failures.
    func endEarly(health: WatchHealthKitManager) {
        guard state == .active || state == .paused else { return }
        runner?.cancel()
        runner = nil
        clock = clock.stopped(at: Date())
        Task { await finish(health: health) }
    }

    /// Zero-judgment skip from the pre-session card (no timer ever ran).
    func skip(reason: SkipReason) {
        lastSkipAcknowledgement = reason.acknowledgement
        let record = MindfulnessSessionRecord(
            practice: activePractice ?? .focusReset,
            startedAt: Date(), endedAt: Date(),
            completed: false, skipReason: reason
        )
        appendRecord(record)
        WKInterfaceDevice.current().play(.click)
        reset()
    }

    func dismissDebrief() {
        debrief = nil
        state = .idle
    }

    // MARK: Runner

    /// Walks breathing phases, playing a haptic at each transition, until
    /// the planned duration elapses. Runs as a cancellable Task so pause /
    /// end are instant.
    private func run(health: WatchHealthKitManager?) async {
        guard let pattern = activePattern else { return }
        while !Task.isCancelled {
            let now = Date()
            let elapsedNow = elapsed(at: now)
            if elapsedNow >= plannedDuration { break }

            let (phase, progress) = pattern.phase(at: elapsedNow)
            playHaptic(for: phase.kind)

            // Sleep to the end of this phase (or session end, whichever first).
            let phaseRemaining = phase.duration * (1 - progress)
            let sessionRemaining = plannedDuration - elapsedNow
            let sleepFor = max(0.05, min(phaseRemaining, sessionRemaining))
            do {
                try await Task.sleep(for: .seconds(sleepFor))
            } catch {
                return // paused or ended — bookkeeping already handled
            }
        }
        guard !Task.isCancelled else { return }
        clock = clock.completed(of: plannedDuration)
        if let health { await finish(health: health) }
    }

    private func finish(health: WatchHealthKitManager) async {
        guard let practice = activePractice, let startedAt else {
            reset()
            return
        }
        runner = nil

        let practicedSeconds = clock.accumulated
        let endDate = Date()
        let biofeedback = await health.endMindfulHeartRateCapture()

        var saved = false
        let countsAsSession = practicedSeconds >= 30
        if countsAsSession {
            do {
                try await health.logMindfulSession(
                    start: endDate.addingTimeInterval(-practicedSeconds),
                    end: endDate
                )
                saved = true
            } catch {
                saved = false
            }
            appendRecord(MindfulnessSessionRecord(
                practice: practice,
                startedAt: startedAt, endedAt: endDate,
                completed: true
            ))
        }

        WKInterfaceDevice.current().play(.success)
        debrief = Debrief(
            practice: practice,
            minutesLogged: countsAsSession ? practicedSeconds / 60 : 0,
            message: debriefMessage(practice: practice, seconds: practicedSeconds),
            biofeedbackLine: biofeedbackLine(from: biofeedback),
            heartRateSettleBPM: biofeedback?.settleBPM,
            healthKitSaved: saved
        )
        state = .debrief
        activePractice = nil
        self.startedAt = nil
    }

    private func reset() {
        runner?.cancel()
        runner = nil
        state = .idle
        activePractice = nil
        startedAt = nil
        clock = SessionClock()
    }

    // MARK: Haptics
    //
    // Directional language: rising haptic = draw breath in, falling = let
    // it go, click = hold. Gentle keeps everything at .click except the
    // session bookends; Strong uses the full directional vocabulary.

    private func playHaptic(for kind: BreathPhaseKind) {
        let device = WKInterfaceDevice.current()
        switch hapticIntensity {
        case .gentle:
            if kind != .rest { device.play(.click) }
        case .strong:
            switch kind {
            case .inhale, .quickInhale: device.play(.directionUp)
            case .exhale:               device.play(.directionDown)
            case .holdIn, .holdOut:     device.play(.click)
            case .rest:                 break // silence is part of the practice
            }
        }
    }

    // MARK: Records

    private func appendRecord(_ record: MindfulnessSessionRecord) {
        recentSessions.append(record)
        if recentSessions.count > 50 {
            recentSessions.removeFirst(recentSessions.count - 50)
        }
        if let data = try? JSONEncoder().encode(recentSessions) {
            defaults?.set(data, forKey: Keys.sessions)
        }
    }

    // MARK: Copy

    private func debriefMessage(practice: PracticeType, seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        switch practice {
        case .physiologicalSigh, .focusReset:
            return "Reset complete. That's your focus compounding, not time lost — back to it whenever you're ready."
        case .boxBreathing, .stressRelease:
            return "Nicely done. Your nervous system got \(max(1, minutes)) real minute\(minutes == 1 ? "" : "s") of down-shift."
        case .bodyScan:
            return "Scan complete. Noticing is the skill — everything else builds on it."
        case .windDown:
            return "Good landing. Let the evening stay this soft."
        case .morningGrounding:
            return "Grounded. Start how you mean to continue — you just did."
        }
    }

    private func biofeedbackLine(from biofeedback: WatchHealthKitManager.MindfulBiofeedback?) -> String? {
        guard let settle = biofeedback?.settleBPM else { return nil }
        // Epistemic honesty: report only clear, positive-or-neutral shifts,
        // and phrase them as observations, not verdicts.
        if settle >= 3 {
            return "Heart rate settled about \(Int(settle.rounded())) bpm over the session — a real downshift."
        }
        if settle >= 1 {
            return "Heart rate eased slightly — the direction that matters."
        }
        return nil // no negative framing, ever
    }
}
