import Foundation
import EventKit
import CoreLocation
import Combine
import ForgeCore

/// Apple Calendar — so ARIA knows your time, not just your HRV.
/// Like HealthKit, it's optional and on-device. ARIA only sees a summary
/// of **this calendar week**: busy windows and classified kinds (wedding,
/// game, trip) — never titles, attendees, or notes. Test-ready builds may
/// write a full year of labeled demo events onto a Forge-owned calendar.
/// Never onto the user's personal calendars. Ingest still tags one week.
@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    static let writesToPersonalCalendars = FakeCalendarPack.writesToPersonalCalendars

    private let store = EKEventStore()
    /// Avoid rewriting hundreds of EventKit rows on every readiness refresh
    /// within the same process. Seed is per-launch like the health pack.
    private var seededSessionSeed: Int?

    @Published var isAuthorized = false
    @Published var authorizationErrorMessage: String?

    @Published var upcomingEvents: [EKEvent] = []
    @Published var busyWindowsToday: Int = 0
    @Published var weekBusyWindows: Int = 0
    @Published var classifiedKinds: [FakeCalendarEvent.Kind] = []

    var calendarTags: [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? Date()
        let todayEvents = upcomingEvents.filter { $0.startDate < tomorrow && $0.endDate > today }
        let morningBusy = todayEvents.contains {
            !$0.isAllDay && cal.component(.hour, from: $0.startDate) < 12
        }
        let eveningBusy = todayEvents.contains {
            !$0.isAllDay && cal.component(.hour, from: $0.startDate) >= 18
        }
        return FakeCalendarPack.ingestTags(
            busyToday: busyWindowsToday,
            morningBusy: morningBusy,
            eveningBusy: eveningBusy,
            allDayBusy: todayEvents.contains { $0.isAllDay },
            weekBusy: weekBusyWindows,
            kinds: classifiedKinds
        )
    }

    /// True when EventKit reports full calendar read access.
    /// `.authorized` was renamed to `.fullAccess` and is deprecated on iOS 17+.
    static func hasReadAccess(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }

    func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            isAuthorized = true
            return
        case .denied, .restricted:
            isAuthorized = false
            throw CalendarError.denied
        case .writeOnly, .notDetermined:
            break
        @unknown default:
            break
        }
        let granted = try await store.requestFullAccessToEvents()
        isAuthorized = granted
        if !granted {
            throw CalendarError.denied
        }
    }

    /// Seed the Forge test calendar when allowed, then refresh this week's tags.
    func ingestUpcomingIfAuthorized() async {
        let status = authorizationStatus()
        guard Self.hasReadAccess(status) else { return }
        isAuthorized = true
        await seedTestReadyCalendarIfNeeded()
        await fetchThisWeek()
    }

    @discardableResult
    func seedTestReadyCalendarIfNeeded() async -> Bool {
        guard FakeCalendarPack.shouldSeed(
            debugBuild: ForgeAuthPolicy.isDebugBuild,
            testReady: AriaService.shouldUseTestReadyDummy,
            calendarAuthorized: isAuthorized
                || Self.hasReadAccess(authorizationStatus()),
            isRunningTests: FakeCalendarPack.isRunningUnitTests
        ) else { return false }
        let seed = AppStore.testReadySessionSeed
        if seededSessionSeed == seed { return false }
        do {
            try await replaceTestReadyEvents(
                FakeCalendarPack.generate(seed: seed)
            )
            seededSessionSeed = seed
            return true
        } catch {
            print("Test-Ready calendar seed failed: \(error)")
            return false
        }
    }

    func fetchUpcoming(days: Int = 7) async {
        await fetchRange(from: Date(), days: days)
    }

    func fetchThisWeek() async {
        let cal = Calendar.current
        let window = FakeCalendarPack.weekWindow(containing: Date(), calendar: cal)
        await fetchRange(start: window.start, end: window.end)
    }

    private func fetchRange(from start: Date, days: Int) async {
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        await fetchRange(start: start, end: end)
    }

    private func fetchRange(start: Date, end: Date) async {
        guard isAuthorized
            || Self.hasReadAccess(authorizationStatus()) else { return }
        let calendars = store.calendars(for: .event)
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
        upcomingEvents = filtered.sorted { $0.startDate < $1.startDate }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? Date()
        busyWindowsToday = filtered.filter { $0.startDate < tomorrow && $0.endDate > today }.count
        weekBusyWindows = filtered.count
        classifiedKinds = Array(Set(kinds)).sorted()
    }

    /// Writes only onto `FakeCalendarPack.calendarTitle`. Aborts rather than
    /// falling through to the user's default calendar.
    func replaceTestReadyEvents(_ pack: FakeCalendarPack) async throws {
        let calendar = try forgeTestCalendar()
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let to = Calendar.current.date(
            byAdding: .day,
            value: FakeCalendarPack.horizonDays + 14,
            to: now
        ) ?? now
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        for event in store.events(matching: predicate)
            where FakeCalendarPack.isForgeTestEvent(notes: event.notes, url: event.url) {
            try store.remove(event, span: .thisEvent, commit: false)
        }
        for (index, item) in pack.events.enumerated() {
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
            if index % 24 == 23 {
                await Task.yield()
            }
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
