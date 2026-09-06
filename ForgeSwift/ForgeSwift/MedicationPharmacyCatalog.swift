import Foundation

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
    private static let extrasKey = "forge.pharmacy.openfda.v3"
    private static let extrasAtKey = "forge.pharmacy.openfda.at.v3"
    private static let savedKey = "forge.pharmacy.saved.v1"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let catalogResource = "fda_pharmacy_catalog"
    private static let reservedWords: Set<String> = ["AND", "OR", "OF", "FOR", "WITH", "THE", "IN", "TO"]
    private static let keepUpper: Set<String> = ["XR", "XL", "ER", "CR", "SR", "IR", "DR", "LA", "ODT", "EC", "HCL", "HBR"]

    private static let lock = NSLock()
    private static var cached: [FDAMedication]?
    private static var sortedTokens: [String] = []
    private static var tokenRows: [String: [Int]] = [:]
    private static var ready = false

    static var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return ready
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
        lock.lock()
        cached = nil
        ready = false
        lock.unlock()
        _ = snapshot()
    }

    // MARK: - Snapshot

    private static func snapshot() -> [FDAMedication] {
        lock.lock()
        if let cached, ready {
            lock.unlock()
            return cached
        }
        lock.unlock()

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
        let tokens = buildIndex(rows)

        lock.lock()
        cached = rows
        sortedTokens = tokens.sorted
        tokenRows = tokens.map
        ready = true
        lock.unlock()
        return rows
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
        let tokens = tokenize(q)
        guard !tokens.isEmpty else { return [] }

        lock.lock()
        let tokenList = sortedTokens
        let map = tokenRows
        lock.unlock()

        var scores: [Int: Int] = [:]
        for token in tokens {
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
            ranked.append((row, relevance(row, query: q, tokens: tokens)))
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
        for (url, compressed) in catalogFileURLs() {
            guard let raw = try? Data(contentsOf: url), !raw.isEmpty else { continue }
            let text: String
            if compressed {
                guard let decoded = inflateZlib(raw) else { continue }
                text = decoded
            } else if let decoded = String(data: raw, encoding: .utf8) {
                text = decoded
            } else {
                continue
            }
            var rows: [FDAMedication] = []
            rows.reserveCapacity(80_000)
            for line in text.split(whereSeparator: \.isNewline) {
                if let row = parseCatalogLine(String(line)) {
                    rows.append(row)
                }
            }
            if !rows.isEmpty { return rows }
        }
        return fallbackSeeds()
    }

    private static func inflateZlib(_ raw: Data) -> String? {
        do {
            let inflated = try (raw as NSData).decompressed(using: .zlib)
            return String(data: inflated as Data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func catalogFileURLs() -> [(URL, Bool)] {
        var urls: [(URL, Bool)] = []
        if let deflate = Bundle.main.url(forResource: catalogResource, withExtension: "deflate") {
            urls.append((deflate, true))
        }
        if let txt = Bundle.main.url(forResource: catalogResource, withExtension: "txt") {
            urls.append((txt, false))
        }
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        urls.append((folder.appendingPathComponent("\(catalogResource).deflate"), true))
        urls.append((folder.appendingPathComponent("\(catalogResource).txt"), false))
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
