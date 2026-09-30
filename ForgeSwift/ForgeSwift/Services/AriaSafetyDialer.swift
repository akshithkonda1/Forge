import Foundation
import UIKit

/// Safety chips that place a call instead of sending chat text.
///
/// A 911 / triage reply offers "Call 911", "Call or text 988", or "Call
/// Poison Control". Tapping one while a safety session is open dials (iOS
/// still shows its own confirmation) and counts as escalation achieved:
/// ARIA's voice turns off and the relationship check-in is posted.
enum AriaSafetyDialer {
    /// Digits for a safety chip label, or nil for an ordinary chip.
    static func number(forAction label: String) -> String? {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "call 911":
            return "911"
        case "call or text 988":
            return "988"
        case "call poison control":
            return "18002221222"
        default:
            return nil
        }
    }

    @MainActor
    static func dial(_ number: String) {
        guard let url = URL(string: "tel:\(number)") else { return }
        UIApplication.shared.open(url)
    }
}
