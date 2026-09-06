import AVFoundation
import UIKit

/// Train-only mute. Chat and onboarding keep talking; the gym floor can go quiet.
enum AriaTrainVoice: Sendable {
    static let mutedKey = "aria.train.voiceMuted"

    static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(!newValue, forKey: mutedKey) }
    }

    @MainActor
    static func speakHowTo(_ def: ExerciseDefinition) {
        guard isEnabled else { return }
        AriaPresence.shared.speak(ExerciseLibrary.howToScript(for: def))
    }
}

/// Picks a neural, non-Siri English voice.
///
/// Compact Samantha spoken as chopped utterances is the “Stephen Hawking”
/// sound: formant TTS, no coarticulation, a fresh intonation contour on every
/// sentence. Claude and Grok use cloud neural TTS. On-device the equivalent is
/// Apple premium/enhanced voices (Zoe, Ava, Nicky, Allison) spoken as **one**
/// utterance so the engine can contour the whole line.
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

    /// Installed identifiers we try first, in order. Unknown ids silently
    /// resolve to Samantha — callers must require an identifier match.
    static let preferredNeuralIdentifiers = [
        "com.apple.voice.premium.en-US.Zoe",
        "com.apple.voice.premium.en-US.Ava",
        "com.apple.voice.premium.en-US.Nicky",
        "com.apple.voice.premium.en-US.Allison",
        "com.apple.voice.enhanced.en-US.Zoe",
        "com.apple.voice.enhanced.en-US.Ava",
        "com.apple.voice.enhanced.en-US.Nicky",
        "com.apple.voice.enhanced.en-US.Allison",
        "com.apple.voice.premium.en-GB.Serena",
        "com.apple.voice.enhanced.en-GB.Serena",
    ]

    private static let noveltyTokens = [
        "siri", "novelty", "bells", "cellos", "organ", "pipes", "zarvox",
        "trinoids", "boing", "bubbles", "wobbles", "jester", "superstar",
        "junior", "kathy", "bad news", "good news", "whisper", "albert",
        "bahh", "foxtrot", "grandma", "grandpa", "reed", "rocko", "sandy",
        "sheldon", "flo", "edna", "eloquence", "fred", "ralph",
    ]

    private static let preferredNames = [
        "zoe", "ava", "nicky", "allison", "stephanie", "susan", "sally",
        "emily", "joelle", "serena", "kate", "martha",
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

    /// Compact formant voices (Samantha, Alex). Fine as a last resort when the
    /// user has not downloaded a neural voice; never preferred over one.
    static func isCompactFormant(_ candidate: Candidate) -> Bool {
        let blob = "\(candidate.identifier) \(candidate.name)".lowercased()
        if blob.contains("compact") { return true }
        if blob.contains("samantha") && !isNeural(candidate) { return true }
        return candidate.quality == .standard && !isNeural(candidate)
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
        var points = 0
        let lang = candidate.language.lowercased()
        if lang == "en-us" || lang.hasPrefix("en-us") { points += 40 }
        else if lang.hasPrefix("en-gb") { points += 18 }
        else if lang.hasPrefix("en") { points += 12 }

        switch candidate.quality {
        case .premium: points += 400
        case .enhanced: points += 200
        case .standard: points += 8
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
        if isCompactFormant(candidate) { points -= 120 }
        if blob.contains("samantha") { points -= 40 }
        return points
    }

    static func pick(from candidates: [Candidate]) -> Candidate? {
        let human = candidates.filter { isEnglish($0) && !isSiri($0) && !isNovelty($0) }
        let neural = human.filter(isNeural)
        let pool = neural.isEmpty ? human : neural
        return pool.max { score($0) < score($1) }
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
        if let named = resolveNamedNeural(from: voices) {
            return named
        }
        if let picked = pick(from: voices.map(candidate(from:))),
           let voice = acceptedVoice(requestedId: picked.identifier, from: voices) {
            return voice
        }
        return voices.first { voice in
            let cand = candidate(from: voice)
            return isEnglish(cand) && !isSiri(cand) && !isNovelty(cand)
        } ?? voices.first { voice in
            let cand = candidate(from: voice)
            return isEnglish(cand) && !isSiri(cand)
        }
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
            ), !isSiri(cand), !isNovelty(cand) else { continue }
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

    /// Queue a single neural utterance. Returns false when there is nothing to say.
    @MainActor
    static func enqueue(
        _ text: String,
        on synthesizer: AVSpeechSynthesizer,
        interrupt: Bool,
        stopAt boundary: AVSpeechBoundary = .immediate
    ) -> Bool {
        let voiceOver = UIAccessibility.isVoiceOverRunning
        let utts = utterances(from: text, voiceOver: voiceOver)
        guard !utts.isEmpty else { return false }
        if interrupt, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: boundary)
        }
        try? ForgePlaybackSession.spoken.activate()
        for utterance in utts {
            synthesizer.speak(utterance)
        }
        return true
    }
}
