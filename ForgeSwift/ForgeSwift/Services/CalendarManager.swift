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
    /// Why a Test-Ready year write failed. Nil when ingest is healthy.
    @Published var lastSeedError: String?

    @Published var upcomingEvents: [EKEvent] = []
    @Published var busyWindowsToday: Int = 0
    @Published var weekBusyWindows: Int = 0
    @Published var classifiedKinds: [FakeCalendarEvent.Kind] = []
    /// This week's Test-Ready kinds/busy, applied before EventKit finishes a year write.
    @Published var memoryWeekContext: FakeCalendarWeekContext?
    private var yearWriteTask: Task<Void, Never>?

    var displayedWeekContext: FakeCalendarWeekContext? {
        FakeCalendarPack.mergeWeekContexts(
            eventKit: eventKitWeekContext,
            memory: memoryWeekContext
        )
    }

    var calendarTags: [String] {
        displayedWeekContext?.ingestTags ?? []
    }

    private var eventKitWeekContext: FakeCalendarWeekContext? {
        guard !upcomingEvents.isEmpty
            || busyWindowsToday > 0
            || weekBusyWindows > 0
            || !classifiedKinds.isEmpty else { return nil }
        let cal = Calendar.current
        let window = FakeCalendarPack.weekWindow(containing: Date(), calendar: cal)
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? Date()
        let todayEvents = upcomingEvents.filter { $0.startDate < tomorrow && $0.endDate > today }
        let todayKinds = todayEvents.compactMap { event -> FakeCalendarEvent.Kind? in
            FakeCalendarPack.kind(fromNotes: event.notes)
                ?? FakeCalendarPack.kind(fromURL: event.url)
        }
        return FakeCalendarWeekContext(
            weekStart: window.start,
            weekEnd: window.end,
            todayBusy: busyWindowsToday,
            weekBusy: weekBusyWindows,
            morningBusy: todayEvents.contains {
                !$0.isAllDay && cal.component(.hour, from: $0.startDate) < 12
            },
            eveningBusy: todayEvents.contains {
                !$0.isAllDay && cal.component(.hour, from: $0.startDate) >= 18
            },
            allDayBusy: todayEvents.contains { $0.isAllDay },
            kinds: classifiedKinds,
            todayKinds: Array(Set(todayKinds)).sorted()
        )
    }

    static func describeAccess(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess:
            return "full access"
        case .writeOnly:
            return "write-only — Forge needs read access too"
        case .denied:
            return "denied. Enable Calendars in Settings → Privacy → Calendars"
        case .restricted:
            return "restricted by Screen Time or a configuration profile"
        case .notDetermined:
            return "not asked yet"
        @unknown default:
            return "unknown (\(status.rawValue))"
        }
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
                doing: "Calendar ingest",
                because: Self.describeAccess(status)
            )
            throw CalendarError.denied
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
                doing: "Calendar ingest",
                because: Self.describeAccess(authorizationStatus())
            )
            throw CalendarError.denied
        }
        authorizationErrorMessage = nil
    }

    /// Completion API on the main actor so iOS 26/27 EventKit presents the
    /// system sheet instead of aborting from a cooperative thread.
    private func requestFullAccessOnMain() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Seed the Forge test calendar when allowed, then refresh this week's tags.
    /// The year write runs in the background so Home is not waiting on EventKit.
    func ingestUpcomingIfAuthorized() async {
        let status = authorizationStatus()
        guard Self.hasReadAccess(status) else { return }
        isAuthorized = true
        lastSeedError = nil
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
        let pack = await Task.detached(priority: .utility) {
            FakeCalendarPack.generate(seed: seed)
        }.value
        memoryWeekContext = FakeCalendarPack.weekContext(from: pack)
        if seededSessionSeed == seed { return false }
        if yearWriteTask != nil { return true }
        yearWriteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.replaceTestReadyEvents(pack)
                self.seededSessionSeed = seed
                self.lastSeedError = nil
                await self.fetchThisWeek()
            } catch {
                self.lastSeedError = LifeIngestError.explain(
                    error,
                    doing: "Couldn't write the Forge test calendar"
                )
            }
            self.yearWriteTask = nil
        }
        return true
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
        guard isAuthorized || Self.hasReadAccess(authorizationStatus()) else { return }
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
        for (index, event) in store.events(matching: predicate).enumerated()
            where FakeCalendarPack.isForgeTestEvent(notes: event.notes, url: event.url) {
            do {
                try store.remove(event, span: .thisEvent, commit: false)
            } catch {
                throw CalendarError.writeFailed(
                    LifeIngestError.explain(error, doing: "Couldn't remove a previous Forge test event")
                )
            }
            if index % 32 == 31 {
                do {
                    try store.commit()
                } catch {
                    throw CalendarError.writeFailed(
                        LifeIngestError.explain(error, doing: "Couldn't commit Forge test-event cleanup")
                    )
                }
                await Task.yield()
            }
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
            do {
                try store.save(event, span: .thisEvent, commit: false)
            } catch {
                throw CalendarError.writeFailed(
                    LifeIngestError.explain(error, doing: "Couldn't save Forge test event \(index + 1)")
                )
            }
            if index % 24 == 23 {
                do {
                    try store.commit()
                } catch {
                    throw CalendarError.writeFailed(
                        LifeIngestError.explain(error, doing: "Couldn't commit Forge test calendar batch")
                    )
                }
                await Task.yield()
            }
        }
        do {
            try store.commit()
        } catch {
            throw CalendarError.writeFailed(
                LifeIngestError.explain(error, doing: "Couldn't finish the Forge test calendar")
            )
        }
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
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw CalendarError.writeFailed(
                LifeIngestError.explain(error, doing: "Couldn't create the Forge test calendar")
            )
        }
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
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .denied:
                return "Calendar access was not granted. You can enable it in Settings → Privacy → Calendars."
            case .noWritableSource:
                return "Couldn't create a Forge test calendar because this iPhone has no writable EventKit source (no local or CalDAV account)."
            case .writeFailed(let reason):
                return reason
            }
        }
    }
}
