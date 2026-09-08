import Foundation

/// Deterministic Test-Ready calendar stream.
///
/// This exists to test ARIA, not to decorate Calendar.app. A real phone is
/// dense: standups, 1:1s, a dentist, dinner, then a weekend that actually
/// occupies the day. Seed-shaped like `FakeHealthPack` — not a sticker week
/// of Thursday 7pm forever — so Device Hub can catch ARIA fitting training
/// around busy windows, or failing to.
///
/// Titles, places, and coordinates are written to EventKit so the calendar
/// looks like a life. They never become ARIA tags, prompts, or off-device
/// payload. ARIA is allowed classified kinds (`wedding`, `game`, `travel`)
/// and busy windows only.
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

public struct FakeCalendarPack: Sendable, Equatable {
    /// Isolated calendar EventKit writes may touch. Never the user's default.
    public static let calendarTitle = "Forge — Test Pack"
    public static let eventURL = "forge://test-ready/calendar"
    public static let notesPrefix = "forge-test-pack:"
    public static let writesToPersonalCalendars = false

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
        var rng = CalendarSplitMix64(seed: UInt64(truncatingIfNeeded: seed))
        var week = CalendarWeekBuilder(now: now, calendar: calendar, rng: rng)
        week.build()
        return FakeCalendarPack(
            events: week.events.sorted { $0.start < $1.start },
            generatedAt: now,
            seed: seed
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
        if tag == "calendar:morning:busy"
            || tag == "calendar:evening:busy"
            || tag == "calendar:allday:busy" {
            return true
        }
        if tag.hasPrefix("calendar:kind:") {
            let raw = String(tag.dropFirst("calendar:kind:".count))
            return FakeCalendarEvent.Kind(rawValue: raw) != nil
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
        kinds: [FakeCalendarEvent.Kind]
    ) -> [String] {
        var tags: [String] = ["calendar:busy:\(max(0, busyToday))"]
        if morningBusy { tags.append("calendar:morning:busy") }
        if eveningBusy { tags.append("calendar:evening:busy") }
        if allDayBusy { tags.append("calendar:allday:busy") }
        for kind in Set(kinds).sorted() {
            tags.append("calendar:kind:\(kind.rawValue)")
        }
        return sanitizeTags(tags)
    }

    public static func ingestTags(
        from pack: FakeCalendarPack,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        let today = calendar.startOfDay(for: now)
        let overlapping = pack.events.filter { overlapsDay($0, dayStart: today, calendar: calendar) }
        let morning = overlapping.contains {
            !$0.isAllDay && calendar.component(.hour, from: $0.start) < 12
        }
        let evening = overlapping.contains {
            !$0.isAllDay && calendar.component(.hour, from: $0.start) >= 18
        }
        return ingestTags(
            busyToday: overlapping.count,
            morningBusy: morning,
            eveningBusy: evening,
            allDayBusy: overlapping.contains(\.isAllDay),
            kinds: pack.events.map(\.kind)
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
        for tag in tags where tag.hasPrefix("calendar:busy:") {
            if let n = Int(tag.dropFirst("calendar:busy:".count)) { return n }
        }
        return 0
    }

    /// Companion speech from classified kinds. Headlines only — ARIA should
    /// change a session for a wedding or a trip, not for standup. Never
    /// interpolates a title or a place.
    public static func spokenLine(kinds: [FakeCalendarEvent.Kind], busyToday: Int) -> String? {
        let headlines = Array(Set(kinds.filter(\.isHeadline))).sorted()
        var parts: [String] = []
        if !headlines.isEmpty {
            parts.append("This week you've got \(list(headlines.map(\.spokenLabel))) on the calendar")
        }
        if busyToday > 0 {
            let noun = busyToday == 1 ? "busy window" : "busy windows"
            if headlines.isEmpty {
                parts.append("You've got \(busyToday) \(noun) today — I'll train around them, not through them")
            } else {
                parts.append("today has \(busyToday) \(noun)")
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "; ") + ". I keep the titles on the phone."
    }

    public static func spokenLine(fromTags tags: [String]) -> String? {
        spokenLine(kinds: kinds(fromTags: tags), busyToday: busyToday(fromTags: tags))
    }

    /// How a coach should place today's session given classified ingest.
    public static func sessionFitLine(fromTags tags: [String]) -> String? {
        let kinds = Set(kinds(fromTags: tags))
        let morning = tags.contains("calendar:morning:busy")
        let evening = tags.contains("calendar:evening:busy")
        let busy = busyToday(fromTags: tags)
        if kinds.contains(.travel) || kinds.contains(.flight) {
            return "There's travel on the week — I'll keep the session able to move."
        }
        if kinds.contains(.wedding) {
            return "There's a wedding on the week; I won't drop a hero session on top of it."
        }
        if kinds.contains(.game), evening || busy >= 2 {
            return "There's a game on the calendar — we'll train around that window, not through it."
        }
        if morning, evening {
            return "Morning and evening are both spoken for. This session has to be the thing that still fits."
        }
        if morning {
            return "Morning's packed. This can live later in the day."
        }
        if evening {
            return "Evening's spoken for — we'll keep this short so it actually happens."
        }
        if busy >= 3 {
            return "Today already has a few busy windows. This is the session that still fits."
        }
        return nil
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
}

// MARK: - Week builder

/// Two weeks of a phone. Story events (wedding, game, trip) are guaranteed;
/// the rest is the ordinary density ARIA has to coach around.
private struct CalendarWeekBuilder {
    let now: Date
    let calendar: Calendar
    var rng: CalendarSplitMix64
    var events: [FakeCalendarEvent] = []
    var busy: [(Date, Date)] = []
    var travelOffsets: Set<Int> = []

    mutating func build() {
        placeTravel()
        placeWedding()
        placeGame()
        placeFamily()
        fillWorkdays()
        placeDinners()
        placeAppointments()
        placeSocial()
        placeTodayRemainder()
    }

    // MARK: Story

    mutating func placeTravel() {
        let dest = PlaceBank.destination(&rng)
            var candidates = (3...10).filter {
                let w = weekday($0)
                return w == 5 || w == 6 || w == 7
            }
        if candidates.isEmpty { candidates = Array(4...9) }
        shuffle(&candidates)
        let startOffset = candidates.first ?? 5
        let days = rng.int(2...3)
        travelOffsets = Set(startOffset..<(startOffset + days))
        let start = dayStart(startOffset)
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86400)
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

    mutating func placeWedding() {
        var weekends = (1...13).filter { isWeekend($0) && !travelOffsets.contains($0) }
        if weekends.isEmpty { weekends = (1...13).filter(isWeekend) }
        shuffle(&weekends)
        let offset = weekends.first ?? 6
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

    mutating func placeGame() {
        let evening = rng.int(1...100) <= 60
        var days = (1...13).filter { !travelOffsets.contains($0) && !hasKind(.wedding, on: $0) }
        if evening { days = days.filter { !isWeekend($0) } + days.filter(isWeekend) }
        shuffle(&days)
        let offset = days.first ?? 3
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
        if rng.int(1...100) <= 35 {
            let extraDays = days.filter { $0 != offset }
            if let extra = extraDays.first {
                addTimed(
                    .game,
                    title: PlaceBank.pick(PlaceBank.games, &rng),
                    place: PlaceBank.pick(PlaceBank.gameVenues, &rng),
                    offset: extra,
                    hour: rng.int(17...20),
                    minute: rng.int(0...25),
                    minutes: rng.int(80...130)
                )
            }
        }
    }

    mutating func placeFamily() {
        var days = (1...13).filter { isWeekend($0) && !travelOffsets.contains($0) && !hasKind(.wedding, on: $0) }
        if days.isEmpty { days = (2...12).filter { !travelOffsets.contains($0) } }
        shuffle(&days)
        guard let offset = days.first else { return }
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

    // MARK: Ordinary density

    mutating func fillWorkdays() {
        for offset in 0...13 {
            if isWeekend(offset) || travelOffsets.contains(offset) { continue }
            let hourNow = calendar.component(.hour, from: now)
            if offset != 0 || hourNow < 10, rng.int(1...100) <= 72 {
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
            if rng.int(1...100) <= 62 {
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
            if rng.int(1...100) <= 42 {
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
            if rng.int(1...100) <= 55 {
                let hourNow = calendar.component(.hour, from: now)
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
        var evenings = (0...13).filter { !travelOffsets.contains($0) && !hasKind(.wedding, on: $0) }
        shuffle(&evenings)
        let count = rng.int(2...4)
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
    }

    mutating func placeAppointments() {
        var days = (1...12).filter { !isWeekend($0) && !travelOffsets.contains($0) }
        shuffle(&days)
        let count = rng.int(1...2)
        for offset in days.prefix(count) {
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
        if rng.int(1...100) <= 45 {
            var days = (1...13).filter { !travelOffsets.contains($0) && !hasKind(.wedding, on: $0) }
            shuffle(&days)
            if let offset = days.first {
                let start = dayStart(offset)
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
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
        }
        if rng.int(1...100) <= 40 {
            var days = (1...13).filter {
                !travelOffsets.contains($0) && !hasKind(.wedding, on: $0) && !hasKind(.game, on: $0)
            }
            shuffle(&days)
            if let offset = days.first {
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
        if start <= now, !force { return }
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
