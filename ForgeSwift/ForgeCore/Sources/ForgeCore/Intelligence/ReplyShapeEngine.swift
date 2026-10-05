import Foundation

// ============================================================
// MARK: - What shaped this reply
// ============================================================

/// Names the living signals that actually steered ARIA's last turn.
///
/// Coaches score you. Search cites sources. Nobody shows *which of your
/// signals* bent the answer — tomorrow's readiness, how you work, people-
/// energy, an honest estimate, or a phone-local fallback. Lifestyle language
/// only. Never a medical claim, never a model name as the explanation.
public enum ReplyShapeEngine {

    public struct Shape: Sendable, Equatable {
        public var headline: String
        public var detail: String
        public var lanes: [String]

        public var chipLabel: String { "What shaped this · \(headline)" }
        public var ariaTags: [String] { lanes }
    }

    public static func shape(
        prompt: String,
        ariaTags: [String],
        localFallback: Bool,
        scoutUsed: Bool,
        estimate: Bool
    ) -> Shape {
        if estimate {
            return Shape(
                headline: "Estimate, not a lock",
                detail: "I didn't have a clean enough replay to claim more. Ordinary day until more of yours is in — not a medical claim.",
                lanes: ["shape:estimate"]
            )
        }

        var lanes: [String] = []
        var bits: [String] = []
        var headline = "What you asked"

        let lower = prompt.lowercased()
        let hobbyAsk = HobbyPathEngine.isHobbyQuestion(prompt)
        let tomorrowAsk = lower.contains("tomorrow")
        let peopleThin = ariaTags.contains { $0 == "hobby_people:thin" }
        let hobbyPath = ariaTags.compactMap { token -> String? in
            guard token.hasPrefix("hobby_path:") else { return nil }
            return String(token.dropFirst("hobby_path:".count))
        }.first
        let working = ariaTags.compactMap(UserWorkingModel.parseTag).first
        let forecast = ariaTags.compactMap(ReadinessForecastEngine.parseTag).first

        if hobbyAsk || (peopleThin && (hobbyAsk || lower.contains("free"))) {
            lanes.append("shape:hobby")
            if peopleThin {
                headline = "People-energy, not a score"
                bits.append("Tomorrow's people-energy looked thin, so I steered quieter — not a fuller calendar.")
            } else if hobbyPath == "open_gently" {
                headline = "Hobby path"
                bits.append("Solo-first hobby path. Light contact can come later if you want it.")
            } else if hobbyPath == "restore_quiet" {
                headline = "Hobby path"
                bits.append("Restore-quiet hobby path this week. Calendar is not the win.")
            } else {
                headline = "Hobby path"
                bits.append("A free-day path from how you actually live, not a fitter costume.")
            }
        }

        if tomorrowAsk, let forecast {
            lanes.append("shape:forecast")
            if headline == "What you asked" { headline = "Tomorrow's readiness" }
            bits.append("Tomorrow's forecast is \(forecast.0) (\(forecast.1.rawValue)).")
        }

        if let working, working.0 == .overreacher || working.1 == .capHeroics {
            lanes.append("shape:working")
            if headline == "What you asked" { headline = "How you work" }
            bits.append("You tend to push through a heavy week — I capped heroics.")
        } else if let working, working.0 == .weekendDrop {
            lanes.append("shape:working")
            if headline == "What you asked" { headline = "How you work" }
            bits.append("Weekdays hold and weekends slip — I kept a tiny weekend anchor.")
        } else if let working, working.0 == .rebuilding {
            lanes.append("shape:working")
            if headline == "What you asked" { headline = "How you work" }
            bits.append("You're finding the rhythm again — showing up small is the win.")
        }

        if scoutUsed {
            lanes.append("shape:scout")
            bits.append("Looked up outside the phone, then coached from your life — not from the article.")
        }

        if localFallback {
            lanes.append("shape:local")
            bits.append("This turn stayed on this phone.")
        }

        if bits.isEmpty {
            bits.append("Ordinary coaching from what you asked. No extra steering.")
        }

        return Shape(
            headline: headline,
            detail: bits.joined(separator: " "),
            lanes: lanes.isEmpty ? ["shape:ask"] : lanes
        )
    }
}
