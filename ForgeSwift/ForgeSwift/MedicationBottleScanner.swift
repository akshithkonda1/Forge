import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Vision)
import Vision
#endif

/// On-device bottle read. Vision OCR stays on this iPhone. The photo is not saved
/// and never leaves the device. Only a catalog name is admitted — never a dose.
struct MedicationBottleScan: Sendable, Equatable {
    var rawText: String
    var tokensUsed: [String]
    var admitted: FDAMedication?
    var candidates: [FDAMedication]

    var headline: String {
        guard let admitted else {
            return candidates.isEmpty
                ? "No catalog match on that label. Try the brand or generic in search."
                : "Found possible matches. Pick one to admit."
        }
        return "Admitted \(admitted.bothNames) · \(admitted.archetype) · \(admitted.disease). ARIA can pull this. It never prescribes and never names a dose."
    }
}

enum MedicationBottleScanner {
    /// Testable path: turn label text into a catalog admit. No photo. No dose.
    static func match(ocrText: String) -> MedicationBottleScan {
        let tokens = extractTokens(ocrText)
        var scored: [String: (FDAMedication, Int)] = [:]
        for token in tokens {
            guard MedicationPharmacy.isReady else { break }
            let page = MedicationPharmacy.search(token, sort: .relevance, limit: 5)
            for hit in page.items {
                guard wholeWordMatch(hit, token) else { continue }
                let next = score(hit, token: token)
                if let current = scored[hit.id], current.1 >= next { continue }
                scored[hit.id] = (hit, next)
            }
        }
        let best = scored.values.sorted { $0.1 > $1.1 }
        let ranked = best.map(\.0)
        let admitted = best.first.flatMap { $0.1 >= 70 ? $0.0 : nil }
        return MedicationBottleScan(
            rawText: ocrText,
            tokensUsed: tokens,
            admitted: admitted,
            candidates: Array(ranked.prefix(6))
        )
    }

#if canImport(UIKit) && canImport(Vision)
    static func readText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if error != nil {
                    continuation.resume(returning: "")
                    return
                }
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
#endif

    private static func extractTokens(_ text: String) -> [String] {
        let parts = text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        var tokens: [String] = []
        var index = 0
        while index < parts.count {
            let part = parts[index]
            let lower = part.lowercased()
            if index + 1 < parts.count {
                let next = parts[index + 1].uppercased()
                if suffixMarkers.contains(next), part.count >= 4, !isNoise(lower) {
                    tokens.append("\(part) \(parts[index + 1])")
                    index += 2
                    continue
                }
            }
            if !isNoise(lower) { tokens.append(part) }
            index += 1
        }
        return Array(Set(tokens)).sorted { $0.count > $1.count }
    }

    private static func isNoise(_ token: String) -> Bool {
        if token.count < 4 { return true }
        if token.allSatisfy(\.isNumber) { return true }
        if doseUnits.contains(token) { return true }
        if labelNoise.contains(token) { return true }
        return false
    }

    private static func wholeWordMatch(_ hit: FDAMedication, _ token: String) -> Bool {
        let needle = token.lowercased()
        return [hit.brand, hit.generic, hit.name].compactMap { $0 }.contains { field in
            field.split { !$0.isLetter && !$0.isNumber }.contains {
                $0.lowercased() == needle || field.lowercased() == needle
            } || field.lowercased() == needle
        }
    }

    private static func score(_ hit: FDAMedication, token: String) -> Int {
        let q = token.lowercased()
        if hit.brand?.lowercased() == q { return 100 }
        if hit.generic.lowercased() == q { return 90 }
        if hit.brand?.lowercased().split(separator: " ").contains(where: { $0.lowercased() == q }) == true {
            return 85
        }
        if hit.generic.lowercased().split(separator: " ").contains(where: { $0 == q }) { return 80 }
        if hit.brand?.lowercased().contains(q) == true { return 70 }
        if hit.generic.lowercased().contains(q) { return 65 }
        return 0
    }

    private static let suffixMarkers: Set<String> = ["XR", "XL", "ER", "CR", "SR", "IR", "DR", "LA", "ODT"]

    private static let doseUnits: Set<String> = [
        "mg", "mcg", "ug", "ml", "iu", "meq", "g", "kg", "mm", "cm",
    ]

    private static let labelNoise: Set<String> = [
        "only", "tablet", "tablets", "capsule", "capsules", "oral", "film",
        "coated", "extended", "release", "delayed", "usp", "ndc", "qty",
        "quantity", "take", "daily", "twice", "once", "store", "keep",
        "child", "children", "resistant", "pharmacist", "prescription",
        "generic", "with", "this", "that", "from", "each", "every",
        "about", "after", "before", "reach", "room", "temperature",
        "protect", "light", "moisture", "dispense", "original", "container",
        "caution", "federal", "law", "prohibits", "transfer", "another",
        "person", "doctor", "physician", "refill", "refills", "exp",
        "expiry", "lot", "batch", "manufactured", "distributed", "for",
        "the", "and", "use", "as", "directed", "swallow", "whole",
        "do", "not", "crush", "chew", "split", "food", "water",
    ]
}
