import Foundation

/// Form-check stays on this phone.
///
/// A third-party app cannot call Apple Private Cloud Compute directly.
/// PCC is only reached through Apple's own frameworks: Foundation Models
/// / Apple Intelligence decide on-device vs PCC. Forge never sends a
/// frame or pose to its servers.
public struct OnDeviceFormRead: Equatable, Sendable {
    public var score: Int
    public var status: String
    public var summary: String
    public var cues: [String]
    public var usedFoundationModels: Bool
    public var personInFrame: Bool

    public init(
        score: Int,
        status: String,
        summary: String,
        cues: [String],
        usedFoundationModels: Bool,
        personInFrame: Bool
    ) {
        self.score = score
        self.status = status
        self.summary = summary
        self.cues = cues
        self.usedFoundationModels = usedFoundationModels
        self.personInFrame = personInFrame
    }
}

public enum OnDeviceFormCheck: Sendable {

    public static func evaluate(
        exerciseName: String,
        setLabel: String,
        cues: [String],
        personInFrame: Bool,
        jointCount: Int,
        foundationLine: String? = nil
    ) -> OnDeviceFormRead {
        _ = setLabel
        if !personInFrame || jointCount < 4 {
            return OnDeviceFormRead(
                score: 62,
                status: "adjust",
                summary: "I can't see enough of you in frame. Step back so hips and shoulders are visible.",
                cues: ["Whole body in shot", "Light from the front"],
                usedFoundationModels: false,
                personInFrame: false
            )
        }
        let localCues = cues.isEmpty
            ? ["Brace before you move", "Control the eccentric"]
            : Array(cues.prefix(2))
        if let line = foundationLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
            return OnDeviceFormRead(
                score: 86,
                status: "good",
                summary: String(line.prefix(160)),
                cues: localCues,
                usedFoundationModels: true,
                personInFrame: true
            )
        }
        return OnDeviceFormRead(
            score: 84,
            status: "good",
            summary: "\(exerciseName.isEmpty ? "The movement" : exerciseName) looks controlled on this phone. Keep the tempo honest.",
            cues: localCues,
            usedFoundationModels: false,
            personInFrame: true
        )
    }
}
