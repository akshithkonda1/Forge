import Foundation

/// Deterministic Test-Ready calendar stream.
///
/// This exists to test ARIA, not to decorate Calendar.app. A real phone holds
/// a year of standups, 1:1s, dinners, a few trips, a wedding, games — then
/// ARIA only *thinks* about the week she's in. Seed-shaped like
/// `FakeHealthPack` so Device Hub can catch her fitting training around this
/// week's busy windows, or failing to.
///
/// Titles, places, and coordinates are written to EventKit so the calendar
/// looks like a life. They never become ARIA tags, prompts, or off-device
/// payload. ARIA is allowed classified kinds (`wedding`, `game`, `travel`)
/// and busy windows for **this calendar week** only.
///
/// EventKit writes land only on a Forge-owned calendar (`calendarTitle`).
/// Production builds never seed. Unit tests never seed.
public struct FakeCalendarEvent: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable, Comparable {
        case wedding
        case game
        case flight
        case travel
        case work
        case dinner
        case family
        case appointment
        case social

        public static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// Companion speech. A kind, never a guest list or a venue.
        public var spokenLabel: String {
            switch self {
            case .wedding: return "a wedding"
            case .game: return "a game"
            case .flight: return "a flight"
            case .travel: return "a trip"
            case .work: return "a work block"
            case .dinner: return "dinner out"
            case .family: return "family time"
            case .appointment: return "an appointment"
            case .social: return "a social"
            }
        }

        /// The kinds ARIA should actually change a session for.
        public var isHeadline: Bool {
            switch self {
            case .wedding, .game, .flight, .travel: return true
            default: return false
            }
        }
    }

    public var kind: Kind
    /// Written to EventKit only. Never copied into tags.
    public var title: String
    /// Venue / city label written to EventKit only. Never copied into tags.
    public var placeName: String
    /// Synthetic. Jittered around a fake anchor — not a real address.
    public var latitude: Double
    public var longitude: Double
    public var start: Date
    public var end: Date
    public var isAllDay: Bool

    public init(
        kind: Kind,
        title: String,
        placeName: String,
        latitude: Double,
        longitude: Double,
        start: Date,
        end: Date,
        isAllDay: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }

    public var notesMarker: String {
        FakeCalendarPack.notesPrefix + kind.rawValue
    }

    public var eventURL: URL {
        URL(string: FakeCalendarPack.eventURL + "#" + kind.rawValue)!
    }
}

/// One calendar week of classified ingest. The year lives in EventKit; ARIA
/// only receives this window — kinds + busy, never titles.
public struct FakeCalendarWeekContext: Sendable, Equatable {
    public var weekStart: Date
    public var weekEnd: Date
    public var todayBusy: Int
    public var weekBusy: Int
    public var morningBusy: Bool
    public var eveningBusy: Bool
    public var allDayBusy: Bool
    public var kinds: [FakeCalendarEvent.Kind]
    public var todayKinds: [FakeCalendarEvent.Kind]

    public init(
        weekStart: Date,
        weekEnd: Date,
        todayBusy: Int,
        weekBusy: Int,
        morningBusy: Bool,
        eveningBusy: Bool,
        allDayBusy: Bool,
        kinds: [FakeCalendarEvent.Kind],
        todayKinds: [FakeCalendarEvent.Kind]
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.todayBusy = todayBusy
        self.weekBusy = weekBusy
        self.morningBusy = morningBusy
        self.eveningBusy = eveningBusy
        self.allDayBusy = allDayBusy
        self.kinds = kinds
        self.todayKinds = todayKinds
    }

    public var ingestTags: [String] {
        FakeCalendarPack.ingestTags(
            busyToday: todayBusy,
            morningBusy: morningBusy,
            eveningBusy: eveningBusy,
            allDayBusy: allDayBusy,
            weekBusy: weekBusy,
            kinds: kinds
        )
    }

    public var spokenLine: String? {
        FakeCalendarPack.spokenLine(fromTags: ingestTags)
    }

    public var thinkingLine: String? {
        FakeCalendarPack.thinkingLine(fromTags: ingestTags)
    }

    public var contextualizeLine: String? {
        FakeCalendarPack.contextualizeLine(fromTags: ingestTags)
    }

    public var outcome: AriaCalendarOutcome {
        FakeCalendarPack.outcome(fromTags: ingestTags)
    }
}

/// What ARIA should *do* with this week's classified calendar.
/// Combinatory on purpose: a trip plus a wedding is not the same session as
/// a trip alone. Never carries titles, places, or attendees.
public struct AriaCalendarOutcome: Sendable, Equatable {
    public enum SessionShape: String, Sendable, Equatable {
        /// Travel / flight — the session has to be able to move.
        case movable
        /// Wedding / family — do not drop a hero session on top of it.
        case protectHero
        /// Game, appointment, or a single spoken-for window.
        case aroundWindow
        /// Morning is packed; the session lives later.
        case laterDay
        /// Dense week or both windows taken — short, and it has to fit.
        case shortFit
        /// Ordinary density. Read it; don't rewrite the session.
        case ordinary
    }

    public var shape: SessionShape
    public var keepLight: Bool
    public var shorten: Bool
    public var maxMinutes: Int
    public var thinkingLine: String?

    public init(
        shape: SessionShape,
        keepLight: Bool,
        shorten: Bool,
        maxMinutes: Int,
        thinkingLine: String?
    ) {
        self.shape = shape
        self.keepLight = keepLight
        self.shorten = shorten
        self.maxMinutes = maxMinutes
        self.thinkingLine = thinkingLine
    }

    public static let ordinary = AriaCalendarOutcome(
        shape: .ordinary,
        keepLight: false,
        shorten: false,
        maxMinutes: 55,
        thinkingLine: nil
    )

    public var changesSession: Bool {
        shape != .ordinary || keepLight || shorten
    }

    public var sessionFitLine: String? { thinkingLine }
}

public struct FakeCalendarPack: Sendable, Equatable {
    /// Isolated calendar EventKit writes may touch. Never the user's default.
    public static let calendarTitle = "Forge — Test Pack"
    public static let eventURL = "forge://test-ready/calendar"
    public static let notesPrefix = "forge-test-pack:"
    public static let writesToPersonalCalendars = false
    /// How far ahead EventKit is filled. ARIA still only ingest-tags one week.
    public static let horizonDays = 365

    public var events: [FakeCalendarEvent]
    public var generatedAt: Date
    public var seed: Int

    public init(events: [FakeCalendarEvent], generatedAt: Date, seed: Int) {
        self.events = events
        self.generatedAt = generatedAt
        self.seed = seed
    }

    /// Debug + test-ready + authorized. Never production. Never XCTest.
    /// Simulator *or* a physical phone is fine: writes stay on the Forge calendar.
    public static func shouldSeed(
        debugBuild: Bool,
        testReady: Bool,
        calendarAuthorized: Bool,
        isRunningTests: Bool
    ) -> Bool {
        debugBuild && testReady && calendarAuthorized && !isRunningTests
    }

    public static var isRunningUnitTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
    }

    public static func generate(
        now: Date = Date(),
        calendar: Calendar = .current,
        seed: Int = 0xCA1E17
    ) -> FakeCalendarPack {
        let rng = CalendarSplitMix64(seed: UInt64(truncatingIfNeeded: seed))
        var year = CalendarYearBuilder(now: now, calendar: calendar, rng: rng)
        year.build()
        return FakeCalendarPack(
            events: year.events.sorted { $0.start < $1.start },
            generatedAt: now,
            seed: seed
        )
    }

    // MARK: - Week window (ARIA's working memory)

    /// Start of the calendar week containing `now`, through the next 7 days.
    public static func weekWindow(
        containing now: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -delta, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 86_400)
        return (start, end)
    }

    /// EventKit this week plus an in-memory Test-Ready week, without waiting
    /// for a year of EventKit writes. Empty EventKit keeps the memory week;
    /// otherwise busy windows stay real and kinds are the union.
    public static func mergeWeekContexts(
        eventKit: FakeCalendarWeekContext?,
        memory: FakeCalendarWeekContext?
    ) -> FakeCalendarWeekContext? {
        switch (eventKit, memory) {
        case (nil, nil):
            return nil
        case (let eventKit?, nil):
            return eventKit
        case (nil, let memory?):
            return memory
        case (let eventKit?, let memory?):
            return FakeCalendarWeekContext(
                weekStart: eventKit.weekStart,
                weekEnd: eventKit.weekEnd,
                todayBusy: max(eventKit.todayBusy, memory.todayBusy),
                weekBusy: max(eventKit.weekBusy, memory.weekBusy),
                morningBusy: eventKit.morningBusy || memory.morningBusy,
                eveningBusy: eventKit.eveningBusy || memory.eveningBusy,
                allDayBusy: eventKit.allDayBusy || memory.allDayBusy,
                kinds: Array(Set(eventKit.kinds + memory.kinds)).sorted(),
                todayKinds: Array(Set(eventKit.todayKinds + memory.todayKinds)).sorted()
            )
        }
    }

    public static func overlapsWindow(_ event: FakeCalendarEvent, start: Date, end: Date) -> Bool {
        event.start < end && event.end > start
    }

    public static func events(
        in pack: FakeCalendarPack,
        overlapping start: Date,
        end: Date
    ) -> [FakeCalendarEvent] {
        pack.events.filter { overlapsWindow($0, start: start, end: end) }
    }

    public static func weekContext(
        from pack: FakeCalendarPack,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FakeCalendarWeekContext {
        let window = weekWindow(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let weekEvents = events(in: pack, overlapping: window.start, end: window.end)
        let todayEvents = pack.events.filter { overlapsDay($0, dayStart: today, calendar: calendar) }
        let morning = todayEvents.contains {
            !$0.isAllDay && calendar.component(.hour, from: $0.start) < 12
        }
        let evening = todayEvents.contains {
            !$0.isAllDay && calendar.component(.hour, from: $0.start) >= 18
        }
        let allDay = todayEvents.contains { $0.isAllDay }
        return FakeCalendarWeekContext(
            weekStart: window.start,
            weekEnd: window.end,
            todayBusy: todayEvents.count,
            weekBusy: weekEvents.count,
            morningBusy: morning,
            eveningBusy: evening,
            allDayBusy: allDay,
            kinds: Array(Set(weekEvents.map(\.kind))).sorted(),
            todayKinds: Array(Set(todayEvents.map(\.kind))).sorted()
        )
    }

    // MARK: - Ingest (kinds + busy windows, never titles or places)

    public static func kind(fromNotes notes: String?) -> FakeCalendarEvent.Kind? {
        guard let notes else { return nil }
        for kind in FakeCalendarEvent.Kind.allCases {
            if notes.contains(notesPrefix + kind.rawValue) { return kind }
        }
        return nil
    }

    public static func kind(fromURL url: URL?) -> FakeCalendarEvent.Kind? {
        guard let url else { return nil }
        guard url.absoluteString.hasPrefix(eventURL) else { return nil }
        if let fragment = url.fragment, let kind = FakeCalendarEvent.Kind(rawValue: fragment) {
            return kind
        }
        return nil
    }

    public static func isForgeTestEvent(notes: String?, url: URL?) -> Bool {
        if let url, url.absoluteString.hasPrefix(eventURL) { return true }
        if let notes, notes.contains(notesPrefix) { return true }
        return false
    }

    public static func isAllowedIngestTag(_ tag: String) -> Bool {
        if tag.hasPrefix("calendar:busy:") {
            return Int(tag.dropFirst("calendar:busy:".count)) != nil
        }
        if tag.hasPrefix("calendar:week:busy:") {
            return Int(tag.dropFirst("calendar:week:busy:".count)) != nil
        }
        if tag == "calendar:morning:busy"
            || tag == "calendar:evening:busy"
            || tag == "calendar:allday:busy" {
            return true
        }
        if tag.hasPrefix("calendar:kind:") {
            let raw = String(tag.dropFirst("calendar:kind:".count))
            return FakeCalendarEvent.Kind(rawValue: raw) != nil
        }
        if tag.hasPrefix("calendar:horizon:") {
            let rest = String(tag.dropFirst("calendar:horizon:".count))
            let parts = rest.split(separator: ":")
            guard parts.count == 2, Int(parts[1]) != nil else { return false }
            return FakeCalendarEvent.Kind(rawValue: String(parts[0])) != nil
        }
        return false
    }

    public static func sanitizeTags(_ tags: [String]) -> [String] {
        tags.filter(isAllowedIngestTag)
    }

    public static func ingestTags(
        busyToday: Int,
        morningBusy: Bool,
        eveningBusy: Bool,
        allDayBusy: Bool,
        weekBusy: Int = 0,
        kinds: [FakeCalendarEvent.Kind]
    ) -> [String] {
        var tags: [String] = [
            "calendar:busy:\(max(0, busyToday))",
            "calendar:week:busy:\(max(0, weekBusy))",
        ]
        if morningBusy { tags.append("calendar:morning:busy") }
        if eveningBusy { tags.append("calendar:evening:busy") }
        if allDayBusy { tags.append("calendar:allday:busy") }
        for kind in Set(kinds).sorted() {
            tags.append("calendar:kind:\(kind.rawValue)")
        }
        return sanitizeTags(tags)
    }

    /// Headline events in the next `withinDays` — kind and days-until only.
    public static func horizonTags(
        events: [FakeCalendarEvent],
        now: Date = Date(),
        calendar: Calendar = .current,
        withinDays: Int = 21
    ) -> [String] {
        let start = calendar.startOfDay(for: now)
        var nearest: [FakeCalendarEvent.Kind: Int] = [:]
        for event in events where event.kind.isHeadline {
            let day = calendar.startOfDay(for: event.start)
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            guard days >= 0, days <= withinDays else { continue }
            if let existing = nearest[event.kind], existing <= days { continue }
            nearest[event.kind] = days
        }
        return sanitizeTags(
            nearest.keys.sorted().map { "calendar:horizon:\($0.rawValue):\(nearest[$0] ?? 0)" }
        )
    }

    public static func ingestTags(
        from pack: FakeCalendarPack,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        sanitizeTags(
            weekContext(from: pack, now: now, calendar: calendar).ingestTags
                + horizonTags(events: pack.events, now: now, calendar: calendar)
        )
    }

    public static func kinds(fromTags tags: [String]) -> [FakeCalendarEvent.Kind] {
        tags.compactMap { tag in
            guard tag.hasPrefix("calendar:kind:") else { return nil }
            return FakeCalendarEvent.Kind(rawValue: String(tag.dropFirst("calendar:kind:".count)))
        }
        .sorted()
    }

    public static func busyToday(fromTags tags: [String]) -> Int {
        for tag in tags where tag.hasPrefix("calendar:busy:") && !tag.hasPrefix("calendar:week:busy:") {
            if let n = Int(tag.dropFirst("calendar:busy:".count)) { return n }
        }
        return 0
    }

    public static func weekBusy(fromTags tags: [String]) -> Int {
        for tag in tags where tag.hasPrefix("calendar:week:busy:") {
            if let n = Int(tag.dropFirst("calendar:week:busy:".count)) { return n }
        }
        return 0
    }

    /// Companion speech from this week's classified kinds. Headlines first —
    /// ARIA should change a session for a wedding or a trip, not for standup.
    /// Never interpolates a title or a place.
    public static func spokenLine(kinds: [FakeCalendarEvent.Kind], busyToday: Int, weekBusy: Int = 0) -> String? {
        let headlines = Array(Set(kinds.filter(\.isHeadline))).sorted()
        var parts: [String] = []
        if !headlines.isEmpty {
            parts.append("This week you've got \(list(headlines.map(\.spokenLabel))) on the calendar")
        } else if weekBusy > 0 {
            parts.append("This week has \(weekBusy) holds — ordinary density, not a blank week")
        }
        if busyToday > 0 {
            let noun = busyToday == 1 ? "busy window" : "busy windows"
            if parts.isEmpty {
                parts.append("You've got \(busyToday) \(noun) today — I'll train around them, not through them")
            } else {
                parts.append("today has \(busyToday) \(noun)")
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "; ") + ". I keep the titles on the phone."
    }

    public static func spokenLine(fromTags tags: [String]) -> String? {
        spokenLine(
            kinds: kinds(fromTags: tags),
            busyToday: busyToday(fromTags: tags),
            weekBusy: weekBusy(fromTags: tags)
        )
    }

    /// Combinatory coaching outcome for this week's classified ingest.
    /// Travel + a wedding is a different session than travel alone.
    public static func outcome(fromTags tags: [String]) -> AriaCalendarOutcome {
        let kinds = Set(kinds(fromTags: tags))
        let morning = tags.contains("calendar:morning:busy")
        let evening = tags.contains("calendar:evening:busy")
        let busy = busyToday(fromTags: tags)
        let week = weekBusy(fromTags: tags)
        let travel = kinds.contains(.travel) || kinds.contains(.flight)
        let wedding = kinds.contains(.wedding)
        let game = kinds.contains(.game)
        let family = kinds.contains(.family)
        let appointment = kinds.contains(.appointment)

        var shape: AriaCalendarOutcome.SessionShape = .ordinary
        var keepLight = false
        var shorten = false
        var maxMinutes = 55

        if travel {
            shape = .movable
            shorten = true
            maxMinutes = 35
            if wedding || evening || busy >= 2 {
                keepLight = true
                maxMinutes = 30
            }
        } else if wedding {
            shape = .protectHero
            keepLight = evening || busy >= 2
            shorten = keepLight
            maxMinutes = evening ? 30 : 40
        } else if family {
            shape = .protectHero
            shorten = evening || busy >= 2
            maxMinutes = shorten ? 35 : 40
        } else if morning && evening {
            shape = .shortFit
            keepLight = true
            shorten = true
            maxMinutes = 25
        } else if game {
            shape = .aroundWindow
            if evening || busy >= 2 {
                shorten = true
                maxMinutes = 30
            }
        } else if appointment {
            shape = morning ? .laterDay : .aroundWindow
            shorten = busy >= 2 || morning
            maxMinutes = 35
        } else if week >= 8 || busy >= 3 {
            shape = .shortFit
            shorten = true
            maxMinutes = busy >= 3 ? 30 : 35
            keepLight = busy >= 3 && evening
        } else if evening {
            shape = .aroundWindow
            shorten = true
            maxMinutes = 30
        } else if morning {
            shape = .laterDay
        }

        let thinking = thinkingSpeech(
            shape: shape,
            travel: travel,
            wedding: wedding,
            game: game,
            family: family,
            appointment: appointment,
            morning: morning,
            evening: evening,
            busy: busy,
            week: week
        )
        return AriaCalendarOutcome(
            shape: shape,
            keepLight: keepLight,
            shorten: shorten,
            maxMinutes: maxMinutes,
            thinkingLine: thinking
        )
    }

    /// How a coach should place today's session given this week's classified ingest.
    public static func sessionFitLine(fromTags tags: [String]) -> String? {
        outcome(fromTags: tags).sessionFitLine
    }

    /// The coaching thought: how this week's events change what ARIA does.
    public static func thinkingLine(fromTags tags: [String]) -> String? {
        outcome(fromTags: tags).thinkingLine
    }

    /// Read this week, then think about it. Still kinds + busy — never titles.
    public static func contextualizeLine(fromTags tags: [String]) -> String? {
        let read = spokenLine(fromTags: tags)
        let think = thinkingLine(fromTags: tags)
        switch (read, think) {
        case (nil, nil):
            return nil
        case (let read?, nil):
            return read
        case (nil, let think?):
            return think + " I keep the titles on the phone."
        case (let read?, let think?):
            let stem = read.replacingOccurrences(of: " I keep the titles on the phone.", with: "")
            return stem + " " + think + " I keep the titles on the phone."
        }
    }

    public static func overlapsDay(_ event: FakeCalendarEvent, dayStart: Date, calendar: Calendar) -> Bool {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return event.start < dayEnd && event.end > dayStart
    }

    public static func dayOffset(
        of event: FakeCalendarEvent,
        from now: Date,
        calendar: Calendar
    ) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: event.start)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    private static func list(_ labels: [String]) -> String {
        if labels.count == 1 { return labels[0] }
        if labels.count == 2 { return "\(labels[0]) and \(labels[1])" }
        return labels.dropLast().joined(separator: ", ") + ", and " + labels.last!
    }

    private static func thinkingSpeech(
        shape: AriaCalendarOutcome.SessionShape,
        travel: Bool,
        wedding: Bool,
        game: Bool,
        family: Bool,
        appointment: Bool,
        morning: Bool,
        evening: Bool,
        busy: Int,
        week: Int
    ) -> String? {
        switch shape {
        case .movable:
            if wedding {
                return "There's a trip and a wedding on the week — I'll keep the session able to move and skip the hero work."
            }
            if evening {
                return "There's travel on the week and evening's spoken for — short and able to move."
            }
            return "There's travel on the week — I'll keep the session able to move."
        case .protectHero:
            if wedding {
                return "There's a wedding on the week; I won't drop a hero session on top of it."
            }
            return "Family time's on the week. I won't drop a hero session on top of it."
        case .aroundWindow:
            if game {
                return "There's a game on the calendar — we'll train around that window, not through it."
            }
            if appointment {
                return "There's an appointment on the week — we'll keep the session from colliding with it."
            }
            if evening {
                return "Evening's spoken for — we'll keep this short so it actually happens."
            }
            return "We'll train around this week's windows, not through them."
        case .laterDay:
            if appointment {
                return "There's an appointment on the week — we'll keep the session from colliding with it."
            }
            return "Morning's packed. This can live later in the day."
        case .shortFit:
            if morning && evening {
                return "Morning and evening are both spoken for. This session has to be the thing that still fits."
            }
            if week >= 8 {
                return "This week is already carrying a lot. I'll place the session in the gaps."
            }
            if busy >= 3 {
                return "Today already has a few busy windows. This is the session that still fits."
            }
            return "I'll place the session in the gaps this week."
        case .ordinary:
            return nil
        }
    }
}

// MARK: - Year builder

/// A year of a phone. Story events (wedding, game, trip) are scattered across
/// the horizon; work texture fills the weeks. ARIA only ingest-tags the week
/// containing `now`.
private struct CalendarYearBuilder {
    let now: Date
    let calendar: Calendar
    var rng: CalendarSplitMix64
    var events: [FakeCalendarEvent] = []
    var busy: [(Date, Date)] = []
    var travelOffsets: Set<Int> = []

    var weekStartOffset: Int {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        return -delta
    }

    var weekEndOffset: Int { weekStartOffset + 6 }

    mutating func build() {
        placeTrips()
        placeWeddings()
        placeGames()
        placeFamily()
        fillWorkdays()
        placeDinners()
        placeAppointments()
        placeSocial()
        placeTodayRemainder()
        ensureCurrentWeekReadable()
    }

    // MARK: Story — year scatter

    mutating func placeTrips() {
        let count = rng.int(4...6)
        var candidates = Array(3...350).filter {
            let w = weekday($0)
            return w == 5 || w == 6 || w == 7
        }
        shuffle(&candidates)
        var placedStarts: [Int] = []
        for startOffset in candidates {
            if placedStarts.count >= count { break }
            if placedStarts.contains(where: { abs($0 - startOffset) < 18 }) { continue }
            let dest = PlaceBank.destination(&rng)
            let days = rng.int(2...4)
            travelOffsets.formUnion(startOffset..<(startOffset + days))
            placedStarts.append(startOffset)
            let start = dayStart(startOffset)
            let end = calendar.date(byAdding: .day, value: days, to: start)
                ?? start.addingTimeInterval(Double(days) * 86_400)
            add(
                FakeCalendarEvent(
                    kind: .travel,
                    title: dest.tripTitle,
                    placeName: dest.stay,
                    latitude: jitter(spread: 2_400),
                    longitude: jitter(PlaceBank.anchorLongitude, spread: 2_400),
                    start: start,
                    end: end,
                    isAllDay: true
                ),
                force: true
            )
            let eveningFlight = rng.int(1...100) <= 35
            let hour = eveningFlight ? rng.int(16...19) : rng.int(5...10)
            addTimed(
                .flight,
                title: "Flight to \(dest.city)",
                place: dest.airport,
                offset: startOffset,
                hour: hour,
                minute: rng.int(5...50),
                minutes: rng.int(75...260),
                far: true,
                force: true
            )
        }
    }

    mutating func placeWeddings() {
        let count = rng.int(3...5)
        var weekends = (1...360).filter { isWeekend($0) && !travelOffsets.contains($0) }
        if weekends.isEmpty { weekends = (1...360).filter(isWeekend) }
        shuffle(&weekends)
        var placed: [Int] = []
        for offset in weekends {
            if placed.count >= count { break }
            if placed.contains(where: { abs($0 - offset) < 21 }) { continue }
            placed.append(offset)
            addTimed(
                .wedding,
                title: "\(PlaceBank.pick(PlaceBank.couples, &rng))'s wedding",
                place: PlaceBank.pick(PlaceBank.weddingVenues, &rng),
                offset: offset,
                hour: rng.int(12...16),
                minute: rng.int(0...40),
                minutes: rng.int(150...300),
                force: true
            )
        }
    }

    mutating func placeGames() {
        var candidates = (1...360).filter { !travelOffsets.contains($0) && !hasKind(.wedding, on: $0) }
        shuffle(&candidates)
        let count = rng.int(18...26)
        for offset in candidates.prefix(count) {
            let month = calendar.component(.month, from: dayStart(offset))
            let shoulder = month == 3 || month == 4 || month == 5 || month == 9 || month == 10 || month == 11
            if !shoulder, rng.int(1...100) <= 40 { continue }
            let evening = !isWeekend(offset) || rng.int(1...100) <= 45
            addTimed(
                .game,
                title: PlaceBank.pick(PlaceBank.games, &rng),
                place: PlaceBank.pick(PlaceBank.gameVenues, &rng),
                offset: offset,
                hour: evening ? rng.int(17...20) : rng.int(10...14),
                minute: rng.int(0...40),
                minutes: rng.int(90...150),
                force: true
            )
        }
    }

    mutating func placeFamily() {
        var days = (1...360).filter { isWeekend($0) && !travelOffsets.contains($0) && !hasKind(.wedding, on: $0) }
        shuffle(&days)
        let count = rng.int(8...12)
        var placed: [Int] = []
        for offset in days {
            if placed.count >= count { break }
            if placed.contains(where: { abs($0 - offset) < 21 }) { continue }
            placed.append(offset)
            let brunch = rng.int(1...100) <= 60
            addTimed(
                .family,
                title: PlaceBank.pick(PlaceBank.familyTitles, &rng),
                place: PlaceBank.pick(PlaceBank.familyPlaces, &rng),
                offset: offset,
                hour: brunch ? rng.int(9...12) : rng.int(16...18),
                minute: rng.int(0...30),
                minutes: rng.int(90...180)
            )
        }
    }

    // MARK: Ordinary density

    mutating func fillWorkdays() {
        for offset in weekStartOffset...FakeCalendarPack.horizonDays {
            if isWeekend(offset) || travelOffsets.contains(offset) { continue }
            let hourNow = calendar.component(.hour, from: now)
            if offset != 0 || hourNow < 10, rng.int(1...100) <= 42 {
                addTimed(
                    .work,
                    title: PlaceBank.pick(PlaceBank.standups, &rng),
                    place: PlaceBank.pick(PlaceBank.virtualPlaces, &rng),
                    offset: offset,
                    hour: 9,
                    minute: rng.int(0...20),
                    minutes: rng.int(15...30)
                )
            }
            if rng.int(1...100) <= 28 {
                addTimed(
                    .work,
                    title: PlaceBank.pick(PlaceBank.meetings, &rng),
                    place: PlaceBank.pick(PlaceBank.workPlaces, &rng),
                    offset: offset,
                    hour: rng.int(10...12),
                    minute: rng.int(0...40),
                    minutes: rng.int(25...90)
                )
            }
            if rng.int(1...100) <= 16 {
                addTimed(
                    .work,
                    title: "Lunch",
                    place: PlaceBank.pick(PlaceBank.restaurants, &rng),
                    offset: offset,
                    hour: rng.int(11...13),
                    minute: rng.int(0...25),
                    minutes: rng.int(30...60)
                )
            }
            if rng.int(1...100) <= 24 {
                if offset == 0 {
                    let lower = max(hourNow + 1, 13)
                    if lower <= 16 {
                        addTimed(
                            .work,
                            title: PlaceBank.pick(PlaceBank.afternoons, &rng),
                            place: PlaceBank.pick(PlaceBank.workPlaces, &rng),
                            offset: offset,
                            hour: rng.int(lower...16),
                            minute: rng.int(0...40),
                            minutes: rng.int(30...90)
                        )
                    }
                } else {
                    addTimed(
                        .work,
                        title: PlaceBank.pick(PlaceBank.afternoons, &rng),
                        place: PlaceBank.pick(PlaceBank.workPlaces, &rng),
                        offset: offset,
                        hour: rng.int(13...16),
                        minute: rng.int(0...40),
                        minutes: rng.int(30...90)
                    )
                }
            }
        }
    }

    mutating func placeDinners() {
        var week = weekStartOffset
        while week <= FakeCalendarPack.horizonDays {
            var evenings = Array(week..<(week + 7)).filter {
                $0 >= weekStartOffset
                    && $0 <= FakeCalendarPack.horizonDays
                    && !travelOffsets.contains($0)
                    && !hasKind(.wedding, on: $0)
            }
            shuffle(&evenings)
            let count = rng.int(1...3)
            for offset in evenings.prefix(count) {
                if hasKind(.game, on: offset), rng.int(1...100) <= 70 { continue }
                let restaurant = PlaceBank.pick(PlaceBank.restaurants, &rng)
                addTimed(
                    .dinner,
                    title: "Dinner at \(restaurant)",
                    place: restaurant,
                    offset: offset,
                    hour: rng.int(18...21),
                    minute: rng.int(0...40),
                    minutes: rng.int(70...140)
                )
            }
            week += 7
        }
    }

    mutating func placeAppointments() {
        var days = (1...350).filter { !isWeekend($0) && !travelOffsets.contains($0) }
        shuffle(&days)
        let count = rng.int(10...14)
        var placed: [Int] = []
        for offset in days {
            if placed.count >= count { break }
            if placed.contains(where: { abs($0 - offset) < 14 }) { continue }
            placed.append(offset)
            let pick = PlaceBank.appointments[rng.int(0...(PlaceBank.appointments.count - 1))]
            addTimed(
                .appointment,
                title: pick.title,
                place: pick.place,
                offset: offset,
                hour: rng.int(10...16),
                minute: rng.int(0...30),
                minutes: pick.minutes
            )
        }
    }

    mutating func placeSocial() {
        var birthdayDays = (1...360).filter { !travelOffsets.contains($0) && !hasKind(.wedding, on: $0) }
        shuffle(&birthdayDays)
        for offset in birthdayDays.prefix(rng.int(6...10)) {
            if rng.int(1...100) > 55 { continue }
            let start = dayStart(offset)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            add(
                FakeCalendarEvent(
                    kind: .social,
                    title: PlaceBank.pick(PlaceBank.birthdays, &rng),
                    placeName: "",
                    latitude: jitter(spread: 80),
                    longitude: jitter(PlaceBank.anchorLongitude, spread: 80),
                    start: start,
                    end: end,
                    isAllDay: true
                )
            )
        }
        var drinkDays = (1...360).filter {
            !travelOffsets.contains($0) && !hasKind(.wedding, on: $0) && !hasKind(.game, on: $0)
        }
        shuffle(&drinkDays)
        for offset in drinkDays.prefix(rng.int(8...14)) {
            if rng.int(1...100) > 50 { continue }
            addTimed(
                .social,
                title: PlaceBank.pick(PlaceBank.drinks, &rng),
                place: PlaceBank.pick(PlaceBank.bars, &rng),
                offset: offset,
                hour: rng.int(18...21),
                minute: rng.int(0...40),
                minutes: rng.int(60...150)
            )
        }
    }

    /// If "now" is still a working afternoon, leave something later today so
    /// `calendar:busy` is a live signal, not only a future-week story.
    mutating func placeTodayRemainder() {
        if travelOffsets.contains(0) { return }
        let hour = calendar.component(.hour, from: now)
        if hour < 17, !isWeekend(0) {
            addTimed(
                .work,
                title: PlaceBank.pick(PlaceBank.afternoons, &rng),
                place: PlaceBank.pick(PlaceBank.workPlaces, &rng),
                offset: 0,
                hour: min(16, max(hour + 1, 14)),
                minute: rng.int(0...25),
                minutes: rng.int(30...60)
            )
        }
        if hour < 20, rng.int(1...100) <= 40, !hasKind(.dinner, on: 0), !hasKind(.game, on: 0) {
            let restaurant = PlaceBank.pick(PlaceBank.restaurants, &rng)
            addTimed(
                .dinner,
                title: "Dinner at \(restaurant)",
                place: restaurant,
                offset: 0,
                hour: max(18, hour + 2),
                minute: rng.int(0...30),
                minutes: rng.int(70...120)
            )
        }
    }

    /// Device Hub launches into *this* week. Guarantee ARIA has something to
    /// read and think about without dumping next month's wedding into tags.
    /// Seed picks *which* headline so different launches produce different
    /// coaching outcomes, not the same game every time.
    mutating func ensureCurrentWeekReadable() {
        let hasHeadline = (weekStartOffset...weekEndOffset).contains { offset in
            FakeCalendarEvent.Kind.allCases.contains { kind in
                kind.isHeadline && hasKind(kind, on: offset)
            }
        }
        if !hasHeadline {
            var days = Array(weekStartOffset...weekEndOffset).filter {
                $0 >= 0 && !travelOffsets.contains($0) && !hasKind(.wedding, on: $0)
            }
            if days.isEmpty {
                days = Array(weekStartOffset...weekEndOffset).filter { $0 >= 0 }
            }
            shuffle(&days)
            switch rng.int(0...3) {
            case 0:
                if let offset = days.first(where: { isWeekend($0) }) ?? days.last ?? days.first {
                    addTimed(
                        .family,
                        title: PlaceBank.pick(PlaceBank.familyTitles, &rng),
                        place: PlaceBank.pick(PlaceBank.familyPlaces, &rng),
                        offset: offset,
                        hour: rng.int(10...16),
                        minute: rng.int(0...25),
                        minutes: rng.int(90...160),
                        force: true
                    )
                }
            case 1:
                if let offset = days.first(where: { !isWeekend($0) }) ?? days.first {
                    let pick = PlaceBank.appointments[rng.int(0...(PlaceBank.appointments.count - 1))]
                    addTimed(
                        .appointment,
                        title: pick.title,
                        place: pick.place,
                        offset: offset,
                        hour: rng.int(10...16),
                        minute: rng.int(0...20),
                        minutes: pick.minutes,
                        force: true
                    )
                }
            default:
                if let offset = days.last ?? days.first {
                    let evening = !isWeekend(offset)
                    addTimed(
                        .game,
                        title: PlaceBank.pick(PlaceBank.games, &rng),
                        place: PlaceBank.pick(PlaceBank.gameVenues, &rng),
                        offset: offset,
                        hour: evening ? rng.int(17...20) : rng.int(10...14),
                        minute: rng.int(0...25),
                        minutes: rng.int(90...130),
                        force: true
                    )
                }
            }
        }
        let workThisWeek = events.filter {
            $0.kind == .work && (weekStartOffset...weekEndOffset).contains(dayOffset($0.start))
        }
        if workThisWeek.count < 2 {
            for offset in weekStartOffset...weekEndOffset {
                if isWeekend(offset) || travelOffsets.contains(offset) { continue }
                if offset < 0 { continue }
                if hasKind(.work, on: offset) { continue }
                addTimed(
                    .work,
                    title: PlaceBank.pick(PlaceBank.standups, &rng),
                    place: PlaceBank.pick(PlaceBank.virtualPlaces, &rng),
                    offset: offset,
                    hour: 9,
                    minute: rng.int(0...15),
                    minutes: rng.int(15...30),
                    force: true
                )
                break
            }
        }
    }

    // MARK: Placement

    mutating func addTimed(
        _ kind: FakeCalendarEvent.Kind,
        title: String,
        place: String,
        offset: Int,
        hour: Int,
        minute: Int,
        minutes: Int,
        far: Bool = false,
        force: Bool = false
    ) {
        let start = stamp(offset, hour: hour, minute: minute)
        let end = calendar.date(byAdding: .minute, value: minutes, to: start)
            ?? start.addingTimeInterval(TimeInterval(minutes * 60))
        let inCurrentWeek = offset >= weekStartOffset && offset <= weekEndOffset
        if start <= now, !force {
            if inCurrentWeek {
                add(
                    FakeCalendarEvent(
                        kind: kind,
                        title: title,
                        placeName: place,
                        latitude: jitter(spread: far ? 2_400 : 260),
                        longitude: jitter(PlaceBank.anchorLongitude, spread: far ? 2_400 : 260),
                        start: start,
                        end: end,
                        isAllDay: false
                    ),
                    force: true
                )
            }
            return
        }
        let spread = far ? 2_400 : 260
        add(
            FakeCalendarEvent(
                kind: kind,
                title: title,
                placeName: place,
                latitude: jitter(spread: spread),
                longitude: jitter(PlaceBank.anchorLongitude, spread: spread),
                start: start,
                end: end,
                isAllDay: false
            ),
            force: force
        )
    }

    mutating func add(_ event: FakeCalendarEvent, force: Bool = false) {
        if !force, !event.isAllDay, collides(event.start, event.end) { return }
        events.append(event)
        if !event.isAllDay {
            busy.append((event.start, event.end))
        }
    }

    func collides(_ start: Date, _ end: Date) -> Bool {
        busy.contains { max($0.0, start) < min($0.1, end) }
    }

    func hasKind(_ kind: FakeCalendarEvent.Kind, on offset: Int) -> Bool {
        events.contains { $0.kind == kind && dayOffset($0.start) == offset }
    }

    func dayStart(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    func stamp(_ offset: Int, hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart(offset))
            ?? dayStart(offset)
    }

    func weekday(_ offset: Int) -> Int {
        calendar.component(.weekday, from: dayStart(offset))
    }

    func isWeekend(_ offset: Int) -> Bool {
        let w = weekday(offset)
        return w == 1 || w == 7
    }

    func dayOffset(_ date: Date) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    mutating func shuffle(_ items: inout [Int]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            let j = rng.int(0...i)
            items.swapAt(i, j)
        }
    }

    mutating func jitter(_ base: Double = PlaceBank.anchorLatitude, spread: Int) -> Double {
        base + Double(rng.int(-spread...spread)) / 10_000.0
    }
}

// MARK: - Synthetic places

/// Invented names and coordinates. Must never look learned from the device.
private enum PlaceBank {
    static let anchorLatitude = 37.7840
    static let anchorLongitude = -122.4070

    static let weddingVenues = [
        "Harbor Hall", "The Greenhouse", "Riverside Pavilion", "St. Anne's", "Hilltop Barn",
    ]
    static let gameVenues = [
        "City Arena", "Westside Field", "Riverside Court", "Harbor Park", "The Yard",
    ]
    static let games = [
        "City vs Harbor", "Sharks at home", "Alumni scrimmage", "League night", "Pickup at the park",
    ]
    static let restaurants = [
        "Osteria", "Nopalito", "Kin Khao", "Corner Table", "The Alibi", "Blue Bottle",
    ]
    static let workPlaces = [
        "HQ — 4th floor", "Conf 3A", "Studio", "Client site", "Zoom", "Google Meet",
    ]
    static let virtualPlaces = ["Zoom", "Google Meet", "Teams"]
    static let standups = ["Standup", "Daily standup", "Morning standup"]
    static let meetings = [
        "1:1", "Design review", "Sprint planning", "Hiring loop", "Sync", "Staff meeting",
    ]
    static let afternoons = [
        "Focus time", "1:1", "Project sync", "Interview", "Workshop",
    ]
    static let familyPlaces = [
        "Family's place", "Parents' house", "Sunday at home", "Cousin's place",
    ]
    static let familyTitles = [
        "Family brunch", "Dinner with family", "Kids' afternoon", "Sunday roast",
    ]
    static let couples = [
        "Jordan & Alex", "Casey & Morgan", "Avery & Quinn", "Riley & Drew",
    ]
    static let birthdays = [
        "Dad's birthday", "Priya's birthday", "Nia's birthday",
    ]
    static let drinks = [
        "Drinks", "Catch-up drinks", "After-work drinks",
    ]
    static let bars = ["The Alibi", "Third Rail", "Lucky's"]

    struct Appointment {
        var title: String
        var place: String
        var minutes: Int
    }

    static let appointments: [Appointment] = [
        Appointment(title: "Dentist", place: "Oak Dental", minutes: 50),
        Appointment(title: "Haircut", place: "Barber on Pine", minutes: 45),
        Appointment(title: "PT", place: "Motion Clinic", minutes: 55),
        Appointment(title: "Annual physical", place: "City Medical", minutes: 40),
    ]

    struct Destination {
        var city: String
        var tripTitle: String
        var stay: String
        var airport: String
    }

    static let destinations: [Destination] = [
        Destination(city: "Denver", tripTitle: "Weekend in the mountains", stay: "Denver lodge", airport: "SFO → DEN"),
        Destination(city: "Seattle", tripTitle: "Coast trip", stay: "Seattle inn", airport: "OAK → SEA"),
        Destination(city: "Austin", tripTitle: "Lake cabin", stay: "Austin cabin", airport: "SFO → AUS"),
        Destination(city: "Chicago", tripTitle: "City weekend", stay: "Chicago hotel", airport: "SFO → ORD"),
        Destination(city: "Portland", tripTitle: "River weekend", stay: "Portland loft", airport: "SFO → PDX"),
    ]

    static func pick(_ items: [String], _ rng: inout CalendarSplitMix64) -> String {
        items[rng.int(0...(items.count - 1))]
    }

    static func destination(_ rng: inout CalendarSplitMix64) -> Destination {
        destinations[rng.int(0...(destinations.count - 1))]
    }
}

// MARK: - SplitMix64 (file-private; same generator as FakeHealthPack)

private struct CalendarSplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let lo = range.lowerBound
        let hi = range.upperBound
        if hi <= lo { return lo }
        let span = UInt64(hi - lo) + 1
        return lo + Int(next() % span)
    }
}
