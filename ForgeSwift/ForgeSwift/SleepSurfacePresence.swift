import SwiftUI
import ForgeCore

// MARK: - Research-brief extension points
//
// Forge Sleep is a multi-source reader (Apple Health + any wearable that
// writes the night), not a single-app tracker. Do not hardcode one ring or
// band as the product. When the RISE / Pillow Deep Research brief lands,
// extend these hooks rather than rewriting SleepView.

enum SleepResearchHook: String, CaseIterable, Equatable, Sendable {
    /// Stage-map / hypnogram density — compare to Pillow-class night craft.
    case timeline
    /// How sleep debt is framed versus energy — compare to RISE-class days.
    case debt
    /// Tonight wind-down density (sound dock + ritual), not a clone.
    case windDown

    var waitsForBrief: String {
        switch self {
        case .timeline:
            return "Stage-map craft vs RISE / Pillow (hypnogram density, not a clone)."
        case .debt:
            return "Debt vs energy framing once the brief lands."
        case .windDown:
            return "Tonight wind-down density vs peer sound/ritual craft."
        }
    }
}

enum SleepFeedKind: Equatable, Sendable {
    case loading
    case notConnected
    case connectedEmpty
    case live
}

enum SleepLiveDot: Equatable, Sendable {
    case off, waiting, pulling, live
}

/// Honest empty / not-connected / live presence for the Sleep tab.
struct SleepSurfacePresence: Equatable, Sendable {
    var kind: SleepFeedKind
    var sourceIDs: [String]
    var sourceLabels: [String]
    var liveDot: SleepLiveDot
    var statusCaption: String
    var emptyTitle: String
    var emptyMessage: String
    var emptyCTA: String
    var lastNightEmptyMessage: String
    var lifestyleDisclaimer: String

    var showsEmptyCard: Bool {
        kind == .notConnected || kind == .connectedEmpty
    }

    static func make(
        healthConnected: Bool,
        isLoading: Bool,
        hasScoredNight: Bool,
        metricSources: [String]
    ) -> SleepSurfacePresence {
        let sourceIDs = canonicalSources(
            healthConnected: healthConnected,
            metricSources: metricSources
        )
        let labels = sourceIDs.map(sleepSourceLabel)
        let kind: SleepFeedKind
        if hasScoredNight {
            kind = .live
        } else if isLoading {
            kind = .loading
        } else if healthConnected {
            kind = .connectedEmpty
        } else {
            kind = .notConnected
        }
        let empty = emptyCopy(kind: kind)
        return SleepSurfacePresence(
            kind: kind,
            sourceIDs: sourceIDs,
            sourceLabels: labels,
            liveDot: liveDot(for: kind),
            statusCaption: statusCaption(kind: kind, labels: labels),
            emptyTitle: empty.title,
            emptyMessage: empty.message,
            emptyCTA: empty.cta,
            lastNightEmptyMessage: lastNightEmpty(kind: kind),
            lifestyleDisclaimer: SleepLifestyleCopy.disclaimer
        )
    }

    // MARK: Sources

    /// Hub first (Apple Health when connected), then every other ingest id.
    /// Unknown wearables stay in the list — never collapse to a single brand.
    static func canonicalSources(healthConnected: Bool, metricSources: [String]) -> [String] {
        var ids: [String] = []
        if healthConnected {
            ids.append("apple-health")
        }
        for raw in metricSources {
            let id = canonicalizeSource(raw)
            guard !id.isEmpty, !ids.contains(id) else { continue }
            if id == "apple-watch", ids.contains("apple-health") { continue }
            ids.append(id)
        }
        return ids
    }

    static func canonicalizeSource(_ raw: String) -> String {
        let key = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        if key.isEmpty { return "" }
        if key.contains("healthkit") || key.contains("apple-health") || key == "health" {
            return "apple-health"
        }
        if key.contains("oura") { return "oura" }
        if key.contains("whoop") { return "whoop" }
        if key.contains("garmin") { return "garmin" }
        if key.contains("watch") { return "apple-watch" }
        if key.contains("eight") { return "eight-sleep" }
        if key.contains("ultrahuman") { return "ultrahuman" }
        if key.contains("fitbit") { return "fitbit" }
        return String(key.prefix(40))
    }

    /// Sleep-tab labels: Apple Health as the hub, wearables by name.
    /// Strips backend "via Terra" so the phone UI does not hardcode one ingest pipe.
    static func sleepSourceLabel(_ id: String) -> String {
        switch id {
        case "apple-health": return "Apple Health"
        case "apple-watch": return "Apple Watch"
        case "oura": return "Oura"
        case "whoop": return "WHOOP"
        case "garmin": return "Garmin"
        case "eight-sleep": return "Eight Sleep"
        case "ultrahuman": return "Ultrahuman"
        case "fitbit": return "Fitbit"
        default:
            let cloud = CloudSourceLabel.displayName(for: id)
            if let range = cloud.range(of: " via ", options: .caseInsensitive) {
                return String(cloud[..<range.lowerBound])
            }
            return cloud
        }
    }

    // MARK: Copy

    static func emptyCopy(kind: SleepFeedKind) -> (title: String, message: String, cta: String) {
        switch kind {
        case .connectedEmpty, .loading, .live:
            return (
                "No scored night yet",
                "Forge reads stages from Apple Health — Watch, ring, or any wearable that writes the night. Until a night lands, log in-bed on Tonight — that's a real window, not a fake score.",
                "Refresh from Apple Health"
            )
        case .notConnected:
            return (
                "Connect Apple Health to unlock sleep",
                "Forge reads last night's stages from Apple Health. Watch, ring, or any wearable that writes the night can land here. Once a night lands, ARIA can explain recovery and bedtime.",
                "Reconnect Apple Health"
            )
        }
    }

    static func lastNightEmpty(kind: SleepFeedKind) -> String {
        switch kind {
        case .notConnected:
            return "Connect Apple Health and last night will land here — stages from Watch, a ring, or any wearable that writes the night."
        case .connectedEmpty, .loading:
            return "Apple Health is connected. Last night will land here when a scored night arrives — in-bed on Tonight is a window, not a fake score."
        case .live:
            return ""
        }
    }

    static func statusCaption(kind: SleepFeedKind, labels: [String]) -> String {
        switch kind {
        case .loading:
            return "Pulling nights…"
        case .notConnected:
            return "Apple Health is off"
        case .connectedEmpty:
            return labels.isEmpty ? "Connected · waiting on a night" : labels.joined(separator: " · ") + " · waiting on a night"
        case .live:
            return labels.isEmpty ? "Last night is on this phone" : labels.joined(separator: " · ")
        }
    }

    static func liveDot(for kind: SleepFeedKind) -> SleepLiveDot {
        switch kind {
        case .loading: return .pulling
        case .notConnected: return .off
        case .connectedEmpty: return .waiting
        case .live: return .live
        }
    }
}

enum SleepLifestyleCopy {
    static let disclaimer = "Lifestyle coaching from your nights — not medical advice."
    static let dimRoomCue = "Lights and screens down. A bright kitchen keeps the day going."
    static let environmentHint = "Show ARIA the room — light and clutter are lifestyle cues, not a medical assessment."
}

extension AppStore {
    var sleepSurface: SleepSurfacePresence {
        SleepSurfacePresence.make(
            healthConnected: healthKitLive,
            isLoading: sleepData.isEmpty && (dataLoadState == .loading || isHealthKitPulling),
            hasScoredNight: !sleepData.isEmpty,
            metricSources: metricSources
        )
    }
}

// MARK: - Header / empty chrome

struct SleepStatusDot: View {
    let kind: SleepLiveDot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var color: Color {
        switch kind {
        case .off: return .textTertiary
        case .waiting: return .aurora
        case .pulling, .live: return .vitality
        }
    }

    private var accessibilityName: String {
        switch kind {
        case .off: return "Apple Health is off"
        case .waiting: return "Connected, waiting on a night"
        case .pulling: return "Pulling nights"
        case .live: return "Sleep data is live"
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(kind == .off ? 0 : 0.55), radius: 4)
            .opacity(kind == .pulling && !reduceMotion && pulse ? 0.4 : 1)
            .onAppear {
                guard kind == .pulling, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityLabel(accessibilityName)
    }
}

struct SleepSourceStrip: View {
    let presence: SleepSurfacePresence

    var body: some View {
        if !presence.sourceLabels.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presence.sourceLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sleep sources: \(presence.sourceLabels.joined(separator: ", "))")
        }
    }
}

struct SleepLifestyleCaption: View {
    var text: String = SleepLifestyleCopy.disclaimer

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }
}
