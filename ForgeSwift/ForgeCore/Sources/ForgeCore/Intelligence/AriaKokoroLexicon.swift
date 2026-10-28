import Foundation

/// Spoken expansions for ARIA coaching terms Misaki would otherwise mangle.
///
/// MisakiSwift is dictionary-plus-neural, Apache-2.0, and has no eSpeak path.
/// We still rewrite a small allowlisted set into words a US-English G2P already
/// knows, instead of leaving acronyms or Unicode subscripts in the line.
public enum AriaKokoroLexicon: Sendable {

    public struct Expansion: Equatable, Sendable {
        public var needle: String
        public var spoken: String
        public var caseInsensitive: Bool

        public init(_ needle: String, spoken: String, caseInsensitive: Bool = false) {
            self.needle = needle
            self.spoken = spoken
            self.caseInsensitive = caseInsensitive
        }
    }

    /// Longer needles first so `VO2 max` wins over `VO2`.
    public static let expansions: [Expansion] = [
        Expansion("VO₂ max", spoken: "V O 2 max"),
        Expansion("VO2 max", spoken: "V O 2 max", caseInsensitive: true),
        Expansion("VO2max", spoken: "V O 2 max", caseInsensitive: true),
        Expansion("VO₂", spoken: "V O 2"),
        Expansion("SpO₂", spoken: "spot O 2"),
        Expansion("SpO2", spoken: "spot O 2", caseInsensitive: true),
        Expansion("RMSSD", spoken: "R M S S D"),
        Expansion("HRV", spoken: "H R V"),
        Expansion("RHR", spoken: "resting heart rate"),
        Expansion("bpm", spoken: "beats per minute", caseInsensitive: true),
    ]

    public static func expand(_ text: String) -> String {
        var out = text
        for item in expansions {
            out = replace(item.needle, with: item.spoken, in: out, caseInsensitive: item.caseInsensitive)
        }
        return out
    }

    /// Sentence-sized pieces. A 30 s line on one Core ML bucket can peak past
    /// 1 GB; splitting on sentence punctuation keeps each inference small.
    public static func spokenSegments(
        in text: String,
        maxCharacters: Int = AriaKokoroDelivery.maxChunkCharacters
    ) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let expanded = expand(trimmed)
        let sentences = splitSentences(expanded)
        var chunks: [String] = []
        for sentence in sentences {
            if sentence.count <= maxCharacters {
                chunks.append(sentence)
                continue
            }
            chunks.append(contentsOf: splitLong(sentence, maxCharacters: maxCharacters))
        }
        return chunks.filter { !$0.isEmpty }
    }

    public static func splitSentences(_ text: String) -> [String] {
        let pattern = #"(?<=[.!?])\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return [text] }
        var parts: [String] = []
        var cursor = 0
        for match in matches {
            let piece = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { parts.append(piece) }
            cursor = match.range.location + match.range.length
        }
        let tail = ns.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        return parts.isEmpty ? [text] : parts
    }

    private static func splitLong(_ text: String, maxCharacters: Int) -> [String] {
        var remaining = text
        var out: [String] = []
        while remaining.count > maxCharacters {
            let idx = remaining.index(remaining.startIndex, offsetBy: maxCharacters)
            var cut = remaining[..<idx]
            if let comma = cut.lastIndex(of: ",") {
                cut = remaining[remaining.startIndex...comma]
            } else if let space = cut.lastIndex(of: " ") {
                cut = remaining[remaining.startIndex...space]
            }
            let piece = String(cut).trimmingCharacters(in: .whitespacesAndNewlines)
            if piece.isEmpty { break }
            out.append(piece)
            remaining = String(remaining[cut.endIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !remaining.isEmpty { out.append(remaining) }
        return out
    }

    private static func replace(
        _ needle: String,
        with spoken: String,
        in text: String,
        caseInsensitive: Bool
    ) -> String {
        guard !needle.isEmpty else { return text }
        if !caseInsensitive {
            return text.replacingOccurrences(of: needle, with: spoken)
        }
        var result = ""
        var rest = text[...]
        let needleLower = needle.lowercased()
        while let range = rest.range(of: needleLower, options: .caseInsensitive) {
            result += rest[rest.startIndex..<range.lowerBound]
            result += spoken
            rest = rest[range.upperBound...]
        }
        result += rest
        return result
    }
}
