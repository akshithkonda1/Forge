import Foundation
import EventKit
import CoreLocation
import Combine
import ForgeCore

/// Apple Calendar — so ARIA knows your time, not just your HRV.
/// Like HealthKit, it's optional and on-device. ARIA only sees a summary:
/// busy windows and classified kinds (wedding, game, trip) — never titles,
/// attendees, or notes. Test-ready builds may write labeled demo events
/// onto a Forge-owned calendar. Never onto the user's personal calendars.
@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    static let writesToPersonalCalendars = FakeCalendarPack.writesToPersonalCalendars

    private let store = EKEventStore()

    @Published var isAuthorized = false
    @Published var authorizationErrorMessage: String?

    @Published var upcomingEvents: [EKEvent] = []
    @Published var busyWindowsToday: Int = 0
    @Published var classifiedKinds: [FakeCalendarEvent.Kind] = []

    var calendarTags: [String] {
        let morningBusy = upcomingEvents.contains {
            !$0.isAllDay && Calendar.current.component(.hour, from: $0.startDate) < 12
        }
        let eveningBusy = upcomingEvents.contains {
            !$0.isAllDay && Calendar.current.component(.hour, from: $0.startDate) >= 18
        }
        return FakeCalendarPack.ingestTags(
            busyToday: busyWindowsToday,
            morningBusy: morningBusy,
            eveningBusy: eveningBusy,
            allDayBusy: upcomingEvents.contains(where: \.isAllDay),
            kinds: classifiedKinds
        )
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

    /// Seed the Forge test calendar when allowed, then refresh busy windows.
    func ingestUpcomingIfAuthorized(days: Int = 14) async {
        let status = authorizationStatus()
        guard status == .authorized || status == .fullAccess else { return }
        isAuthorized = true
        await seedTestReadyCalendarIfNeeded()
        await fetchUpcoming(days: days)
    }

    @discardableResult
    func seedTestReadyCalendarIfNeeded() async -> Bool {
        guard FakeCalendarPack.shouldSeed(
            debugBuild: ForgeAuthPolicy.isDebugBuild,
            testReady: AriaService.shouldUseTestReadyDummy,
            calendarAuthorized: isAuthorized
                || authorizationStatus() == .authorized
                || authorizationStatus() == .fullAccess,
            isRunningTests: FakeCalendarPack.isRunningUnitTests
        ) else { return false }
        do {
            try replaceTestReadyEvents(
                FakeCalendarPack.generate(seed: AppStore.testReadySessionSeed)
            )
            return true
        } catch {
            print("Test-Ready calendar seed failed: \(error)")
            return false
        }
    }

    func fetchUpcoming(days: Int = 14) async {
        guard isAuthorized
            || authorizationStatus() == .authorized
            || authorizationStatus() == .fullAccess else { return }
        let calendars = store.calendars(for: .event)
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
        // Keep busy (and default/unsupported availability). Drop free + canceled.
        // All-day stays: a wedding Saturday still occupies the day.
        // `.none` is a normal personal event, not a missing invite — keep it.
        let filtered = events.filter { $0.status != .canceled && $0.availability != .free }
        let kinds = filtered.compactMap { event -> FakeCalendarEvent.Kind? in
            FakeCalendarPack.kind(fromNotes: event.notes)
                ?? FakeCalendarPack.kind(fromURL: event.url)
        }
        await MainActor.run {
            self.upcomingEvents = filtered.sorted { $0.startDate < $1.startDate }.prefix(40).map { $0 }
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? Date()
            self.busyWindowsToday = filtered.filter { $0.startDate < tomorrow && $0.endDate > today }.count
            self.classifiedKinds = Array(Set(kinds)).sorted()
        }
    }

    /// Writes only onto `FakeCalendarPack.calendarTitle`. Aborts rather than
    /// falling through to the user's default calendar.
    func replaceTestReadyEvents(_ pack: FakeCalendarPack) throws {
        let calendar = try forgeTestCalendar()
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let to = Calendar.current.date(byAdding: .day, value: 21, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        for event in store.events(matching: predicate)
            where FakeCalendarPack.isForgeTestEvent(notes: event.notes, url: event.url) {
            try store.remove(event, span: .thisEvent, commit: false)
        }
        for item in pack.events {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = item.title
            event.startDate = item.start
            event.endDate = item.end
            event.isAllDay = item.isAllDay
            event.notes = item.notesMarker
            event.url = item.eventURL
            event.availability = .busy
            if !item.placeName.isEmpty {
                event.location = item.placeName
                let pin = EKStructuredLocation(title: item.placeName)
                pin.geoLocation = CLLocation(latitude: item.latitude, longitude: item.longitude)
                event.structuredLocation = pin
            }
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    private func forgeTestCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == FakeCalendarPack.calendarTitle }) {
            return existing
        }
        guard let source = preferredSource() else {
            throw CalendarError.noWritableSource
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = FakeCalendarPack.calendarTitle
        calendar.source = source
        calendar.cgColor = CGColor(srgbRed: 0.15, green: 0.65, blue: 0.72, alpha: 1)
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    /// A source we can attach a *new* Forge calendar to. Never returns the
    /// user's default calendar itself — only its source, as a last resort.
    private func preferredSource() -> EKSource? {
        if let local = store.sources.first(where: { $0.sourceType == .local }) {
            return local
        }
        if let calDAV = store.sources.first(where: { $0.sourceType == .calDAV }) {
            return calDAV
        }
        return store.defaultCalendarForNewEvents?.source
    }

    enum CalendarError: Error, LocalizedError {
        case denied
        case noWritableSource
        var errorDescription: String? {
            switch self {
            case .denied:
                return "Calendar access was not granted. You can enable it in Settings → Privacy → Calendars."
            case .noWritableSource:
                return "Couldn't create a Forge test calendar on this iPhone."
            }
        }
    }
}
