import Foundation
import ForgeCore

/// Keyless public health search plus weather and air for the Dummy.
///
/// Uses the device's default route (Wi-Fi / cellular; the Mac's internet in
/// Simulator). Nothing here talks to Forge's AWS and nothing needs a key:
///
/// * MedlinePlus health-topic search (NLM) — plain-language topic summaries;
/// * openFDA drug labels — uses and warnings for a named medication;
/// * PubMed E-utilities — the most relevant recent papers for a topic;
/// * Open-Meteo forecast + air quality — heat, cold, UV, rain, AQI.
///
/// Only a scrubbed keyword query (`AriaQueryPrivacy`) and, for weather, a
/// location rounded to one decimal (~11 km) ever leave the phone. Called only
/// from `AriaWebResearch`, which owns the local-testing / Dummy gate
/// (`scripts/check-aria-web-research.py` enforces that).
@MainActor
enum AriaWebSources {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        config.allowsCellularAccess = true
        return URLSession(configuration: config)
    }()

    private static let medicationWords = ["dose", "dosage", "side", "drug", "medication", "pill", "tablet", "mg"]

    /// Best keyless health evidence for one need: MedlinePlus → openFDA → PubMed.
    static func healthSearch(_ need: AriaResearchNeed) async -> AriaWebEvidence? {
        let query = need.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }

        if let url = makeURL("https://wsearch.nlm.nih.gov/ws/query", [
            "db": "healthTopics", "retmax": "2", "term": query,
        ]), let data = await get(url, accept: "application/xml"),
           let top = AriaWebParsers.medlinePlus(data).first {
            return AriaWebEvidence(
                text: top.summary,
                sources: [.init(title: top.title, url: top.url)],
                via: .medlineplus,
                confidence: 0.7
            )
        }

        let words = query.split(separator: " ").map(String.init)
        if medicationWords.contains(where: { words.contains($0) }),
           let drug = words.first(where: { !medicationWords.contains($0) }),
           let url = makeURL("https://api.fda.gov/drug/label.json", [
               "limit": "1", "search": "openfda.generic_name:\"\(drug)\"",
           ]),
           let data = await get(url),
           let label = AriaWebParsers.openFDALabel(data) {
            return AriaWebEvidence(
                text: label.warnings.isEmpty ? label.use : label.warnings,
                sources: [.init(title: "FDA label: \(label.name)", url: "https://open.fda.gov/apis/drug/label/")],
                via: .openfda,
                confidence: 0.6
            )
        }

        if let idsURL = makeURL("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi", [
            "db": "pubmed", "term": query, "retmax": "3", "retmode": "json", "sort": "relevance",
        ]), let idsData = await get(idsURL) {
            let ids = AriaWebParsers.pubmedIDs(idsData)
            if !ids.isEmpty,
               let sumURL = makeURL("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi", [
                   "db": "pubmed", "id": ids.joined(separator: ","), "retmode": "json",
               ]),
               let sumData = await get(sumURL) {
                let papers = AriaWebParsers.pubmedSummaries(sumData)
                if let lead = papers.first {
                    return AriaWebEvidence(
                        text: "Recent research includes \"\(lead.title)\" (\(lead.journal), \(lead.year)).",
                        sources: papers.map { .init(title: $0.title, url: $0.url) },
                        via: .pubmed,
                        confidence: 0.55
                    )
                }
            }
        }
        return nil
    }

    /// Weather + air for a coarse location. Coordinates are rounded here too,
    /// so a caller cannot accidentally send a precise fix.
    static func environment(latitude: Double, longitude: Double) async -> AriaEnvironmentRead? {
        let lat = String(format: "%.1f", latitude)
        let lon = String(format: "%.1f", longitude)
        let forecastURL = makeURL("https://api.open-meteo.com/v1/forecast", [
            "latitude": lat, "longitude": lon, "timezone": "auto", "forecast_days": "1",
            "current": "temperature_2m,apparent_temperature,precipitation,uv_index,is_day",
        ])
        let airURL = makeURL("https://air-quality-api.open-meteo.com/v1/air-quality", [
            "latitude": lat, "longitude": lon, "current": "us_aqi,pm2_5",
        ])
        var forecast: Data?
        if let forecastURL { forecast = await get(forecastURL) }
        var air: Data?
        if let airURL { air = await get(airURL) }
        return AriaWebParsers.environment(forecast: forecast, air: air)
    }

    private static func makeURL(_ base: String, _ items: [String: String]) -> URL? {
        var comps = URLComponents(string: base)
        comps?.queryItems = items.keys.sorted().map { URLQueryItem(name: $0, value: items[$0]) }
        return comps?.url
    }

    private static func get(_ url: URL, accept: String = "application/json") async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Forge-ARIA/1.0", forHTTPHeaderField: "User-Agent")
        guard let result = try? await session.data(for: request) else { return nil }
        guard let http = result.1 as? HTTPURLResponse, http.statusCode == 200, !result.0.isEmpty else { return nil }
        return result.0
    }
}
