import Foundation

// ============================================================
// MARK: - Life Ops digest
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA sees: counts and Forge's own words — nearest trip as a day
// offset, how many interview holds, how many work holds, reminder overdue /
// due-today counts, today's busy-window count, and a load band
// (quiet / moderate / heavy). Tags are `life_ops:…`. On-device ARIA only;
// `AriaOnDeviceHealthPolicy` strips every `life_ops:` tag and spoken line
// before a remote (/ai/chat) request.
// What stays on-device: calendar titles, places, attendees, reminder titles.
// This type never holds a string that came from the user. Interview holds
// are counted from `LifestyleAsset.isInterview`, which was decided at ingest
// and dropped the title there.
//
// This is Forge's version of inbox / job / travel "automations": ARIA
// coaches around the life load already on this iPhone (Calendar + Reminders),
// instead of shipping mail or GitHub into the cloud.

/// How loud the board is today. Heavy means keep the session kind.
public enum LifeOpsLoad: String, Sendable, Equatable {
    case quiet, moderate, heavy
}

/// Training reshape when Life Ops is loud. Same shape as QoL / event policy.
public struct LifeOpsTrainingPlan: Sendable, Equatable {
    public var keepLight: Bool
    public var reduceVolume: Bool
    public var maxDuration: Int
    public var reason: String

    public init(keepLight: Bool, reduceVolume: Bool, maxDuration: Int, reason: String) {
        self.keepLight = keepLight
        self.reduceVolume = reduceVolume
        self.maxDuration = maxDuration
        self.reason = reason
    }
}

/// Structured life-ops signal ARIA reads instead of mail, a job tracker, or
/// a shipping dashboard.
public struct LifeOpsDigest: Sendable, Equatable {
    /// Nearest flight or trip, in whole days. Nil when none in the travel horizon.
    public var travelDaysUntil: Int?
    public var interviewCount: Int
    public var workHoldCount: Int
    public var reminderOverdue: Int
    public var reminderDueToday: Int
    public var calendarBusyToday: Int
    public var load: LifeOpsLoad

    public init(
        travelDaysUntil: Int? = nil,
        interviewCount: Int = 0,
        workHoldCount: Int = 0,
        reminderOverdue: Int = 0,
        reminderDueToday: Int = 0,
        calendarBusyToday: Int = 0,
        load: LifeOpsLoad = .quiet
    ) {
        self.travelDaysUntil = travelDaysUntil
        self.interviewCount = interviewCount
        self.workHoldCount = workHoldCount
        self.reminderOverdue = reminderOverdue
        self.reminderDueToday = reminderDueToday
        self.calendarBusyToday = calendarBusyToday
        self.load = load
    }

    public static let empty = LifeOpsDigest()

    public var isQuiet: Bool {
        load == .quiet
            && travelDaysUntil == nil
            && interviewCount == 0
            && reminderOverdue == 0
            && reminderDueToday == 0
    }

    /// Tags for on-device ARIA. Integers and Forge's own band names only.
    public var ariaTags: [String] {
        guard !isQuiet else { return ["life_ops:clear"] }
        var tags = ["life_ops:load:\(load.rawValue)"]
        if let days = travelDaysUntil {
            tags.append("life_ops:travel:d\(days)")
        }
        if interviewCount > 0 {
            tags.append("life_ops:interview:\(interviewCount)")
        }
        if load != .quiet, workHoldCount > 0 {
            tags.append("life_ops:work:\(workHoldCount)")
        }
        if reminderOverdue > 0 {
            tags.append("life_ops:reminders_overdue:\(reminderOverdue)")
        }
        if reminderDueToday > 0 {
            tags.append("life_ops:reminders_today:\(reminderDueToday)")
        }
        if load != .quiet, calendarBusyToday > 0 {
            tags.append("life_ops:busy_today:\(calendarBusyToday)")
        }
        return tags
    }

    /// Settings / knowledge-viewer line. Counts only.
    public var summaryLine: String {
        guard !isQuiet else { return "Board is quiet" }
        var parts: [String] = []
        switch load {
        case .heavy: parts.append("Heavy load")
        case .moderate: parts.append("Moderate load")
        case .quiet: break
        }
        if let days = travelDaysUntil {
            if days == 0 {
                parts.append("trip today")
            } else if days == 1 {
                parts.append("trip tomorrow")
            } else {
                parts.append("trip in \(days) days")
            }
        }
        if interviewCount > 0 {
            parts.append("\(interviewCount) interview hold\(interviewCount == 1 ? "" : "s")")
        }
        if reminderOverdue > 0 {
            parts.append("\(reminderOverdue) overdue reminder\(reminderOverdue == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    /// What on-device ARIA says. Never a title, a company, or a city.
    public var spokenLine: String? {
        guard !isQuiet else { return nil }
        var parts: [String] = []
        if load == .heavy {
            parts.append("The board is heavy — overdue reminders or a packed calendar. I'd keep today kind.")
        }
        if let days = travelDaysUntil {
            if days <= 1 {
                parts.append("Travel is here. I'll keep the session able to move.")
            } else if days <= LifestyleAssetIndex.workingHorizonDays {
                parts.append("A trip is \(days) days out — I'll keep training movable as it gets closer.")
            } else {
                parts.append("A trip is \(days) days out. I'll keep it in mind; no need to change today's session yet.")
            }
        }
        if interviewCount > 0 {
            parts.append(
                interviewCount == 1
                    ? "There's an interview hold on the calendar. I don't read the title."
                    : "You've got \(interviewCount) interview holds. I'll keep the session from landing on top of them."
            )
        }
        if parts.isEmpty, workHoldCount > 0, calendarBusyToday >= 3 {
            parts.append("Work holds plus a busy calendar today — I'll leave room around them.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public var trainingPlan: LifeOpsTrainingPlan? {
        switch load {
        case .heavy:
            return LifeOpsTrainingPlan(
                keepLight: true,
                reduceVolume: true,
                maxDuration: 35,
                reason: "Life load is heavy — keep today's session kind."
            )
        case .moderate:
            if interviewCount > 0 {
                return LifeOpsTrainingPlan(
                    keepLight: false,
                    reduceVolume: true,
                    maxDuration: 45,
                    reason: "Interview holds this week — I'll keep the session from stacking on them."
                )
            }
            if let days = travelDaysUntil, days <= 1 {
                return LifeOpsTrainingPlan(
                    keepLight: true,
                    reduceVolume: true,
                    maxDuration: 30,
                    reason: "Travel day — keep the session able to move."
                )
            }
            return nil
        case .quiet:
            return nil
        }
    }

    public static func build(
        assets: [LifestyleAsset],
        reminders: RemindersWorkload?,
        busyToday: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LifeOpsDigest {
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let travelHorizonEnd = calendar.date(
            byAdding: .day,
            value: LifestyleAssetIndex.travelHorizonDays + 1,
            to: today
        ) ?? today

        var nearestTravel: Int?
        var interviews = 0
        var workHolds = 0
        for asset in assets {
            if asset.bucket == .travel, asset.start >= today, asset.start < travelHorizonEnd {
                if nearestTravel == nil || asset.daysUntil < nearestTravel! {
                    nearestTravel = asset.daysUntil
                }
            }
            let inWeek = asset.start >= today && asset.start < weekEnd
            if inWeek, asset.bucket == .work {
                workHolds += 1
                if asset.isInterview { interviews += 1 }
            } else if asset.isInterview, asset.start >= today, asset.start < weekEnd {
                interviews += 1
            }
        }

        let overdue = reminders?.overdueCount ?? 0
        let dueToday = reminders?.dueTodayCount ?? 0
        let busy = max(0, busyToday)
        let load = scoreLoad(
            overdue: overdue,
            dueToday: dueToday,
            busyToday: busy,
            interviewCount: interviews,
            travelDaysUntil: nearestTravel
        )
        return LifeOpsDigest(
            travelDaysUntil: nearestTravel,
            interviewCount: interviews,
            workHoldCount: workHolds,
            reminderOverdue: overdue,
            reminderDueToday: dueToday,
            calendarBusyToday: busy,
            load: load
        )
    }

    static func scoreLoad(
        overdue: Int,
        dueToday: Int,
        busyToday: Int,
        interviewCount: Int,
        travelDaysUntil: Int?
    ) -> LifeOpsLoad {
        let travelSoon = (travelDaysUntil ?? 99) <= 1
        if overdue >= 2 || busyToday >= 4 || interviewCount >= 2 || (interviewCount >= 1 && overdue >= 1) {
            return .heavy
        }
        if overdue >= 1 || dueToday >= 2 || busyToday >= 3 || interviewCount >= 1 || travelSoon {
            return .moderate
        }
        return .quiet
    }
}
