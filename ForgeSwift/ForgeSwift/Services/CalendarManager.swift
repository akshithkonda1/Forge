import Foundation
import EventKit
import Combine

/// Apple Calendar — so ARIA knows your time, not just your HRV.
/// Like HealthKit, it's optional and on-device. ARIA only sees a summary:
/// busy windows, not event titles or attendees, unless you tell it.
@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    private let store = EKEventStore()

    @Published var isAuthorized = false
    @Published var authorizationErrorMessage: String?

    @Published var upcomingEvents: [EKEvent] = []
    @Published var busyWindowsToday: Int = 0

    var calendarTags: [String] {
        // ARIA sees: calendar:busy:3, calendar:morning:busy — no titles, no PII
        var tags: [String] = []
        tags.append("calendar:busy:\(busyWindowsToday)")
        if !upcomingEvents.isEmpty {
            let morningBusy = upcomingEvents.contains { Calendar.current.component(.hour, from: $0.startDate) < 12 }
            if morningBusy { tags.append("calendar:morning:busy") }
            let eveningBusy = upcomingEvents.contains { Calendar.current.component(.hour, from: $0.startDate) >= 18 }
            if eveningBusy { tags.append("calendar:evening:busy") }
        }
        return tags
    }

    func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .authorized || status == .fullAccess {
            isAuthorized = true
            return
        }
        let granted = try await store.requestFullAccessToEvents()
        isAuthorized = granted
        if !granted {
            throw CalendarError.denied
        }
    }

    func fetchUpcoming(days: Int = 7) async {
        guard isAuthorized || authorizationStatus() == .authorized || authorizationStatus() == .fullAccess else { return }
        let calendars = store.calendars(for: .event)
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
        // Keep only non-all-day, not declined
        let filtered = events.filter { !$0.isAllDay && $0.availability != .free && $0.status != .none }
        await MainActor.run {
            self.upcomingEvents = filtered.sorted { $0.startDate < $1.startDate }.prefix(20).map { $0 }
            // Busy windows today
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
            self.busyWindowsToday = filtered.filter { $0.startDate >= today && $0.startDate < tomorrow }.count
        }
    }

    enum CalendarError: Error, LocalizedError {
        case denied
        var errorDescription: String? {
            "Calendar access was not granted. You can enable it in Settings → Privacy → Calendars."
        }
    }
}
