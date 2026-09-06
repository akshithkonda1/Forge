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

/// Picks a neural, non-Siri English voice and scores candidates so tests can
/// lock the “not Siri 2.0” rule without spinning the synthesizer.
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

    /// Slightly under default 0.5 — unhurried, not a compact-Siri clip.
    static let rate: Float = 0.47
    static let pitch: Float = 1.03
    static let volume: Float = 0.90
    static let firstPhraseDelay: TimeInterval = 0.06
    static let betweenPhraseDelay: TimeInterval = 0.18
    static let phraseTailDelay: TimeInterval = 0.10

    private static let noveltyTokens = [
        "siri", "novelty", "bells", "cellos", "organ", "pipes", "zarvox",
        "trinoids", "boing", "bubbles", "wobbles", "jester", "superstar",
        "junior", "kathy", "bad news", "good news", "whisper", "albert",
        "bahh", "foxtrot", "grandma", "grandpa", "reed", "rocko", "sandy",
        "sheldon", "flo", "edna", "cellos", "bells",
    ]

    /// Preferred natural female voices, in order. Never Siri-bundle ids.
    private static let preferredNames = [
        "zoe", "nicky", "ava", "allison", "stephanie", "susan", "sally",
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

    static func score(_ candidate: Candidate) -> Int {
        if isSiri(candidate) || isNovelty(candidate) { return -1_000_000 }
        var points = 0
        let lang = candidate.language.lowercased()
        if lang == "en-us" || lang.hasPrefix("en-us") { points += 40 }
        else if lang.hasPrefix("en-gb") { points += 18 }
        else if lang.hasPrefix("en") { points += 12 }

        switch candidate.quality {
        case .premium: points += 100
        case .enhanced: points += 60
        case .standard: points += 8
        }

        if candidate.gender == .female { points += 12 }
        else if candidate.gender == .male { points += 2 }

        let blob = "\(candidate.identifier) \(candidate.name)".lowercased()
        for (index, token) in preferredNames.enumerated() {
            if blob.contains(token) {
                points += 28 - index
                break
            }
        }
        // Compact Samantha is the default Siri-adjacent voice. Keep her last.
        if blob.contains("samantha") { points -= 20 }
        return points
    }

    static func pick(from candidates: [Candidate]) -> Candidate? {
        candidates
            .filter { isEnglish($0) && !isSiri($0) && !isNovelty($0) }
            .max { score($0) < score($1) }
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
        let picked = pick(from: voices.map(candidate(from:)))
        if let picked, let voice = AVSpeechSynthesisVoice(identifier: picked.identifier) {
            return voice
        }
        // Last resort — language voice, still never a Siri identifier we selected.
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension AriaSpeechPrep {

    /// Break a line into spoken breaths. Em-dashes and sentence ends become
    /// pauses, which is how a person talks — not one compressed Siri blob.
    static func phrases(in text: String) -> [String] {
        guard let clipped = clipped(text) else { return [] }
        let normalized = clipped
            .replacingOccurrences(of: "—", with: " — ")
            .replacingOccurrences(of: "–", with: " — ")
            .replacingOccurrences(of: "\n", with: " ")
        var parts: [String] = []
        var current = ""
        let chars = Array(normalized)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            current.append(ch)
            if ch == "—" {
                let trimmed = current
                    .replacingOccurrences(of: "—", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
                current = ""
                i += 1
                continue
            }
            let isStop = ch == "." || ch == "?" || ch == "!"
            if isStop && !isDecimalPoint(chars, index: i) {
                let nextIsBoundary = i + 1 >= chars.count || chars[i + 1].isWhitespace
                if nextIsBoundary {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { parts.append(trimmed) }
                    current = ""
                    while i + 1 < chars.count && chars[i + 1].isWhitespace { i += 1 }
                }
            }
            i += 1
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        return mergeTinyPhrases(parts)
    }

    static func utterances(from text: String, voiceOver: Bool) -> [AVSpeechUtterance] {
        let chunks = phrases(in: text)
        guard !chunks.isEmpty else { return [] }
        let voice = AriaSpokenVoice.preferredVoice()
        return chunks.enumerated().map { index, phrase in
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = voice
            if voiceOver {
                utterance.prefersAssistiveTechnologySettings = true
            } else {
                utterance.rate = AriaSpokenVoice.rate
                utterance.pitchMultiplier = AriaSpokenVoice.pitch
                utterance.volume = AriaSpokenVoice.volume
            }
            utterance.preUtteranceDelay = index == 0
                ? AriaSpokenVoice.firstPhraseDelay
                : AriaSpokenVoice.betweenPhraseDelay
            utterance.postUtteranceDelay = AriaSpokenVoice.phraseTailDelay
            return utterance
        }
    }

    /// Queue human-paced utterances on a synthesizer. Returns false when there
    /// is nothing to say (empty / whitespace).
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

    private static func isDecimalPoint(_ chars: [Character], index: Int) -> Bool {
        guard chars[index] == ".", index > 0, index + 1 < chars.count else { return false }
        return chars[index - 1].isNumber && chars[index + 1].isNumber
    }

    /// Glue tiny fragments ("Ok.") onto the next breath so we don't over-pause.
    private static func mergeTinyPhrases(_ parts: [String]) -> [String] {
        guard parts.count > 1 else { return parts }
        var merged: [String] = []
        var i = 0
        while i < parts.count {
            var piece = parts[i]
            while piece.count < 12, i + 1 < parts.count {
                i += 1
                piece = "\(piece) \(parts[i])"
            }
            merged.append(piece)
            i += 1
        }
        return merged
    }
}
