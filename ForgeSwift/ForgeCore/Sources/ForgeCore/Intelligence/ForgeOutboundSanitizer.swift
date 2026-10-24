import Foundation

/// The one gate every Forge client request must pass before it leaves
/// the device. Health samples, names, emails, and other personal fields
/// are stripped. Chat text and TTS text may remain (scrubbed of canaries
/// and structured health keys) so language models and voice can still run.
///
/// Auth to Cognito still needs an email on sign-in — that path is listed
/// in `allowedAuthPIIPaths`. Everything else is deny-by-default for PII.
public enum ForgeOutboundSanitizer: Sendable {

    /// Unusual tokens tests plant in a store. If any of these appear in a
    /// request body, URL, header, or log line, the boundary is broken.
    public enum Canary {
        public static let name = "ZeldaCanaryQuill"
        public static let email = "zelda.canary.quill@example.invalid"
        public static let heartRate = 177
        public static let hrv = 188
        public static let sleepHours = 11.7
        public static let sleepMinutes = 702
        public static let weightKg = 99.3
        public static let cycleDay = 27
    }

    /// JSON keys that must never leave (any casing / kebab / snake).
    public static let blockedKeys: Set<String> = [
        "samples", "metrics", "vitals", "recent_metrics", "recentmetrics",
        "hrv", "hrv_rmssd", "hrvrmssd", "hrv_sdnn", "hrvsdnn",
        "hrv7daytrend", "hrv30daybaseline", "hrvdaysavailable",
        "resting_hr", "restinghr", "resting-heart-rate", "restingheartrate",
        "heartrate", "heart_rate", "hr", "heartratesettlebpm",
        "sleep", "sleep_duration", "sleepduration", "sleephours",
        "sleepminutes", "deepsleep", "remsleep", "lightsleep",
        "oxygen_saturation", "oxygensaturation", "spo2",
        "blood_glucose", "bloodglucose", "blood_pressure", "bloodpressure",
        "respiratory_rate", "respiratoryrate", "body_temperature",
        "bodytemperature", "bodytemperaturef", "wristtemperaturedeviationc",
        "weight", "weightkg", "body_weight", "bodyweight", "bodyfat",
        "vo2", "vo2max", "vo2-max",
        "cycle_day", "cycleday", "cyclephase", "cycle_phase",
        "clinicaldata", "clinical_data", "medicationlayer",
        "image_base64", "imagebase64",
        "firstname", "lastname", "displayname", "fullname",
        "email", "phone", "phonenumber",
        "hrvrecentms", "hrvtrendms", "hrvbaselinems",
    ]

    /// Paths that may carry an account email (Cognito). Nothing else.
    public static let allowedAuthPIIPaths: Set<String> = [
        "/oauth2/token",
        "/oauth2/revoke",
        "/signup",
        "/confirm",
        "/forgot",
    ]

    public static func normalizeKey(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    public static func isBlockedKey(_ raw: String) -> Bool {
        blockedKeys.contains(normalizeKey(raw))
    }

    /// Recursively drop blocked keys and redact canary / email / name strings.
    public static func sanitizeJSON(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, child) in dict {
                if isBlockedKey(key) { continue }
                out[key] = sanitizeJSON(child)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { sanitizeJSON($0) }
        }
        if let text = value as? String {
            return redactText(text)
        }
        if let number = value as? Double, isCanaryNumber(number) {
            return NSNull()
        }
        if let number = value as? Int, isCanaryNumber(Double(number)) {
            return NSNull()
        }
        return value
    }

    public static func isCanaryNumber(_ value: Double) -> Bool {
        let targets: [Double] = [
            Double(Canary.heartRate),
            Double(Canary.hrv),
            Canary.sleepHours,
            Double(Canary.sleepMinutes),
            Canary.weightKg,
            Double(Canary.cycleDay),
        ]
        return targets.contains { abs($0 - value) < 0.001 }
    }

    public static func redactText(_ text: String) -> String {
        var out = text
        let needles = [
            Canary.name, Canary.email,
            "\(Canary.heartRate)", "\(Canary.hrv)",
            "\(Canary.sleepHours)", "\(Canary.sleepMinutes)",
            "\(Canary.weightKg)", "\(Canary.cycleDay)",
        ]
        for needle in needles {
            out = out.replacingOccurrences(of: needle, with: "", options: .caseInsensitive)
        }
        if let email = try? NSRegularExpression(pattern: #"[\w.+-]+@[\w-]+\.[\w.-]+"#) {
            out = email.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..<out.endIndex, in: out),
                withTemplate: ""
            )
        }
        return out
    }

    /// Sanitize an already-built request. Body JSON is rewritten; query
    /// items with blocked keys are dropped; canary strings are redacted
    /// from the URL and from non-auth headers.
    public static func sanitize(_ request: URLRequest) -> URLRequest {
        var next = request
        if let url = request.url, let sanitized = sanitizeURL(url) {
            next.url = sanitized
        }
        if let headers = request.allHTTPHeaderFields {
            var clean: [String: String] = [:]
            for (key, value) in headers {
                if key.caseInsensitiveCompare("Authorization") == .orderedSame {
                    clean[key] = value
                    continue
                }
                clean[key] = redactText(value)
            }
            next.allHTTPHeaderFields = clean
        }
        if let body = request.httpBody, !body.isEmpty {
            next.httpBody = sanitizeBody(body, url: request.url)
        }
        return next
    }

    public static func sanitizeURL(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if let items = parts.queryItems {
            parts.queryItems = items.compactMap { item in
                if isBlockedKey(item.name) { return nil }
                guard let value = item.value else { return item }
                return URLQueryItem(name: item.name, value: redactText(value))
            }
            if parts.queryItems?.isEmpty == true {
                parts.queryItems = nil
            }
        }
        return parts.url ?? url
    }

    public static func sanitizeBody(_ data: Data, url: URL?) -> Data {
        let path = url?.path.lowercased() ?? ""
        let allowAuthPII = allowedAuthPIIPaths.contains { path.hasSuffix($0) || path.contains($0) }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            if let text = String(data: data, encoding: .utf8) {
                return Data(redactText(text).utf8)
            }
            return Data()
        }
        var cleaned = sanitizeJSON(object)
        if allowAuthPII, let original = object as? [String: Any], var dict = cleaned as? [String: Any] {
            if let email = original["email"] as? String { dict["email"] = email }
            if let username = original["username"] as? String { dict["username"] = username }
            cleaned = dict
        }
        return (try? JSONSerialization.data(withJSONObject: cleaned, options: [])) ?? Data()
    }

    /// Findings if any canary or blocked health token is still visible.
    public static func leakFindings(in text: String) -> [String] {
        let lower = text.lowercased()
        var hits: [String] = []
        let canaries = [
            Canary.name.lowercased(),
            Canary.email.lowercased(),
            "\(Canary.heartRate)",
            "\(Canary.hrv)",
            "\(Canary.sleepHours)",
            "\(Canary.sleepMinutes)",
            "\(Canary.weightKg)",
            "\(Canary.cycleDay)",
        ]
        for canary in canaries where lower.contains(canary) {
            hits.append(canary)
        }
        return hits
    }

    public static func leakFindings(in request: URLRequest) -> [String] {
        var blobs: [String] = []
        if let url = request.url { blobs.append(url.absoluteString) }
        request.allHTTPHeaderFields?.forEach { key, value in
            if key.caseInsensitiveCompare("Authorization") != .orderedSame {
                blobs.append("\(key):\(value)")
            }
        }
        if let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
            blobs.append(text)
        }
        return leakFindings(in: blobs.joined(separator: "\n"))
    }

    /// Redact a log / analytics line. Prefer this over `print` for anything
    /// that might mention a person or a HealthKit number.
    public static func redactLog(_ message: String) -> String {
        redactText(message)
    }
}
