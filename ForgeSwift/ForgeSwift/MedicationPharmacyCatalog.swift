import Compression
import Foundation
import os

/// One federal-list presentation. Names only — not a prescription, not PHI.
struct FDAMedication: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var generic: String
    var brand: String?
    var form: String
    var strength: String
    var therapeuticClass: String
    var archetype: String
    var disease: String

    var brandOrGeneric: String { brand?.isEmpty == false ? brand! : generic }

    var bothNames: String {
        if let brand, !brand.isEmpty, brand.caseInsensitiveCompare(generic) != .orderedSame {
            return "\(brand) · \(generic)"
        }
        return generic
    }
}

enum PharmacySort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case archetype
    case disease
    case name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevance: return "Match"
        case .archetype: return "Archetype"
        case .disease: return "Disease"
        case .name: return "Name"
        }
    }
}

struct PharmacyGroup: Identifiable, Sendable {
    var id: String { title }
    var title: String
    var items: [FDAMedication]
}

struct PharmacySearchPage: Sendable {
    var items: [FDAMedication]
    var total: Int
    var groups: [PharmacyGroup]
}

/// On-device pharmacy. Loads off the main thread so opening Medicine cannot
/// watchdog-kill the app. Search hits brand, generic, archetype, and disease.
enum MedicationPharmacy {
    static let minimumCount = 10_000
    /// Honest Show all cap so a 50k browse does not mount every row.
    static let showAllLimit = 1_000
    private static let extrasKey = "forge.pharmacy.openfda.v3"
    private static let extrasAtKey = "forge.pharmacy.openfda.at.v3"
    private static let savedKey = "forge.pharmacy.saved.v1"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let catalogResource = "fda_pharmacy_catalog"
    private static let reservedWords: Set<String> = ["AND", "OR", "OF", "FOR", "WITH", "THE", "IN", "TO"]
    private static let keepUpper: Set<String> = ["XR", "XL", "ER", "CR", "SR", "IR", "DR", "LA", "ODT", "EC", "HCL", "HBR"]

    private static let lock = OSAllocatedUnfairLock()
    private static var cached: [FDAMedication]?
    private static var sortedTokens: [String] = []
    private static var tokenRows: [String: [Int]] = [:]
    private static var ready = false
    /// Why the last bundled load succeeded or fell back to seeds. Tests
    /// surface this when the federal catalog does not come back.
    static var loadDiagnostics = ""

    static var isReady: Bool {
        lock.withLock { ready }
    }

    static var count: Int { snapshot().count }

    /// Decompress and index off the caller. The Medicine page must await this
    /// before it reads the catalog — doing that work in a view body is what
    /// was crashing the flow.
    static func prepare() async {
        await Task.detached(priority: .userInitiated) {
            _ = snapshot()
        }.value
    }

    static func all() -> [FDAMedication] { snapshot() }

    static func search(
        _ query: String,
        sort: PharmacySort = .relevance,
        limit: Int = 40,
        offset: Int = 0,
        archetype: String? = nil,
        disease: String? = nil
    ) -> PharmacySearchPage {
        let catalog = snapshot()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var hits: [FDAMedication]
        if q.isEmpty {
            hits = catalog
        } else {
            hits = rankedHits(query: q, catalog: catalog)
        }
        if let archetype, !archetype.isEmpty {
            hits = hits.filter { $0.archetype == archetype }
        }
        if let disease, !disease.isEmpty {
            hits = hits.filter { $0.disease == disease }
        }
        let total = hits.count
        let sorted = sortHits(hits, sort: sort, query: q)
        let page = Array(sorted.dropFirst(min(offset, sorted.count)).prefix(limit))
        return PharmacySearchPage(
            items: uniqued(page),
            total: total,
            groups: grouped(uniqued(page), sort: sort)
        )
    }

    static func archetypeCounts() -> [(String, Int)] {
        counts(snapshot().map(\.archetype))
    }

    static func diseaseCounts(in archetype: String? = nil) -> [(String, Int)] {
        let rows = snapshot().filter { archetype == nil || $0.archetype == archetype }
        return counts(rows.map(\.disease))
    }

    static func savedNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: savedKey) ?? []
    }

    static func toggleSaved(name: String) {
        var names = savedNames()
        if let i = names.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.remove(at: i)
        } else {
            names.insert(name, at: 0)
        }
        UserDefaults.standard.set(Array(names.prefix(40)), forKey: savedKey)
    }

    /// Instant admit — add without toggling off if it's already on the list.
    static func ensureSaved(name: String) {
        var names = savedNames()
        if names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return }
        names.insert(name, at: 0)
        UserDefaults.standard.set(Array(names.prefix(40)), forKey: savedKey)
    }

    static func lastRefreshLabel() -> String {
        guard let at = UserDefaults.standard.object(forKey: extrasAtKey) as? Date else {
            return "FDA · CDC · CMS NDC · sorted by archetype and disease"
        }
        return "Updated " + at.formatted(date: .abbreviated, time: .shortened)
    }

    static func refreshFromOpenFDAIfDue() async {
        if let at = UserDefaults.standard.object(forKey: extrasAtKey) as? Date,
           Date().timeIntervalSince(at) < refreshInterval {
            return
        }
        var extras: [FDAMedication] = []
        var seen = Set<String>()
        for endpoint in ["drugsfda", "ndc"] {
            for skip in stride(from: 0, to: 5_000, by: 1_000) {
                guard let page = await fetchOpenFDAPage(endpoint: endpoint, skip: skip) else { break }
                if page.isEmpty { break }
                for row in page where seen.insert(row.id).inserted {
                    extras.append(classify(row))
                }
            }
        }
        guard extras.count >= 20 else { return }
        if let encoded = try? JSONEncoder().encode(Array(extras.prefix(8_000))) {
            UserDefaults.standard.set(encoded, forKey: extrasKey)
            UserDefaults.standard.set(Date(), forKey: extrasAtKey)
        }
        lock.withLock {
            cached = nil
            ready = false
        }
        _ = snapshot()
    }

    // MARK: - Snapshot

    private static func snapshot() -> [FDAMedication] {
        if let hit = lock.withLock({ cached.flatMap { ready ? $0 : nil } }) {
            return hit
        }

        var rows = loadBundledCatalog()
        rows.append(contentsOf: loadExtras())
        var seen = Set<String>()
        rows = rows.compactMap { row -> FDAMedication? in
            var next = classify(row)
            if next.id.isEmpty { next.id = fallbackID(next) }
            guard seen.insert(next.id).inserted else { return nil }
            return next
        }
        rows.sort {
            if $0.archetype != $1.archetype {
                return $0.archetype.localizedCaseInsensitiveCompare($1.archetype) == .orderedAscending
            }
            if $0.disease != $1.disease {
                return $0.disease.localizedCaseInsensitiveCompare($1.disease) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let catalog = rows
        let tokens = buildIndex(catalog)

        lock.withLock {
            cached = catalog
            sortedTokens = tokens.sorted
            tokenRows = tokens.map
            ready = true
        }
        return catalog
    }

    private static func buildIndex(_ rows: [FDAMedication]) -> (sorted: [String], map: [String: [Int]]) {
        var map: [String: [Int]] = [:]
        map.reserveCapacity(rows.count * 4)
        for (index, row) in rows.enumerated() {
            for token in searchTokens(row) {
                map[token, default: []].append(index)
            }
        }
        return (map.keys.sorted(), map)
    }

    private static func searchTokens(_ row: FDAMedication) -> Set<String> {
        var tokens = Set<String>()
        let fields = [row.name, row.generic, row.brand ?? "", row.form, row.strength, row.archetype, row.disease, row.therapeuticClass]
        for field in fields {
            for token in tokenize(field) {
                tokens.insert(token)
            }
        }
        return tokens
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private static func rankedHits(query: String, catalog: [FDAMedication]) -> [FDAMedication] {
        let q = query.lowercased()
        let queryTokens = tokenize(q)
        guard !queryTokens.isEmpty else { return [] }

        let (tokenList, map) = lock.withLock { (sortedTokens, tokenRows) }

        var scores: [Int: Int] = [:]
        for token in queryTokens {
            var union = Set<Int>()
            for key in tokens(startingWith: token, in: tokenList) {
                for row in map[key] ?? [] { union.insert(row) }
            }
            if union.isEmpty { return [] }
            if scores.isEmpty {
                for row in union { scores[row] = 1 }
            } else {
                scores = scores.filter { union.contains($0.key) }
                if scores.isEmpty { return [] }
            }
        }

        var ranked: [(FDAMedication, Int)] = []
        ranked.reserveCapacity(scores.count)
        for (index, _) in scores {
            guard catalog.indices.contains(index) else { continue }
            let row = catalog[index]
            ranked.append((row, relevance(row, query: q, tokens: queryTokens)))
        }
        ranked.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
        }
        return ranked.map(\.0)
    }

    private static func tokens(startingWith prefix: String, in sorted: [String]) -> [String] {
        guard !prefix.isEmpty, !sorted.isEmpty else { return [] }
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < prefix { low = mid + 1 } else { high = mid }
        }
        var hits: [String] = []
        var i = low
        while i < sorted.count, sorted[i].hasPrefix(prefix) {
            hits.append(sorted[i])
            i += 1
        }
        return hits
    }

    private static func relevance(_ row: FDAMedication, query: String, tokens: [String]) -> Int {
        let brand = (row.brand ?? "").lowercased()
        let generic = row.generic.lowercased()
        let name = row.name.lowercased()
        let disease = row.disease.lowercased()
        let archetype = row.archetype.lowercased()
        var score = 0
        if brand == query { score += 800 }
        else if brand.hasPrefix(query) { score += 500 }
        if generic == query { score += 700 }
        else if generic.hasPrefix(query) { score += 450 }
        if name.hasPrefix(query) { score += 200 }
        if disease == query || disease.hasPrefix(query) { score += 300 }
        if archetype == query || archetype.hasPrefix(query) { score += 220 }
        for token in tokens {
            if brand == token { score += 80 }
            if generic.split(whereSeparator: { $0 == " " || $0 == "/" }).contains(where: { $0 == token }) { score += 70 }
            if disease.contains(token) { score += 40 }
            if archetype.contains(token) { score += 30 }
        }
        return score
    }

    private static func sortHits(_ hits: [FDAMedication], sort: PharmacySort, query: String) -> [FDAMedication] {
        switch sort {
        case .relevance:
            return hits
        case .name:
            return hits.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .archetype:
            return hits.sorted {
                if $0.archetype != $1.archetype {
                    return $0.archetype.localizedCaseInsensitiveCompare($1.archetype) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .disease:
            return hits.sorted {
                if $0.disease != $1.disease {
                    return $0.disease.localizedCaseInsensitiveCompare($1.disease) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private static func grouped(_ items: [FDAMedication], sort: PharmacySort) -> [PharmacyGroup] {
        let key: (FDAMedication) -> String
        switch sort {
        case .archetype: key = { $0.archetype }
        case .disease: key = { $0.disease }
        case .name, .relevance: key = { $0.archetype + " · " + $0.disease }
        }
        var order: [String] = []
        var buckets: [String: [FDAMedication]] = [:]
        for item in items {
            let title = key(item)
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(item)
        }
        return order.map { PharmacyGroup(title: $0, items: buckets[$0] ?? []) }
    }

    private static func counts(_ values: [String]) -> [(String, Int)] {
        var tallies: [String: Int] = [:]
        for value in values { tallies[value, default: 0] += 1 }
        return tallies.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
    }

    private static func uniqued(_ items: [FDAMedication]) -> [FDAMedication] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    // MARK: - IO

    private static func fetchOpenFDAPage(endpoint: String, skip: Int) async -> [FDAMedication]? {
        guard let url = URL(string: "https://api.fda.gov/drug/\(endpoint).json?limit=1000&skip=\(skip)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 14
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return parseOpenFDA(data)
        } catch {
            return nil
        }
    }

    private static func loadExtras() -> [FDAMedication] {
        guard let data = UserDefaults.standard.data(forKey: extrasKey),
              let rows = try? JSONDecoder().decode([FDAMedication].self, from: data) else {
            return []
        }
        return rows
    }

    private static func loadBundledCatalog() -> [FDAMedication] {
        var notes: [String] = []
        let urls = catalogFileURLs()
        notes.append("candidates=\(urls.count)")
        for (url, compressed) in urls {
            guard FileManager.default.fileExists(atPath: url.path),
                  let raw = try? Data(contentsOf: url), !raw.isEmpty else {
                notes.append("miss \(url.lastPathComponent)")
                continue
            }
            let magic = raw.prefix(2).map { String(format: "%02x", $0) }.joined()
            notes.append("read \(raw.count)b \(magic) z=\(compressed)")
            let text: String
            if compressed {
                guard let decoded = inflateZlib(raw, notes: &notes) else { continue }
                text = decoded
            } else if let decoded = String(data: raw, encoding: .utf8) {
                text = decoded
            } else {
                notes.append("utf8 fail")
                continue
            }
            var rows: [FDAMedication] = []
            rows.reserveCapacity(80_000)
            for line in text.split(whereSeparator: \.isNewline) {
                if let row = parseCatalogLine(String(line)) {
                    rows.append(row)
                }
            }
            notes.append("parsed \(rows.count)")
            if !rows.isEmpty {
                loadDiagnostics = notes.joined(separator: "; ")
                return rows
            }
        }
        notes.append("fallback seeds")
        loadDiagnostics = notes.joined(separator: "; ")
        return fallbackSeeds()
    }

    /// RFC 1950/1951 inflater. The simulator test host's one-shot
    /// `NSData.decompressed` and `compression_decode_buffer` both returned
    /// nothing for this ~17MB catalog, so the pharmacy fell back to four
    /// seeds. This reader is what the bundled file actually inflates with.
    private enum ZlibInflate {
        private struct Boom: Error {}

        private struct Reader {
            var data: [UInt8]
            var pos = 0
            var bitbuf: UInt64 = 0
            var bitcnt = 0

            mutating func bits(_ n: Int) throws -> Int {
                while bitcnt < n {
                    if pos >= data.count { throw Boom() }
                    bitbuf |= UInt64(data[pos]) << bitcnt
                    pos += 1
                    bitcnt += 8
                }
                let mask = (UInt64(1) << UInt64(n)) - 1
                let value = Int(bitbuf & mask)
                bitbuf >>= n
                bitcnt -= n
                return value
            }

            mutating func align() {
                let drop = bitcnt % 8
                if drop != 0 {
                    bitbuf >>= drop
                    bitcnt -= drop
                }
            }

            mutating func bytes(_ n: Int) throws -> [UInt8] {
                align()
                var out: [UInt8] = []
                out.reserveCapacity(n)
                while out.count < n {
                    if bitcnt >= 8 {
                        out.append(UInt8(bitbuf & 0xFF))
                        bitbuf >>= 8
                        bitcnt -= 8
                    } else {
                        if pos >= data.count { throw Boom() }
                        let take = min(n - out.count, data.count - pos)
                        out.append(contentsOf: data[pos..<(pos + take)])
                        pos += take
                    }
                }
                return out
            }

            mutating func symbol(_ accel: [(Int, Int)?]) throws -> Int {
                while bitcnt < 15, pos < data.count {
                    bitbuf |= UInt64(data[pos]) << bitcnt
                    pos += 1
                    bitcnt += 8
                }
                let peeked = Int(bitbuf & 0x7FFF)
                guard let hit = accel[peeked] else { throw Boom() }
                let (sym, length) = hit
                if bitcnt < length { throw Boom() }
                bitbuf >>= length
                bitcnt -= length
                return sym
            }
        }

        private static let lenBase = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258]
        private static let lenExtra = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0]
        private static let distBase = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577]
        private static let distExtra = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13]
        private static let order = [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]

        private static func accel(_ lengths: [Int]) -> [(Int, Int)?] {
            var counts = [Int](repeating: 0, count: 16)
            for length in lengths where length > 0 {
                counts[length] += 1
            }
            var code = 0
            var next = [Int](repeating: 0, count: 16)
            for bits in 1..<16 {
                code = (code + counts[bits - 1]) << 1
                next[bits] = code
            }
            var table = [(Int, Int)?](repeating: nil, count: 1 << 15)
            for (sym, length) in lengths.enumerated() where length > 0 {
                var canonical = next[length]
                next[length] += 1
                var reversed = 0
                var remaining = canonical
                for _ in 0..<length {
                    reversed = (reversed << 1) | (remaining & 1)
                    remaining >>= 1
                }
                var index = reversed
                let step = 1 << length
                while index < table.count {
                    table[index] = (sym, length)
                    index += step
                }
            }
            return table
        }

        private static let fixedLit: [(Int, Int)?] = {
            var lengths = [Int](repeating: 8, count: 144)
            lengths.append(contentsOf: [Int](repeating: 9, count: 112))
            lengths.append(contentsOf: [Int](repeating: 7, count: 24))
            lengths.append(contentsOf: [Int](repeating: 8, count: 8))
            return accel(lengths)
        }()
        private static let fixedDist: [(Int, Int)?] = accel([Int](repeating: 5, count: 32))

        private static func blocks(_ data: [UInt8]) throws -> [UInt8] {
            var reader = Reader(data: data)
            var out: [UInt8] = []
            out.reserveCapacity(18_000_000)
            while true {
                let final = try reader.bits(1)
                let kind = try reader.bits(2)
                if kind == 0 {
                    let lengthBytes = try reader.bytes(2)
                    let nlenBytes = try reader.bytes(2)
                    let length = Int(lengthBytes[0]) | (Int(lengthBytes[1]) << 8)
                    let nlen = Int(nlenBytes[0]) | (Int(nlenBytes[1]) << 8)
                    if length ^ 0xFFFF != nlen { throw Boom() }
                    out.append(contentsOf: try reader.bytes(length))
                } else if kind == 1 || kind == 2 {
                    let lit: [(Int, Int)?]
                    let dist: [(Int, Int)?]
                    if kind == 1 {
                        lit = fixedLit
                        dist = fixedDist
                    } else {
                        let hlit = try reader.bits(5) + 257
                        let hdist = try reader.bits(5) + 1
                        let hclen = try reader.bits(4) + 4
                        var clen = [Int](repeating: 0, count: 19)
                        for index in 0..<hclen {
                            clen[order[index]] = try reader.bits(3)
                        }
                        let codeLen = accel(clen)
                        var lengths: [Int] = []
                        lengths.reserveCapacity(hlit + hdist)
                        while lengths.count < hlit + hdist {
                            let sym = try reader.symbol(codeLen)
                            if sym < 16 {
                                lengths.append(sym)
                            } else if sym == 16 {
                                guard let last = lengths.last else { throw Boom() }
                                lengths.append(contentsOf: [Int](repeating: last, count: try reader.bits(2) + 3))
                            } else if sym == 17 {
                                lengths.append(contentsOf: [Int](repeating: 0, count: try reader.bits(3) + 3))
                            } else {
                                lengths.append(contentsOf: [Int](repeating: 0, count: try reader.bits(7) + 11))
                            }
                        }
                        if lengths.count != hlit + hdist { throw Boom() }
                        lit = accel(Array(lengths.prefix(hlit)))
                        dist = accel(Array(lengths.suffix(hdist)))
                    }
                    while true {
                        let sym = try reader.symbol(lit)
                        if sym < 256 {
                            out.append(UInt8(sym))
                        } else if sym == 256 {
                            break
                        } else {
                            let index = sym - 257
                            let extra = lenExtra[index]
                            let length = lenBase[index] + (extra > 0 ? try reader.bits(extra) : 0)
                            let dsym = try reader.symbol(dist)
                            let dextra = distExtra[dsym]
                            let distance = distBase[dsym] + (dextra > 0 ? try reader.bits(dextra) : 0)
                            if distance <= 0 || distance > out.count { throw Boom() }
                            for _ in 0..<length {
                                out.append(out[out.count - distance])
                            }
                        }
                    }
                } else {
                    throw Boom()
                }
                if final == 1 { break }
            }
            return out
        }

        static func inflate(_ raw: Data) -> Data? {
            let bytes = [UInt8](raw)
            guard bytes.count > 6, bytes[0] == 0x78 else { return nil }
            let header = Int(bytes[0]) * 256 + Int(bytes[1])
            guard header % 31 == 0 else { return nil }
            var offset = 2
            if bytes[1] & 0x20 != 0 { offset += 4 }
            guard offset < bytes.count else { return nil }
            guard let out = try? blocks(Array(bytes[offset...])) else { return nil }
            guard !out.isEmpty else { return nil }
            return Data(out)
        }
    }

    /// The shipped catalog is zlib (RFC 1950, header `78 da`) and inflates to
    /// about 17MB. Prefer the in-process inflater; Apple's one-shot helpers
    /// stay as backups. Raw DEFLATE (header and Adler trailer stripped) is
    /// tried because `COMPRESSION_ZLIB` is the raw format on some OS versions.
    private static func inflateZlib(_ raw: Data, notes: inout [String]) -> String? {
        if let data = ZlibInflate.inflate(raw),
           let text = String(data: data, encoding: .utf8), text.contains("|") {
            notes.append("pure \(data.count)")
            return text
        }
        var attempts: [(String, Data)] = [("zlib", raw)]
        if raw.count > 6, raw[raw.startIndex] == 0x78 {
            let payload = raw.subdata(in: raw.index(raw.startIndex, offsetBy: 2)..<raw.index(raw.endIndex, offsetBy: -4))
            attempts.append(("raw", payload))
        }
        for (label, bytes) in attempts {
            if let data = inflateViaStream(bytes),
               let text = String(data: data, encoding: .utf8), text.contains("|") {
                notes.append("stream \(label) \(data.count)")
                return text
            }
            if let data = inflateViaBuffer(bytes),
               let text = String(data: data, encoding: .utf8), text.contains("|") {
                notes.append("buffer \(label) \(data.count)")
                return text
            }
        }
        if let data = inflateViaFoundation(raw),
           let text = String(data: data, encoding: .utf8), text.contains("|") {
            notes.append("foundation \(data.count)")
            return text
        }
        notes.append("inflate failed")
        return nil
    }

    private static func inflateViaFoundation(_ raw: Data) -> Data? {
        guard let inflated = try? (raw as NSData).decompressed(using: .zlib) else { return nil }
        let data = inflated as Data
        return data.isEmpty ? nil : data
    }

    private static func inflateViaBuffer(_ raw: Data) -> Data? {
        let capacity = 32 * 1024 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let produced = raw.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                destination,
                capacity,
                base,
                raw.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard produced > 0 else { return nil }
        return Data(bytes: destination, count: produced)
    }

    /// Chunked decode so a 17MB catalog does not depend on one 32MB one-shot.
    private static func inflateViaStream(_ raw: Data) -> Data? {
        guard !raw.isEmpty else { return nil }
        let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPointer.deallocate() }
        guard compression_stream_init(streamPointer, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            return nil
        }
        defer { compression_stream_destroy(streamPointer) }

        let chunk = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { destination.deallocate() }
        var output = Data()
        output.reserveCapacity(min(max(raw.count * 8, 1024), 20 * 1024 * 1024))
        let cap = 40 * 1024 * 1024
        let finished: Bool = raw.withUnsafeBytes { source in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return false }
            streamPointer.pointee.src_ptr = base
            streamPointer.pointee.src_size = raw.count
            while output.count < cap {
                streamPointer.pointee.dst_ptr = destination
                streamPointer.pointee.dst_size = chunk
                let status = compression_stream_process(
                    streamPointer,
                    Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                )
                let wrote = chunk - streamPointer.pointee.dst_size
                if wrote > 0 {
                    output.append(destination, count: wrote)
                }
                if status == COMPRESSION_STATUS_END { return true }
                if status == COMPRESSION_STATUS_ERROR { return false }
                if wrote == 0 { return false }
            }
            return false
        }
        guard finished, !output.isEmpty else { return nil }
        return output
    }

    /// Anchor so `Bundle(for:)` resolves the app module that copied the catalog,
    /// including when a test host's `Bundle.main` is not that bundle.
    private final class BundleAnchor: NSObject {}

    private static func catalogFileURLs() -> [(URL, Bool)] {
        var urls: [(URL, Bool)] = []
        var seen = Set<String>()
        func add(_ url: URL, compressed: Bool) {
            let path = url.path
            guard seen.insert(path).inserted else { return }
            urls.append((url, compressed))
        }
        func addBundle(_ bundle: Bundle) {
            if let deflate = bundle.url(forResource: catalogResource, withExtension: "deflate") {
                add(deflate, compressed: true)
            }
            if let txt = bundle.url(forResource: catalogResource, withExtension: "txt") {
                add(txt, compressed: false)
            }
            // Unknown UTIs are sometimes copied into the app but skipped by
            // url(forResource:withExtension:). The file sits at the bundle root.
            let roots = [bundle.resourceURL, bundle.bundleURL].compactMap { $0 }
            for root in roots {
                add(root.appendingPathComponent("\(catalogResource).deflate"), compressed: true)
                add(root.appendingPathComponent("\(catalogResource).txt"), compressed: false)
            }
        }
        var bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        bundles.append(Bundle(for: BundleAnchor.self))
        if let app = Bundle(identifier: "com.forge.ForgeSwift") {
            bundles.append(app)
        }
        for bundle in bundles {
            addBundle(bundle)
        }
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        add(folder.appendingPathComponent("\(catalogResource).deflate"), compressed: true)
        add(folder.appendingPathComponent("\(catalogResource).txt"), compressed: false)
        // Last resort: walk the app bundle. A generic `file` UTI can hide the
        // resource from url(forResource:) even after CpResource copies it.
        let root = Bundle(identifier: "com.forge.ForgeSwift")?.bundleURL
            ?? Bundle(for: BundleAnchor.self).bundleURL
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if name == "\(catalogResource).deflate" {
                    add(url, compressed: true)
                } else if name == "\(catalogResource).txt" {
                    add(url, compressed: false)
                }
            }
        }
        return urls
    }

    private static func parseCatalogLine(_ line: String) -> FDAMedication? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6 else { return nil }
        let id = parts[0].trimmingCharacters(in: .whitespaces)
        let name = parts[1].trimmingCharacters(in: .whitespaces)
        let generic = parts[2].trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !name.isEmpty, !generic.isEmpty else { return nil }
        let brand = parts[3].trimmingCharacters(in: .whitespaces)
        let klass = parts.count > 6 && parts.count < 8 ? parts[6] : "FDA NDC"
        let archetype = parts.count >= 8 ? parts[6] : ""
        let disease = parts.count >= 8 ? parts[7] : ""
        return FDAMedication(
            id: id,
            name: name,
            generic: generic,
            brand: brand.isEmpty ? nil : brand,
            form: parts[4],
            strength: parts[5],
            therapeuticClass: klass,
            archetype: archetype,
            disease: disease
        )
    }

    private static func parseOpenFDA(_ data: Data) -> [FDAMedication] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        var rows: [FDAMedication] = []
        for item in results {
            if let products = item["products"] as? [[String: Any]], !products.isEmpty {
                for product in products {
                    let status = ((product["marketing_status"] as? String) ?? "").lowercased()
                    if status.contains("tentative") { continue }
                    if let row = medication(fromOpenFDA: product) { rows.append(row) }
                }
            } else if let row = medication(fromOpenFDA: item) {
                rows.append(row)
            }
        }
        return rows
    }

    private static func medication(fromOpenFDA product: [String: Any]) -> FDAMedication? {
        let brandRaw = ((product["brand_name"] as? String)
            ?? (product["brand_name_base"] as? String)
            ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let form = displayName((product["dosage_form"] as? String) ?? "Tablet")
        let ingredients = product["active_ingredients"] as? [[String: Any]] ?? []
        var names: [String] = []
        var strengths: [String] = []
        for ingredient in ingredients {
            let name = ((ingredient["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names.append(displayName(name)) }
            let strength = ((ingredient["strength"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !strength.isEmpty { strengths.append(strength.replacingOccurrences(of: "MG", with: "mg")) }
        }
        let genericRaw = ((product["generic_name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = names.isEmpty
            ? displayName(genericRaw.isEmpty ? brandRaw : genericRaw)
            : names.joined(separator: " / ")
        guard !generic.isEmpty else { return nil }
        let brand = displayName(brandRaw)
        let brandOut = brand.isEmpty || brand.caseInsensitiveCompare(generic) == .orderedSame ? nil : brand
        let strength = strengths.joined(separator: " / ")
        let name = [brandOut ?? generic, strength, form].filter { !$0.isEmpty }.joined(separator: " ")
        return classify(FDAMedication(
            id: fallbackID(name: name),
            name: name,
            generic: generic,
            brand: brandOut,
            form: form,
            strength: strength,
            therapeuticClass: "FDA NDC",
            archetype: "",
            disease: ""
        ))
    }

    private static func displayName(_ raw: String) -> String {
        var words: [String] = []
        var current = ""
        for character in raw {
            if character == " " || character == "/" || character == "-" {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                words.append(String(character))
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        var wordIndex = 0
        return words.map { token in
            if token == " " || token == "/" || token == "-" { return token }
            let upper = token.uppercased()
            let styled: String
            if keepUpper.contains(upper) {
                styled = upper
            } else if reservedWords.contains(upper), wordIndex > 0 {
                styled = token.lowercased()
            } else if token.count <= 1 {
                styled = token.uppercased()
            } else {
                styled = token.prefix(1).uppercased() + token.dropFirst().lowercased()
            }
            wordIndex += 1
            return styled
        }.joined()
    }

    private static func fallbackID(_ row: FDAMedication) -> String {
        fallbackID(name: row.name.isEmpty ? row.generic : row.name)
    }

    private static func fallbackID(name: String) -> String {
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return slug.isEmpty ? UUID().uuidString : slug
    }

    private static func classify(_ row: FDAMedication) -> FDAMedication {
        var next = row
        if next.archetype.isEmpty || next.archetype == "Other" {
            let inferred = MedicationTaxonomy.infer(generic: next.generic, brand: next.brand ?? "", form: next.form)
            if next.archetype.isEmpty || inferred.0 != "Other" {
                next.archetype = inferred.0
                next.disease = inferred.1
            }
        }
        if next.disease.isEmpty { next.disease = "Unclassified" }
        if next.archetype.isEmpty { next.archetype = "Other" }
        return next
    }

    private static func fallbackSeeds() -> [FDAMedication] {
        [
            FDAMedication(id: "xcopri-100mg-tablet", name: "Xcopri 100 mg Tablet", generic: "Cenobamate", brand: "Xcopri", form: "Tablet", strength: "100 mg", therapeuticClass: "FDA approved", archetype: "Neurology", disease: "Epilepsy"),
            FDAMedication(id: "oxtellar-xr-150mg-tablet", name: "Oxtellar XR 150 mg Tablet", generic: "Oxcarbazepine", brand: "Oxtellar XR", form: "Tablet", strength: "150 mg", therapeuticClass: "FDA approved", archetype: "Neurology", disease: "Epilepsy"),
            FDAMedication(id: "lipitor-10mg-tablet", name: "Lipitor 10 mg Tablet", generic: "Atorvastatin Calcium", brand: "Lipitor", form: "Tablet", strength: "10 mg", therapeuticClass: "FDA approved", archetype: "Cardiovascular", disease: "High cholesterol"),
            FDAMedication(id: "glucophage-500mg-tablet", name: "Glucophage 500 mg Tablet", generic: "Metformin Hydrochloride", brand: "Glucophage", form: "Tablet", strength: "500 mg", therapeuticClass: "FDA approved", archetype: "Metabolic", disease: "Diabetes"),
        ]
    }
}
