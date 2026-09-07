import AVFoundation
import Observation
import SwiftUI
import UIKit

/// App-wide spoken mute. Missing key means muted — ARIA does not talk until
/// the user unmutes. Compact TTS reading every screen is the Hawking fail;
/// silence until they ask is the product.
enum AriaSpokenMute: Sendable {
    static let mutedKey = "aria.spoken.muted"

    /// When the key has never been written, she stays quiet.
    static var isMuted: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: mutedKey) == nil { return true }
            return defaults.bool(forKey: mutedKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: mutedKey)
        }
    }

    static var allowsSpeech: Bool { !isMuted }
}

/// Train how-to and gym cues share the same spoken mute as chat and onboarding.
enum AriaTrainVoice: Sendable {
    static let mutedKey = AriaSpokenMute.mutedKey

    static var isEnabled: Bool {
        get { AriaSpokenMute.allowsSpeech }
        set { AriaSpokenMute.isMuted = !newValue }
    }

    @MainActor
    static func speakHowTo(_ def: ExerciseDefinition) {
        guard isEnabled else { return }
        AriaPresence.shared.speak(ExerciseLibrary.howToScript(for: def))
    }
}

/// Picks ARIA's locked neural voice — Apple Zoe Premium when installed.
///
/// Compact Samantha spoken as chopped utterances is the “Stephen Hawking”
/// sound: formant TTS, no coarticulation, a fresh intonation contour on every
/// sentence. On-device she is Zoe (then Ava / Nicky / Allison premium, then
/// enhanced). No compact fallback: missing neural identity is silence.
enum AriaSpokenVoice: Sendable {

    enum QualityRank: Int, Sendable, Comparable {
        case standard = 1
        case enhanced = 2
        case premium = 3
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum GenderRank: String, Sendable {
        case female, male, unspecified
    }

    struct Candidate: Equatable, Sendable {
        var identifier: String
        var name: String
        var language: String
        var quality: QualityRank
        var gender: GenderRank
    }

    /// Default rate. Slowing compact TTS below this is what made her sound
    /// assistive / DECtalk. Neural voices already speak conversationally here.
    static let rate: Float = AVSpeechUtteranceDefaultSpeechRate
    static let pitch: Float = 1.0
    static let volume: Float = 1.0
    static let firstPhraseDelay: TimeInterval = 0
    static let betweenPhraseDelay: TimeInterval = 0
    static let phraseTailDelay: TimeInterval = 0

    /// `AVSpeechSynthesisVoice(language:)` ignores the Accessibility voice on
    /// current iOS and returns compact Samantha. Never use it.
    static let allowsLanguageConstructorFallback = false

    /// Locked spoken identity. Chat, onboarding, and Train resolve to this
    /// identifier when it is installed — not whichever neural scored highest.
    static let lockedIdentifier = "com.apple.voice.premium.en-US.Zoe"

    /// Installed identifiers we try, in order. Unknown ids silently resolve
    /// to Samantha — callers must require an identifier match.
    static let preferredNeuralIdentifiers = [
        lockedIdentifier,
        "com.apple.voice.premium.en-US.Ava",
        "com.apple.voice.premium.en-US.Nicky",
        "com.apple.voice.premium.en-US.Allison",
        "com.apple.voice.enhanced.en-US.Zoe",
        "com.apple.voice.enhanced.en-US.Ava",
        "com.apple.voice.enhanced.en-US.Nicky",
        "com.apple.voice.enhanced.en-US.Allison",
    ]

    private static let noveltyTokens = [
        "siri", "novelty", "bells", "cellos", "organ", "pipes", "zarvox",
        "trinoids", "boing", "bubbles", "wobbles", "jester", "superstar",
        "junior", "kathy", "bad news", "good news", "whisper", "albert",
        "bahh", "foxtrot", "grandma", "grandpa", "reed", "rocko", "sandy",
        "sheldon", "flo", "edna", "eloquence", "fred", "ralph",
    ]

    private static let preferredNames = [
        "zoe", "ava", "nicky", "allison",
    ]

    static func isSiri(_ candidate: Candidate) -> Bool {
        let blob = "\(candidate.identifier) \(candidate.name)".lowercased()
        return blob.contains("siri")
    }

    static func isNovelty(_ candidate: Candidate) -> Bool {
        let blob = "\(candidate.identifier) \(candidate.name)".lowercased()
        return noveltyTokens.contains { blob.contains($0) }
    }

    static func isEnglish(_ candidate: Candidate) -> Bool {
        candidate.language.lowercased().hasPrefix("en")
    }

    static func isNeural(_ candidate: Candidate) -> Bool {
        if candidate.quality == .premium || candidate.quality == .enhanced { return true }
        let id = candidate.identifier.lowercased()
        return id.contains(".premium.") || id.contains(".enhanced.")
    }

    /// Compact formant voices (Samantha, Alex). Never spoken. Missing neural
    /// identity is silence plus the download prompt — not a computer voice.
    static func isCompactFormant(_ candidate: Candidate) -> Bool {
        let blob = "\(candidate.identifier) \(candidate.name)".lowercased()
        if blob.contains("compact") { return true }
        if blob.contains("samantha") && !isNeural(candidate) { return true }
        return candidate.quality == .standard && !isNeural(candidate)
    }

    static func isLockedFamily(_ candidate: Candidate) -> Bool {
        preferredNeuralIdentifiers.contains(candidate.identifier)
            && isNeural(candidate)
            && !isSiri(candidate)
            && !isNovelty(candidate)
    }

    /// True only when the requested neural id is actually installed and the
    /// synthesizer did not silently substitute compact Samantha.
    static func shouldSpeak(
        requestedId: String,
        catalogIds: Set<String>,
        resolvedId: String
    ) -> Bool {
        catalogIds.contains(requestedId) && resolvedId == requestedId
    }

    static func score(_ candidate: Candidate) -> Int {
        if isSiri(candidate) || isNovelty(candidate) { return -1_000_000 }
        if isCompactFormant(candidate) { return -1_000_000 }
        var points = 0
        let lang = candidate.language.lowercased()
        if lang == "en-us" || lang.hasPrefix("en-us") { points += 40 }
        else if lang.hasPrefix("en") { points += 8 }

        switch candidate.quality {
        case .premium: points += 400
        case .enhanced: points += 200
        case .standard: points += 0
        }

        if candidate.gender == .female { points += 12 }
        else if candidate.gender == .male { points += 2 }

        let blob = "\(candidate.identifier) \(candidate.name)".lowercased()
        for (index, token) in preferredNames.enumerated() {
            if blob.contains(token) {
                points += 40 - index
                break
            }
        }
        if candidate.identifier == lockedIdentifier { points += 80 }
        return points
    }

    /// First matching locked-family identifier, in `preferredNeuralIdentifiers`
    /// order. Compact catalogs return nil — never Samantha.
    static func pick(from candidates: [Candidate]) -> Candidate? {
        let byId = Dictionary(candidates.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for identifier in preferredNeuralIdentifiers {
            guard let candidate = byId[identifier], isLockedFamily(candidate) else { continue }
            return candidate
        }
        return nil
    }

    static func candidate(from voice: AVSpeechSynthesisVoice) -> Candidate {
        let quality: QualityRank
        switch voice.quality {
        case .premium: quality = .premium
        case .enhanced: quality = .enhanced
        default: quality = .standard
        }
        let gender: GenderRank
        switch voice.gender {
        case .female: gender = .female
        case .male: gender = .male
        default: gender = .unspecified
        }
        return Candidate(
            identifier: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: quality,
            gender: gender
        )
    }

    static func preferredVoice(
        from voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> AVSpeechSynthesisVoice? {
        resolveNamedNeural(from: voices)
    }

    static func hasInstalledIdentity(
        from voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()
    ) -> Bool {
        preferredVoice(from: voices) != nil
    }

    static func resolveNamedNeural(from catalog: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        let catalogIds = Set(catalog.map(\.identifier))
        for requested in preferredNeuralIdentifiers {
            guard let voice = acceptedVoice(requestedId: requested, from: catalog) else { continue }
            let cand = candidate(from: voice)
            guard shouldSpeak(
                requestedId: requested,
                catalogIds: catalogIds,
                resolvedId: voice.identifier
            ), isLockedFamily(cand) else { continue }
            return voice
        }
        return nil
    }

    /// Instantiates by identifier only if that exact id is in the catalog.
    /// `AVSpeechSynthesisVoice(identifier:)` returns Samantha for unknown ids.
    static func acceptedVoice(
        requestedId: String,
        from catalog: [AVSpeechSynthesisVoice]
    ) -> AVSpeechSynthesisVoice? {
        let catalogIds = Set(catalog.map(\.identifier))
        guard catalogIds.contains(requestedId) else { return nil }
        guard let voice = AVSpeechSynthesisVoice(identifier: requestedId) else { return nil }
        guard shouldSpeak(
            requestedId: requestedId,
            catalogIds: catalogIds,
            resolvedId: voice.identifier
        ) else { return nil }
        return voice
    }
}

/// When to show the Zoe-download sheet. Pure so tests do not spin UI.
enum AriaNeuralVoicePromptPolicy: Sendable {
    static let promptedKey = "aria.spoken.neuralVoicePromptShown"
    static let title = "ARIA's voice"
    static let body = "She speaks with Apple's Zoe — a neural voice, one line, not the compact computer voice."
    static let settingsPath = "Settings → Accessibility → Spoken Content → Voices → English → Zoe (Premium)"
    static let actionTitle = "Got it"

    static func shouldPresent(hasNeuralIdentity: Bool, alreadyPrompted: Bool) -> Bool {
        !hasNeuralIdentity && !alreadyPrompted
    }
}

/// First-run prompt when voice mode is used without a neural identity.
/// Re-checks the catalog on foreground so a just-downloaded Zoe starts working.
@MainActor
@Observable
final class AriaNeuralVoiceGate {
    static let shared = AriaNeuralVoiceGate()

    var showPrompt = false
    private(set) var hasNeuralIdentity = false

    private init() {
        refreshCatalog()
    }

    func refreshCatalog() {
        hasNeuralIdentity = AriaSpokenVoice.hasInstalledIdentity()
        if hasNeuralIdentity {
            showPrompt = false
        }
    }

    func requestPromptIfNeeded(defaults: UserDefaults = .standard) {
        refreshCatalog()
        let already = defaults.bool(forKey: AriaNeuralVoicePromptPolicy.promptedKey)
        guard AriaNeuralVoicePromptPolicy.shouldPresent(
            hasNeuralIdentity: hasNeuralIdentity,
            alreadyPrompted: already
        ) else { return }
        defaults.set(true, forKey: AriaNeuralVoicePromptPolicy.promptedKey)
        showPrompt = true
    }

    func dismiss() {
        showPrompt = false
        refreshCatalog()
    }
}

struct AriaNeuralVoiceSheet: View {
    @Bindable var gate: AriaNeuralVoiceGate

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(AriaNeuralVoicePromptPolicy.body)
                    .font(FDS.TypeScale.body(16))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AriaNeuralVoicePromptPolicy.settingsPath)
                    .font(FDS.TypeScale.body(14))
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Spacer()

                Button {
                    FDS.haptic(.light)
                    gate.dismiss()
                } label: {
                    Text(AriaNeuralVoicePromptPolicy.actionTitle)
                        .font(FDS.TypeScale.label(16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.ember, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .navigationTitle(AriaNeuralVoicePromptPolicy.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

extension AriaSpeechPrep {

    /// One spoken line. Em-dashes become commas so the neural engine can
    /// contour a single utterance instead of resetting at every breath.
    static func spokenLine(in text: String) -> String? {
        guard let clipped = clipped(text) else { return nil }
        var line = clipped
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "—", with: ", ")
            .replacingOccurrences(of: "–", with: ", ")
        while line.contains("  ") {
            line = line.replacingOccurrences(of: "  ", with: " ")
        }
        line = line.replacingOccurrences(of: " ,", with: ",")
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Always zero or one element. Kept so existing call sites/tests share
    /// the “do not chop this into Hawking packets” rule.
    static func phrases(in text: String) -> [String] {
        spokenLine(in: text).map { [$0] } ?? []
    }

    /// Speak only when there is a line *and* a neural identity. Compact
    /// fallback is never a reason to enqueue.
    static func canSpeak(text: String, hasNeuralIdentity: Bool) -> Bool {
        spokenLine(in: text) != nil && hasNeuralIdentity
    }

    static func utterances(from text: String, voiceOver: Bool) -> [AVSpeechUtterance] {
        guard let line = spokenLine(in: text) else { return [] }
        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = AriaSpokenVoice.preferredVoice()
        if voiceOver {
            utterance.prefersAssistiveTechnologySettings = true
        } else {
            utterance.rate = AriaSpokenVoice.rate
            utterance.pitchMultiplier = AriaSpokenVoice.pitch
            utterance.volume = AriaSpokenVoice.volume
        }
        utterance.preUtteranceDelay = AriaSpokenVoice.firstPhraseDelay
        utterance.postUtteranceDelay = AriaSpokenVoice.phraseTailDelay
        return [utterance]
    }

    /// Queue a single neural utterance. Returns false when there is nothing
    /// to say, or when no locked neural voice is installed.
    @MainActor
    static func enqueue(
        _ text: String,
        on synthesizer: AVSpeechSynthesizer,
        interrupt: Bool,
        stopAt boundary: AVSpeechBoundary = .immediate,
        session: ForgePlaybackSession = .spoken
    ) -> Bool {
        guard AriaSpokenMute.allowsSpeech else { return false }
        guard canSpeak(text: text, hasNeuralIdentity: AriaSpokenVoice.hasInstalledIdentity()) else {
            return false
        }
        let voiceOver = UIAccessibility.isVoiceOverRunning
        let utts = utterances(from: text, voiceOver: voiceOver)
        guard !utts.isEmpty, utts.contains(where: { $0.voice != nil }) else { return false }
        if interrupt, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: boundary)
        }
        try? session.activate()
        for utterance in utts {
            synthesizer.speak(utterance)
        }
        return true
    }
}
