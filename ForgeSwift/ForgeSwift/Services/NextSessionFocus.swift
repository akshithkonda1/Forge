import Foundation

/// Picks tomorrow's body-region library from yesterday, the clock, and
/// what they know. Mirrors backend ``services/body_library.py`` so ARIA
/// and the Train tab open the same library.
enum NextSessionFocus {

    struct Suggestion: Equatable {
        let region: TargetMuscle.Region
        let extra: TargetMuscle.Region?
        let title: String
        let reason: String
        let alternatives: [TargetMuscle.Region]
        let avoided: TargetMuscle.Region?
        var exerciseCount: Int = 6
        var weekday: Int? = nil
        var planningMode: SchedulePlanningMode = .rotate

        var muscles: [TargetMuscle] {
            TargetMuscle.allCases.filter { $0.region == region }
        }
    }

    static let freshHours: Double = 36
    static let fullBodyHours: Double = 72

    static func isSessionAsk(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "train", "workout", "session", "lift", "gym", "exercise",
            "today's plan", "todays plan", "what should i do today",
            "leg day", "push day", "pull day",
            "yesterday's session", "yesterdays session", "do yesterday",
            "day prior", "this week's", "this weeks",
        ]
        return needles.contains { lower.contains($0) }
    }

    static func inferRegion(name: String?, type: WorkoutType?) -> TargetMuscle.Region? {
        let blob = [name, type?.rawValue].compactMap { $0 }.joined(separator: " ").lowercased()
        guard !blob.isEmpty else { return nil }
        let aliases: [(String, TargetMuscle.Region)] = [
            ("full body", .conditioning), ("full-body", .conditioning),
            ("lower body", .legs), ("leg", .legs), ("squat", .legs),
            ("lunge", .legs), ("deadlift", .legs), ("quad", .legs),
            ("hamstring", .legs), ("glute", .legs), ("calf", .legs),
            ("chest", .push), ("bench", .push), ("press", .push),
            ("pec", .push), ("tricep", .push), ("shoulder", .push),
            ("push", .push),
            ("pull", .pull), ("row", .pull), ("lat", .pull),
            ("back", .pull), ("bicep", .pull),
            ("core", .core), ("abs", .core), ("plank", .core),
            ("cardio", .conditioning), ("hiit", .conditioning),
            ("run", .conditioning), ("circuit", .conditioning),
        ]
        return aliases
            .filter { blob.contains($0.0) }
            .max(by: { $0.0.count < $1.0.count })?
            .1
            ?? typeRegion(type)
    }

    static func hoursSince(last: WorkoutHistory, now: Date) -> Double? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: last.date) ?? ISO8601DateFormatter().date(from: last.date) {
            return now.timeIntervalSince(date) / 3600
        }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        if let date = day.date(from: String(last.date.prefix(10))) {
            return now.timeIntervalSince(date) / 3600
        }
        return nil
    }

    static func suggest(
        history: [WorkoutHistory],
        now: Date,
        experience: ExperienceLevel,
        readiness: Int,
        mode: SchedulePlanningMode = .rotate,
        split: [WeeklySplitSlot] = WeeklySplitSlot.defaultWeek,
        pickWeekday: Int? = nil,
        replayPrior: Bool = false
    ) -> Suggestion {
        let last = history.first
        let lastRegion = last.flatMap { inferRegion(name: $0.name, type: $0.type) }
        let hours = last.flatMap { hoursSince(last: $0, now: now) }
        let stillFresh = (hours ?? .greatestFiniteMagnitude) < freshHours
        let longGap = hours == nil || hours! >= fullBodyHours
        let avoided: TargetMuscle.Region? = stillFresh ? lastRegion : nil
        let beginner = experience == .beginner
        let today = WeeklySplit.sun0(from: now)
        let week = WeeklySplit.normalized(split)

        if replayPrior || pickWeekday != nil {
            let day = replayPrior ? (today + 6) % 7 : ((pickWeekday! % 7) + 7) % 7
            let slot = WeeklySplit.slot(for: day, in: week)
            var reason = slotReason(slot, prefix: replayPrior ? "Going back one day." : "You picked \(WeeklySplit.dayNames[day]).")
            if let avoided, slot.region == avoided {
                reason = "\(avoided.label) is still fresh — your call. \(reason)"
            }
            return from(slot: slot, reason: reason, avoided: avoided, mode: mode)
        }

        if readiness < 55 {
            return Suggestion(
                region: .core,
                extra: nil,
                title: "Easy core",
                reason: "Recovery is asking for care, so I'm keeping the floor small.",
                alternatives: [.conditioning],
                avoided: avoided,
                exerciseCount: 4,
                weekday: today,
                planningMode: mode
            )
        }

        if mode == .fixed {
            let todaySlot = WeeklySplit.slot(for: today, in: week)
            let open = nextOpenSlot(from: todaySlot, week: week, avoided: avoided)
            var prefix: String? = nil
            if open.weekday != todaySlot.weekday, let avoided {
                prefix = "\(avoided.label) is still fresh, so I'm opening the next day on your week."
            }
            return from(slot: open, reason: slotReason(open, prefix: prefix), avoided: avoided, mode: .fixed)
        }

        // Tuesday legs → Wednesday chest + abs (rotate after yesterday).
        if avoided == .legs {
            return Suggestion(
                region: .push,
                extra: .core,
                title: "Chest and abs",
                reason: yesterdayReason(last: last, region: lastRegion, hours: hours),
                alternatives: [.pull, .conditioning],
                avoided: .legs,
                exerciseCount: 6,
                weekday: today,
                planningMode: mode
            )
        }

        // No last session — walk the calendar (Tue legs, Wed chest+abs).
        if lastRegion == nil {
            let slot = WeeklySplit.slot(for: today, in: week)
            return from(slot: slot, reason: slotReason(slot), avoided: avoided, mode: mode)
        }

        if beginner || longGap {
            return Suggestion(
                region: .conditioning,
                extra: nil,
                title: "Full body",
                reason: longGap && !beginner
                    ? "It's been a few days, so a full-body session from the libraries fits."
                    : "Keeping it full-body — consistency beats a split you don't need yet.",
                alternatives: [.push, .legs],
                avoided: avoided,
                exerciseCount: 6,
                weekday: today,
                planningMode: mode
            )
        }

        let next: TargetMuscle.Region
        var alts: [TargetMuscle.Region]
        switch lastRegion {
        case .push: next = .pull; alts = [.legs, .core]
        case .pull: next = .legs; alts = [.push, .core]
        case .core: next = .push; alts = [.legs, .pull]
        case .conditioning: next = .push; alts = [.pull, .legs]
        case .legs, .none: next = .push; alts = [.pull, .core]
        }
        let calWeekday = Calendar.current.component(.weekday, from: now) // 1=Sun
        if calWeekday == 1 || calWeekday == 7 {
            alts = [.conditioning] + alts
        }
        return Suggestion(
            region: next,
            extra: nil,
            title: next.label,
            reason: yesterdayReason(last: last, region: lastRegion, hours: hours),
            alternatives: Array(alts.prefix(2)),
            avoided: avoided,
            exerciseCount: 5,
            weekday: today,
            planningMode: mode
        )
    }

    private static func from(
        slot: WeeklySplitSlot,
        reason: String,
        avoided: TargetMuscle.Region?,
        mode: SchedulePlanningMode
    ) -> Suggestion {
        if slot.isRest {
            return Suggestion(
                region: .core,
                extra: nil,
                title: "Rest day",
                reason: reason,
                alternatives: [.conditioning],
                avoided: avoided,
                exerciseCount: max(2, min(4, slot.exerciseCount == 0 ? 3 : slot.exerciseCount)),
                weekday: slot.weekday,
                planningMode: mode
            )
        }
        if slot.primary == "full_body" {
            return Suggestion(
                region: .conditioning,
                extra: nil,
                title: "Full body",
                reason: reason,
                alternatives: [.push, .legs],
                avoided: avoided,
                exerciseCount: max(4, slot.exerciseCount),
                weekday: slot.weekday,
                planningMode: mode
            )
        }
        return Suggestion(
            region: slot.region ?? .push,
            extra: slot.extraRegion,
            title: slot.title,
            reason: reason,
            alternatives: [.pull, .legs],
            avoided: avoided,
            exerciseCount: max(2, min(8, slot.exerciseCount)),
            weekday: slot.weekday,
            planningMode: mode
        )
    }

    private static func slotReason(_ slot: WeeklySplitSlot, prefix: String? = nil) -> String {
        let day = WeeklySplit.dayNames[slot.weekday]
        let body: String
        if slot.isRest {
            body = "\(day) on your week is a rest slot — easy core if you still want to move."
        } else {
            body = "\(day) on your week is \(slot.title.lowercased())."
        }
        if let prefix, !prefix.isEmpty { return "\(prefix) \(body)" }
        return body
    }

    private static func nextOpenSlot(
        from start: WeeklySplitSlot,
        week: [WeeklySplitSlot],
        avoided: TargetMuscle.Region?
    ) -> WeeklySplitSlot {
        guard let avoided, !start.isRest, start.region == avoided else { return start }
        for delta in 1...6 {
            let nxt = WeeklySplit.slot(for: start.weekday + delta, in: week)
            if !nxt.isRest, nxt.region != avoided { return nxt }
        }
        return start
    }

    private static func typeRegion(_ type: WorkoutType?) -> TargetMuscle.Region? {
        switch type {
        case .cardio, .hiit, .yoga, .mobility: return .conditioning
        default: return nil
        }
    }

    private static func yesterdayReason(last: WorkoutHistory?, region: TargetMuscle.Region?, hours: Double?) -> String {
        let what = last?.name.isEmpty == false ? last!.name : (region?.label ?? "your last session")
        let when: String
        if let hours, hours < 24 { when = "yesterday" }
        else if let hours, hours < 48 { when = "about a day ago" }
        else { when = "last time" }
        if region != nil {
            return "\(what) was \(when), so that tissue sits this one out."
        }
        return "\(what) was \(when) — I'll rotate the library rather than repeat it."
    }
}
