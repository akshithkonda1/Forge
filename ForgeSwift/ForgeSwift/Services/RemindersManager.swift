import Foundation
import EventKit
import Combine
import ForgeCore

/// Apple Reminders — so ARIA knows your workload, not just your HRV.
///
/// Privacy contract
/// ----------------
/// What ARIA sees: `RemindersWorkload` counts only — overdue, due today, due
/// tomorrow, high priority, and one count per classified kind (health, travel,
/// work, social, errand, home, finance, other) — as `reminders:` tags and one
/// spoken line. On-device ARIA only: `AriaOnDeviceHealthPolicy` removes every
/// `reminders:` tag before a remote (/ai/chat) request, so Claude, Grok and the
/// Forge backend never receive them.
/// What stays on-device: everything else, and only in memory. Titles, notes and
/// list names are read inside EventKit's fetch callback, classified into a kind
/// by `ReminderItem`'s initializer, and dropped there — no `EKReminder` is ever
/// published or held. The workload is recomputed on each daily refresh and is
/// never written to disk, UserDefaults, or ARIA's saved context.
///
/// Off by default (Settings → Life Context). Turning the switch on asks iOS
/// once, only if iOS has never been asked. A "no" leaves a quiet link to iOS
/// Settings; Forge never prompts again on its own and the refresh path never
/// prompts at all.
@MainActor
final class RemindersManager: ObservableObject {
    static let shared = RemindersManager()

    enum AccessState: Equatable {
        /// The Forge switch is off.
        case off
        /// The switch is on and iOS has not been asked yet.
        case notConnected
        /// iOS said no, or Screen Time restricts Reminders.
        case denied
        case connected
    }

    private let store = EKEventStore()
    private let defaults = UserDefaults(suiteName: LifeContextSettings.suiteName)

    @Published var isAuthorized = false
    @Published var authorizationErrorMessage: String?
    @Published private(set) var isEnabled: Bool
    /// Nil until a refresh ran with access; memory only.
    @Published private(set) var workload: RemindersWorkload?
    @Published private(set) var lastRefreshed: Date?

    private init() {
        isEnabled = LifeContextSettings.load(from: UserDefaults(suiteName: LifeContextSettings.suiteName)).remindersEnabled
        isAuthorized = Self.hasReadAccess(EKEventStore.authorizationStatus(for: .reminder))
    }

    static func describeAccess(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess:
            return "full access"
        case .writeOnly:
            return "write-only — Forge needs read access to count reminders"
        case .denied:
            return "denied. Enable Reminders in Settings → Privacy → Reminders"
        case .restricted:
            return "restricted by Screen Time or a configuration profile"
        case .notDetermined:
            return "not asked yet"
        @unknown default:
            return "unknown (\(status.rawValue))"
        }
    }

    /// True when EventKit reports full Reminders read access.
    static func hasReadAccess(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }

    func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    var accessState: AccessState {
        guard isEnabled else { return .off }
        let status = authorizationStatus()
        if Self.hasReadAccess(status) { return .connected }
        switch status {
        case .denied, .restricted, .writeOnly:
            return .denied
        case .notDetermined, .fullAccess:
            return .notConnected
        @unknown default:
            return .notConnected
        }
    }

    // MARK: Switch

    /// The Settings → Life Context switch. On: ask iOS only if it has never
    /// been asked, then refresh. Off: drop the workload from memory.
    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        var settings = LifeContextSettings.load(from: defaults)
        settings.remindersEnabled = enabled
        settings.save(to: defaults)
        guard enabled else {
            workload = nil
            lastRefreshed = nil
            authorizationErrorMessage = nil
            return
        }
        if authorizationStatus() == .notDetermined {
            // A refusal is shown by the settings row, not thrown at the user.
            try? await requestAccess()
        }
        await ingestIfAuthorized()
    }

    func requestAccess() async throws {
        let status = authorizationStatus()
        if Self.hasReadAccess(status) {
            isAuthorized = true
            authorizationErrorMessage = nil
            return
        }
        switch status {
        case .denied, .restricted:
            isAuthorized = false
            authorizationErrorMessage = LifeIngestError.skipped(
                doing: "Reminders ingest",
                because: Self.describeAccess(status)
            )
            throw RemindersError.denied
        case .fullAccess:
            isAuthorized = true
            return
        case .writeOnly, .notDetermined:
            break
        @unknown default:
            break
        }
        let granted = try await requestFullAccessOnMain()
        isAuthorized = granted
        if !granted {
            authorizationErrorMessage = LifeIngestError.skipped(
                doing: "Reminders ingest",
                because: Self.describeAccess(authorizationStatus())
            )
            throw RemindersError.denied
        }
        authorizationErrorMessage = nil
    }

    /// Completion API on the main actor so EventKit presents the system sheet
    /// instead of aborting from a cooperative thread (same as CalendarManager).
    private func requestFullAccessOnMain() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: Daily refresh

    /// Called from the daily refresh. Never prompts. Switch off or no access →
    /// no workload, and nothing for ARIA.
    func ingestIfAuthorized(now: Date = Date()) async {
        let status = authorizationStatus()
        isAuthorized = Self.hasReadAccess(status)
        guard isEnabled, isAuthorized else {
            workload = nil
            if isEnabled, status == .denied || status == .restricted {
                authorizationErrorMessage = LifeIngestError.skipped(
                    doing: "Reminders ingest",
                    because: Self.describeAccess(status)
                )
            }
            return
        }
        authorizationErrorMessage = nil
        let calendar = Calendar.current
        let items = await fetchOpenItems(now: now, calendar: calendar)
        workload = RemindersWorkload.build(from: items, now: now, calendar: calendar)
        lastRefreshed = now
    }

    /// Incomplete reminders due up to the end of the horizon (overdue ones
    /// included). Text is classified and dropped inside the callback.
    private func fetchOpenItems(now: Date, calendar: Calendar) async -> [ReminderItem] {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: RemindersWorkload.horizonDays + 1, to: start) ?? now
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        return await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { reminder -> ReminderItem in
                    let components = reminder.dueDateComponents
                    return ReminderItem(
                        title: reminder.title ?? "",
                        listTitle: reminder.calendar?.title,
                        dueDate: components.flatMap { calendar.date(from: $0) },
                        hasDueTime: components?.hour != nil,
                        priority: reminder.priority,
                        isCompleted: reminder.isCompleted
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }

    // MARK: ARIA (on-device only)

    /// `reminders:` tags for on-device ARIA, or nothing when off / not connected.
    var ariaTags: [String] {
        guard isEnabled, isAuthorized, let workload else { return [] }
        return workload.ariaTags
    }

    var spokenLine: String? {
        guard isEnabled, isAuthorized, let workload else { return nil }
        return workload.spokenLine
    }

    enum RemindersError: Error, LocalizedError {
        case denied
        var errorDescription: String? {
            switch self {
            case .denied:
                return "Reminders access was not granted. You can enable it in Settings → Privacy → Reminders."
            }
        }
    }
}
