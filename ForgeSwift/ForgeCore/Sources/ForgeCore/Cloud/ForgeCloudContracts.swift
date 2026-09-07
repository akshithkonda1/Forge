import Foundation

// MARK: - Flexible JSON keys

struct AnyCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where K == AnyCodingKey {
    func decodeIfPresent<T: Decodable>(_ type: T.Type, keys: String...) throws -> T? {
        for key in keys {
            if let value = try decodeIfPresent(type, forKey: AnyCodingKey(key)) {
                return value
            }
        }
        return nil
    }

    func nestedIfPresent(keys: String...) throws -> KeyedDecodingContainer<AnyCodingKey>? {
        for key in keys {
            if let nested = try? nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey(key)) {
                return nested
            }
        }
        return nil
    }
}

enum CloudJSON {
    static func int(from container: KeyedDecodingContainer<AnyCodingKey>, keys: String...) -> Int? {
        for key in keys {
            let k = AnyCodingKey(key)
            if let value = try? container.decodeIfPresent(Int.self, forKey: k) {
                return value
            }
            if let value = try? container.decodeIfPresent(Double.self, forKey: k) {
                return Int(value.rounded())
            }
            if let raw = try? container.decodeIfPresent(String.self, forKey: k),
               let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return value
            }
        }
        return nil
    }

    static func double(from container: KeyedDecodingContainer<AnyCodingKey>, keys: String...) -> Double? {
        for key in keys {
            let k = AnyCodingKey(key)
            if let value = try? container.decodeIfPresent(Double.self, forKey: k) {
                return value
            }
            if let value = try? container.decodeIfPresent(Int.self, forKey: k) {
                return Double(value)
            }
            if let raw = try? container.decodeIfPresent(String.self, forKey: k),
               let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return value
            }
        }
        return nil
    }

    static func string(from container: KeyedDecodingContainer<AnyCodingKey>, keys: String...) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: AnyCodingKey(key)),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    static func bool(from container: KeyedDecodingContainer<AnyCodingKey>, keys: String..., default defaultValue: Bool? = nil) -> Bool? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Bool.self, forKey: AnyCodingKey(key)) {
                return value
            }
        }
        return defaultValue
    }

    static func parseDate(_ raw: String?) -> Date {
        guard let raw, !raw.isEmpty else { return Date() }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(raw.prefix(10))) ?? Date()
    }
}

// MARK: - Rich cards (chat + coach)

public struct CloudRichCardExercise: Equatable, Sendable {
    public var name: String
    public var sets: Int
    public var reps: String

    public init(name: String, sets: Int, reps: String) {
        self.name = name
        self.sets = sets
        self.reps = reps
    }
}

extension CloudRichCardExercise: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        name = CloudJSON.string(from: c, keys: "name", "exercise", "title") ?? "Exercise"
        sets = CloudJSON.int(from: c, keys: "sets") ?? 3
        if let repsText = CloudJSON.string(from: c, keys: "reps", "repRange", "rep_range") {
            reps = repsText
        } else if let repsNum = CloudJSON.int(from: c, keys: "reps") {
            reps = String(repsNum)
        } else {
            reps = "8"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(name, forKey: AnyCodingKey("name"))
        try c.encode(sets, forKey: AnyCodingKey("sets"))
        try c.encode(reps, forKey: AnyCodingKey("reps"))
    }
}

public struct CloudRichCard: Equatable, Sendable {
    public var type: String
    public var title: String?
    public var values: [Double]?
    public var insight: String?
    public var color: String?
    public var workoutName: String?
    public var durationMinutes: Int?
    public var exercises: [CloudRichCardExercise]
    public var toolCallsMade: [String]

    public init(
        type: String,
        title: String? = nil,
        values: [Double]? = nil,
        insight: String? = nil,
        color: String? = nil,
        workoutName: String? = nil,
        durationMinutes: Int? = nil,
        exercises: [CloudRichCardExercise] = [],
        toolCallsMade: [String] = []
    ) {
        self.type = type
        self.title = title
        self.values = values
        self.insight = insight
        self.color = color
        self.workoutName = workoutName
        self.durationMinutes = durationMinutes
        self.exercises = exercises
        self.toolCallsMade = toolCallsMade
    }

    public var isWorkoutPlan: Bool {
        let normalized = type.lowercased().replacingOccurrences(of: "_", with: "-")
        return normalized == "workout-plan" || normalized == "workoutplan"
    }

    public var isDataChart: Bool {
        let normalized = type.lowercased().replacingOccurrences(of: "_", with: "-")
        return normalized == "data-chart" || normalized == "datachart"
    }
}

extension CloudRichCard: Codable {
    public init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: AnyCodingKey.self)
        let data = try top.nestedIfPresent(keys: "data", "payload")
        func pickString(_ keys: String...) -> String? {
            if let data {
                for key in keys {
                    if let value = CloudJSON.string(from: data, keys: key) { return value }
                }
            }
            for key in keys {
                if let value = CloudJSON.string(from: top, keys: key) { return value }
            }
            return nil
        }
        func pickInt(_ keys: String...) -> Int? {
            if let data {
                for key in keys {
                    if let value = CloudJSON.int(from: data, keys: key) { return value }
                }
            }
            for key in keys {
                if let value = CloudJSON.int(from: top, keys: key) { return value }
            }
            return nil
        }

        type = CloudJSON.string(from: top, keys: "type") ?? "unknown"
        title = pickString("title", "chartTitle", "chart_title")
        insight = pickString("insight", "notes", "explanation")
        color = pickString("color", "chartColor", "chart_color")
        workoutName = pickString("workout_name", "workoutName", "name")
        durationMinutes = pickInt("duration_minutes", "durationMinutes", "duration")
        if let dataValues = try data?.decodeIfPresent([Double].self, keys: "values"), !dataValues.isEmpty {
            values = dataValues
        } else {
            values = try top.decodeIfPresent([Double].self, keys: "values")
        }

        if let nested = try data?.decodeIfPresent([CloudRichCardExercise].self, keys: "exercises"), !nested.isEmpty {
            exercises = nested
        } else {
            exercises = (try top.decodeIfPresent([CloudRichCardExercise].self, keys: "exercises")) ?? []
        }

        if let nestedTools = try data?.decodeIfPresent([String].self, keys: "tool_calls_made", "toolCallsMade"), !nestedTools.isEmpty {
            toolCallsMade = nestedTools
        } else {
            toolCallsMade = (try top.decodeIfPresent([String].self, keys: "tool_calls_made", "toolCallsMade")) ?? []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(type, forKey: AnyCodingKey("type"))
        try c.encodeIfPresent(title, forKey: AnyCodingKey("title"))
        try c.encodeIfPresent(values, forKey: AnyCodingKey("values"))
        try c.encodeIfPresent(insight, forKey: AnyCodingKey("insight"))
        try c.encodeIfPresent(color, forKey: AnyCodingKey("color"))
        try c.encodeIfPresent(workoutName, forKey: AnyCodingKey("workout_name"))
        try c.encodeIfPresent(durationMinutes, forKey: AnyCodingKey("duration_minutes"))
        if !exercises.isEmpty {
            try c.encode(exercises, forKey: AnyCodingKey("exercises"))
        }
        if !toolCallsMade.isEmpty {
            try c.encode(toolCallsMade, forKey: AnyCodingKey("tool_calls_made"))
        }
    }
}

// MARK: - Chat thread

public struct CloudChatMessage: Equatable, Sendable {
    public var id: String
    public var role: String
    public var content: String
    public var timestamp: Date
    public var richCard: CloudRichCard?
    public var toolCallsMade: [String]

    public init(
        id: String,
        role: String,
        content: String,
        timestamp: Date,
        richCard: CloudRichCard? = nil,
        toolCallsMade: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.richCard = richCard
        self.toolCallsMade = toolCallsMade
    }

    public var isDemoSeed: Bool {
        ["m1", "m2", "m3", "m4"].contains(id)
    }
}

extension CloudChatMessage: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        id = CloudJSON.string(from: c, keys: "id") ?? UUID().uuidString
        role = (CloudJSON.string(from: c, keys: "role") ?? "trainer").lowercased()
        content = CloudJSON.string(from: c, keys: "content", "message") ?? ""
        timestamp = CloudJSON.parseDate(CloudJSON.string(from: c, keys: "timestamp", "createdAt", "created_at"))
        richCard = try c.decodeIfPresent(CloudRichCard.self, keys: "rich_card", "richCard")
        toolCallsMade = (try c.decodeIfPresent([String].self, keys: "tool_calls_made", "toolCallsMade")) ?? []
    }
}

public struct CloudChatThread: Equatable, Sendable {
    public var threadId: String
    public var messages: [CloudChatMessage]

    public init(threadId: String, messages: [CloudChatMessage]) {
        self.threadId = threadId
        self.messages = messages
    }

    public var looksLikeDemoSeed: Bool {
        let ids = Set(messages.map(\.id))
        return ids.isSuperset(of: ["m1", "m2", "m3", "m4"])
    }
}

extension CloudChatThread: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        threadId = CloudJSON.string(from: c, keys: "threadId", "thread_id") ?? "current"
        messages = (try c.decodeIfPresent([CloudChatMessage].self, keys: "messages")) ?? []
    }
}

// MARK: - Health batch

public struct CloudHealthMetric: Equatable, Encodable, Sendable {
    public var metricType: String
    public var source: String
    public var startedAt: String
    public var value: Double
    public var unit: String?

    public init(metricType: String, source: String, startedAt: String, value: Double, unit: String? = nil) {
        self.metricType = metricType
        self.source = source
        self.startedAt = startedAt
        self.value = value
        self.unit = unit
    }
}

public struct CloudHealthBatchResult: Equatable, Decodable, Sendable {
    public var accepted: Int
    public var rejected: Int

    public init(accepted: Int, rejected: Int) {
        self.accepted = accepted
        self.rejected = rejected
    }
}

public enum CloudHealthMetricType {
    public static let valid: Set<String> = [
        "steps",
        "active-calories",
        "hrv",
        "resting-heart-rate",
        "heart-rate",
        "sleep-stage",
        "body-weight",
        "distance",
    ]

    public static let validSources: Set<String> = [
        "apple-health",
        "oura",
        "whoop",
        "garmin",
        "strava",
        "manual",
    ]

    public static func canonicalType(_ raw: String) -> String? {
        let key = raw.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch key {
        case "steps":
            return "steps"
        case "active-calories", "activecalories", "active-energy", "calories":
            return "active-calories"
        case "hrv":
            return "hrv"
        case "resting-heart-rate", "resting-hr", "restinghr":
            return "resting-heart-rate"
        case "heart-rate", "heartrate", "hr":
            return "heart-rate"
        case "sleep-stage":
            return "sleep-stage"
        case "body-weight", "weight":
            return "body-weight"
        case "distance":
            return "distance"
        default:
            return valid.contains(key) ? key : nil
        }
    }

    public static func canonicalSource(_ raw: String?) -> String {
        let key = (raw ?? "apple-health").lowercased()
            .replacingOccurrences(of: "_", with: "-")
        if validSources.contains(key) { return key }
        if key.contains("apple") || key.contains("healthkit") { return "apple-health" }
        if key.contains("oura") { return "oura" }
        if key.contains("whoop") { return "whoop" }
        if key.contains("garmin") { return "garmin" }
        if key.contains("strava") { return "strava" }
        return "manual"
    }

    public static func metrics(
        from samples: [(type: String, value: Double, unit: String?, timestamp: String?, source: String?)]
    ) -> [CloudHealthMetric] {
        samples.compactMap { sample in
            guard let type = canonicalType(sample.type), sample.value.isFinite else { return nil }
            let startedAt = sample.timestamp?.isEmpty == false
                ? sample.timestamp!
                : ISO8601DateFormatter().string(from: Date())
            return CloudHealthMetric(
                metricType: type,
                source: canonicalSource(sample.source),
                startedAt: startedAt,
                value: sample.value,
                unit: sample.unit
            )
        }
    }
}

// MARK: - Dashboard / coach

public struct CloudReadiness: Equatable, Sendable {
    public var overall: Int?
    public var sleepQuality: Int?
    public var recoveryScore: Int?
    public var stressLevel: Int?
    public var energyBank: Int?
    public var available: Bool

    public init(
        overall: Int? = nil,
        sleepQuality: Int? = nil,
        recoveryScore: Int? = nil,
        stressLevel: Int? = nil,
        energyBank: Int? = nil,
        available: Bool = true
    ) {
        self.overall = overall
        self.sleepQuality = sleepQuality
        self.recoveryScore = recoveryScore
        self.stressLevel = stressLevel
        self.energyBank = energyBank
        self.available = available
    }

    public var isUsable: Bool {
        available && overall != nil
    }
}

extension CloudReadiness: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        overall = CloudJSON.int(from: c, keys: "overall")
        sleepQuality = CloudJSON.int(from: c, keys: "sleepQuality", "sleep_quality")
        recoveryScore = CloudJSON.int(from: c, keys: "recoveryScore", "recovery_score")
        stressLevel = CloudJSON.int(from: c, keys: "stressLevel", "stress_level")
        energyBank = CloudJSON.int(from: c, keys: "energyBank", "energy_bank")
        available = CloudJSON.bool(from: c, keys: "available", default: overall != nil) ?? (overall != nil)
    }
}

public struct CloudDailyMetrics: Equatable, Sendable {
    public var date: String?
    public var steps: Int?
    public var activeCalories: Int?
    public var hrv: Int?
    public var restingHR: Int?
    public var deepSleep: Int?
    public var totalSleep: Int?
    public var sources: [String]

    public init(
        date: String? = nil,
        steps: Int? = nil,
        activeCalories: Int? = nil,
        hrv: Int? = nil,
        restingHR: Int? = nil,
        deepSleep: Int? = nil,
        totalSleep: Int? = nil,
        sources: [String] = []
    ) {
        self.date = date
        self.steps = steps
        self.activeCalories = activeCalories
        self.hrv = hrv
        self.restingHR = restingHR
        self.deepSleep = deepSleep
        self.totalSleep = totalSleep
        self.sources = sources
    }
}

extension CloudDailyMetrics: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        date = CloudJSON.string(from: c, keys: "date")
        steps = CloudJSON.int(from: c, keys: "steps")
        activeCalories = CloudJSON.int(from: c, keys: "activeCalories", "active_calories")
        hrv = CloudJSON.int(from: c, keys: "hrv")
        restingHR = CloudJSON.int(from: c, keys: "restingHR", "resting_hr")
        deepSleep = CloudJSON.int(from: c, keys: "deepSleep", "deep_sleep")
        totalSleep = CloudJSON.int(from: c, keys: "totalSleep", "total_sleep")
        sources = (try c.decodeIfPresent([String].self, keys: "sources")) ?? []
    }
}

public struct CloudWorkoutExerciseDTO: Equatable, Sendable {
    public var id: String?
    public var name: String
    public var sets: Int
    public var reps: String
    public var weight: Int?
    public var restSeconds: Int?
    public var notes: String?

    public init(
        id: String? = nil,
        name: String,
        sets: Int,
        reps: String,
        weight: Int? = nil,
        restSeconds: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.restSeconds = restSeconds
        self.notes = notes
    }
}

extension CloudWorkoutExerciseDTO: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        id = CloudJSON.string(from: c, keys: "id")
        name = CloudJSON.string(from: c, keys: "name") ?? "Exercise"
        sets = CloudJSON.int(from: c, keys: "sets") ?? 3
        if let repsText = CloudJSON.string(from: c, keys: "reps") {
            reps = repsText
        } else if let repsNum = CloudJSON.int(from: c, keys: "reps") {
            reps = String(repsNum)
        } else {
            reps = "8"
        }
        weight = CloudJSON.int(from: c, keys: "weight")
        restSeconds = CloudJSON.int(from: c, keys: "restSeconds", "rest_seconds")
        notes = CloudJSON.string(from: c, keys: "notes")
    }
}

public struct CloudWorkoutPlanDTO: Equatable, Sendable {
    public var id: String?
    public var date: String?
    public var name: String
    public var type: String?
    public var duration: Int?
    public var intensity: String?
    public var notes: String?
    public var exercises: [CloudWorkoutExerciseDTO]

    public init(
        id: String? = nil,
        date: String? = nil,
        name: String,
        type: String? = nil,
        duration: Int? = nil,
        intensity: String? = nil,
        notes: String? = nil,
        exercises: [CloudWorkoutExerciseDTO] = []
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.type = type
        self.duration = duration
        self.intensity = intensity
        self.notes = notes
        self.exercises = exercises
    }
}

extension CloudWorkoutPlanDTO: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        id = CloudJSON.string(from: c, keys: "id")
        date = CloudJSON.string(from: c, keys: "date")
        name = CloudJSON.string(from: c, keys: "name", "title") ?? "Today's session"
        type = CloudJSON.string(from: c, keys: "type")
        duration = CloudJSON.int(from: c, keys: "duration", "durationMinutes", "duration_minutes")
        intensity = CloudJSON.string(from: c, keys: "intensity")
        notes = CloudJSON.string(from: c, keys: "notes")
        exercises = (try c.decodeIfPresent([CloudWorkoutExerciseDTO].self, keys: "exercises")) ?? []
    }
}

public struct CloudSleepNightDTO: Equatable, Sendable {
    public var date: String
    public var totalHours: Double
    public var deepMinutes: Int
    public var remMinutes: Int
    public var lightMinutes: Int
    public var awakeMinutes: Int
    public var score: Int
}

extension CloudSleepNightDTO: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        date = CloudJSON.string(from: c, keys: "date") ?? ""
        totalHours = CloudJSON.double(from: c, keys: "totalHours", "total_hours") ?? 0
        deepMinutes = CloudJSON.int(from: c, keys: "deepMinutes", "deep_minutes") ?? 0
        remMinutes = CloudJSON.int(from: c, keys: "remMinutes", "rem_minutes") ?? 0
        lightMinutes = CloudJSON.int(from: c, keys: "lightMinutes", "light_minutes") ?? 0
        awakeMinutes = CloudJSON.int(from: c, keys: "awakeMinutes", "awake_minutes") ?? 0
        score = CloudJSON.int(from: c, keys: "score") ?? 0
    }
}

public struct CloudWorkoutHistoryDTO: Equatable, Sendable {
    public var id: String
    public var date: String
    public var name: String
    public var type: String?
    public var duration: Int
    public var volume: Int
    public var intensity: String?
}

extension CloudWorkoutHistoryDTO: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        id = CloudJSON.string(from: c, keys: "id") ?? UUID().uuidString
        date = CloudJSON.string(from: c, keys: "date") ?? ""
        name = CloudJSON.string(from: c, keys: "name") ?? "Session"
        type = CloudJSON.string(from: c, keys: "type")
        duration = CloudJSON.int(from: c, keys: "duration") ?? 0
        volume = CloudJSON.int(from: c, keys: "volume") ?? 0
        intensity = CloudJSON.string(from: c, keys: "intensity")
    }
}

public struct CloudPersonalRecordDTO: Equatable, Sendable {
    public var exercise: String
    public var value: Double
    public var unit: String
    public var date: String
}

extension CloudPersonalRecordDTO: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        exercise = CloudJSON.string(from: c, keys: "exercise") ?? ""
        value = CloudJSON.double(from: c, keys: "value") ?? 0
        unit = CloudJSON.string(from: c, keys: "unit") ?? "lb"
        date = CloudJSON.string(from: c, keys: "date") ?? ""
    }
}

public struct CloudConnectionDTO: Equatable, Sendable {
    public var provider: String
    public var status: String?
}

extension CloudConnectionDTO: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        provider = CloudJSON.string(from: c, keys: "provider", "id", "name") ?? ""
        status = CloudJSON.string(from: c, keys: "status")
    }
}

public struct CloudDashboardToday: Equatable, Sendable {
    public var readiness: CloudReadiness?
    public var dailyMetrics: CloudDailyMetrics?
    public var todayWorkout: CloudWorkoutPlanDTO?
    public var recentSleep: [CloudSleepNightDTO]
    public var recentWorkouts: [CloudWorkoutHistoryDTO]
    public var personalRecords: [CloudPersonalRecordDTO]
    public var connections: [CloudConnectionDTO]
}

extension CloudDashboardToday: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        readiness = try c.decodeIfPresent(CloudReadiness.self, keys: "readiness")
        dailyMetrics = try c.decodeIfPresent(CloudDailyMetrics.self, keys: "dailyMetrics", "daily_metrics")
        todayWorkout = try c.decodeIfPresent(CloudWorkoutPlanDTO.self, keys: "todayWorkout", "today_workout")
        recentSleep = (try c.decodeIfPresent([CloudSleepNightDTO].self, keys: "recentSleep", "recent_sleep")) ?? []
        recentWorkouts = (try c.decodeIfPresent([CloudWorkoutHistoryDTO].self, keys: "recentWorkouts", "recent_workouts")) ?? []
        personalRecords = (try c.decodeIfPresent([CloudPersonalRecordDTO].self, keys: "personalRecords", "personal_records")) ?? []
        connections = (try c.decodeIfPresent([CloudConnectionDTO].self, keys: "connections")) ?? []
    }
}

public struct CloudCoachBaseline: Equatable, Sendable {
    public var focus: String?
    public var suggestedType: String?
    public var intensity: String?
}

extension CloudCoachBaseline: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        focus = CloudJSON.string(from: c, keys: "focus")
        suggestedType = CloudJSON.string(from: c, keys: "suggestedType", "suggested_type")
        intensity = CloudJSON.string(from: c, keys: "intensity")
    }
}

public struct CloudCoachWorkoutPlan: Equatable, Sendable {
    public var baseline: CloudCoachBaseline?
    public var todayPlan: CloudWorkoutPlanDTO?
    public var explanation: String
    public var fallback: Bool
}

extension CloudCoachWorkoutPlan: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        baseline = try c.decodeIfPresent(CloudCoachBaseline.self, keys: "baseline")
        todayPlan = try c.decodeIfPresent(CloudWorkoutPlanDTO.self, keys: "todayPlan", "today_plan")
        explanation = CloudJSON.string(from: c, keys: "explanation", "answer") ?? ""
        fallback = CloudJSON.bool(from: c, keys: "fallback", default: false) ?? false
    }
}

public struct CloudCoachSleepInsight: Equatable, Sendable {
    public var insight: String
    public var fallback: Bool
}

extension CloudCoachSleepInsight: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        insight = CloudJSON.string(from: c, keys: "insight", "answer") ?? ""
        fallback = CloudJSON.bool(from: c, keys: "fallback", default: false) ?? false
    }
}

public struct CloudCoachProgressReview: Equatable, Sendable {
    public var review: String
    public var fallback: Bool
}

extension CloudCoachProgressReview: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        review = CloudJSON.string(from: c, keys: "review", "answer") ?? ""
        fallback = CloudJSON.bool(from: c, keys: "fallback", default: false) ?? false
    }
}

public enum CloudSourceLabel {
    public static func displayName(for source: String) -> String {
        switch source.lowercased() {
        case "apple-health", "apple_health", "healthkit":
            return "Apple Health"
        case "oura":
            return "Oura via Terra"
        case "whoop":
            return "WHOOP via Terra"
        case "garmin":
            return "Garmin via Terra"
        case "strava":
            return "Strava via Terra"
        case "manual":
            return "Manual"
        default:
            return source.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}
