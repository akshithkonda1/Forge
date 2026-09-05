import Foundation

/// One FDA-approved presentation. Names only — not a prescription, not PHI.
struct FDAMedication: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var generic: String
    var brand: String?
    var form: String
    var strength: String
    var therapeuticClass: String
}

/// On-device pharmacy. Bundled list is drugs@FDA + the FDA NDC directory
/// (the product codes CMS, CDC, and every federal payer actually bill) +
/// CDC CVX vaccines. Search is local. A daily openFDA merge (drugs@FDA and
/// NDC) adds anything listed after the bundle was cut.
enum MedicationPharmacy {
    static let minimumCount = 10_000
    private static let extrasKey = "forge.pharmacy.openfda.v2"
    private static let extrasAtKey = "forge.pharmacy.openfda.at.v2"
    private static let savedKey = "forge.pharmacy.saved.v1"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let catalogResource = "fda_pharmacy_catalog"
    private static let reservedWords: Set<String> = ["AND", "OR", "OF", "FOR", "WITH", "THE", "IN", "TO"]
    private static let keepUpper: Set<String> = ["XR", "XL", "ER", "CR", "SR", "IR", "DR", "LA", "ODT", "EC", "HCL", "HBR"]

    private static let lock = NSLock()
    private static var cached: [FDAMedication]?

    static var count: Int { all().count }

    static func all() -> [FDAMedication] {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        var rows = loadBundledCatalog()
        rows.append(contentsOf: loadExtras())
        var seen = Set<String>()
        rows = rows.filter { seen.insert($0.id).inserted }
        rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cached = rows
        return rows
    }

    static func search(_ query: String, limit: Int = 40) -> [FDAMedication] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let catalog = all()
        guard q.count >= 1 else { return Array(catalog.prefix(limit)) }
        let tokens = q.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }

        var exactBrand: [FDAMedication] = []
        var prefixBrand: [FDAMedication] = []
        var other: [FDAMedication] = []

        for row in catalog {
            let brand = (row.brand ?? "").lowercased()
            let name = row.name.lowercased()
            let generic = row.generic.lowercased()
            let hay = [name, generic, brand, row.form.lowercased(), row.strength.lowercased()].joined(separator: " ")
            let tokenHit = tokens.allSatisfy { token in
                brand.hasPrefix(token)
                    || name.hasPrefix(token)
                    || generic.hasPrefix(token)
                    || hay.contains(token)
            }
            guard tokenHit || hay.contains(q) else { continue }

            if brand == q || name == q {
                exactBrand.append(row)
            } else if brand.hasPrefix(q) || brand.split(whereSeparator: { $0 == " " || $0 == "-" }).contains(where: { $0.hasPrefix(q) }) {
                prefixBrand.append(row)
            } else {
                other.append(row)
            }
        }
        return Array((exactBrand + prefixBrand + other).prefix(limit))
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
            return "FDA · CDC · CMS NDC catalog · auto-updates daily"
        }
        return "Updated " + at.formatted(date: .abbreviated, time: .shortened)
    }

    /// Daily merge from openFDA drugs@FDA and NDC. Fails closed.
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
                    extras.append(row)
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
        lock.unlock()
    }

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
            guard let raw = try? Data(contentsOf: url) else { continue }
            let text: String
            if compressed {
                guard let inflated = (try? (raw as NSData).decompressed(using: .zlib)) as Data?,
                      let decoded = String(data: inflated, encoding: .utf8) else { continue }
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
            if !rows.isEmpty {
                return rows
            }
        }
        return fallbackSeeds()
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
        let klass = parts.count > 6 ? parts[6].trimmingCharacters(in: .whitespaces) : "FDA approved"
        return FDAMedication(
            id: id,
            name: name,
            generic: generic,
            brand: brand.isEmpty ? nil : brand,
            form: parts[4],
            strength: parts[5],
            therapeuticClass: klass.isEmpty ? "FDA approved" : klass
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
                    if let row = medication(fromOpenFDA: product) {
                        rows.append(row)
                    }
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
        let name = [brandOut ?? generic, strength, form]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let id = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return FDAMedication(
            id: id,
            name: name,
            generic: generic,
            brand: brandOut,
            form: form,
            strength: strength,
            therapeuticClass: "FDA NDC"
        )
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

    /// Last-resort handful so the page still has a flow if the bundle is missing.
    private static func fallbackSeeds() -> [FDAMedication] {
        [
            FDAMedication(id: "xcopri-100mg-tablet", name: "Xcopri 100 mg Tablet", generic: "Cenobamate", brand: "Xcopri", form: "Tablet", strength: "100 mg", therapeuticClass: "FDA approved"),
            FDAMedication(id: "oxtellar-xr-150mg-tablet", name: "Oxtellar XR 150 mg Tablet", generic: "Oxcarbazepine", brand: "Oxtellar XR", form: "Tablet", strength: "150 mg", therapeuticClass: "FDA approved"),
            FDAMedication(id: "atorvastatin-10mg-tablet", name: "Lipitor 10 mg Tablet", generic: "Atorvastatin Calcium", brand: "Lipitor", form: "Tablet", strength: "10 mg", therapeuticClass: "FDA approved"),
            FDAMedication(id: "metformin-500mg-tablet", name: "Glucophage 500 mg Tablet", generic: "Metformin Hydrochloride", brand: "Glucophage", form: "Tablet", strength: "500 mg", therapeuticClass: "FDA approved"),
            FDAMedication(id: "lisinopril-10mg-tablet", name: "Zestril 10 mg Tablet", generic: "Lisinopril", brand: "Zestril", form: "Tablet", strength: "10 mg", therapeuticClass: "FDA approved"),
        ]
    }
}
