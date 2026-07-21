import Foundation

// MARK: - Custom archetype (ARIA-invented)

/// A living archetype ARIA creates beyond the built-in catalog.
/// Authored via backend Bedrock when available; offline local forge otherwise.
struct AriaCustomArchetype: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var slug: String
    var tagline: String
    var speechGuidance: String
    var avoid: [String]
    var supportStance: String
    var formality: String
    var humor: String
    var expressiveness: String
    var lengthBias: String
    var exampleScript: String
    var source: Source
    var inspiredByDescription: String
    var relatedBuiltin: String?
    var createdAt: Date
    var updatedAt: Date

    enum Source: String, Codable {
        case local
        case bedrock
        case backend
        case user
        case hybrid
        /// Legacy decode compatibility (client never calls Anthropic directly).
        case claude

        var displayName: String {
            switch self {
            case .bedrock, .claude: return "ARIA intelligence"
            case .backend: return "ARIA server"
            case .local, .hybrid: return "on-device draft"
            case .user: return "your wording"
            }
        }
    }

    var displayName: String { name }

    static func skeleton(
        name: String,
        description: String,
        source: Source
    ) -> AriaCustomArchetype {
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0 == "_" || $0.isNumber }
        return AriaCustomArchetype(
            id: UUID().uuidString,
            name: name,
            slug: slug.isEmpty ? "custom_\(Int(Date().timeIntervalSince1970))" : slug,
            tagline: description,
            speechGuidance: "Match their energy; lead with respect; avoid assumptions.",
            avoid: ["generic advice", "one-size-fits-all scripts"],
            supportStance: "See them as a full person; adapt to what you know.",
            formality: "neutral",
            humor: "none",
            expressiveness: "balanced",
            lengthBias: "medium",
            exampleScript: "I'm here. What would help right now?",
            source: source,
            inspiredByDescription: description,
            relatedBuiltin: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Studio (backend / Bedrock first)

/// Creates, stores, and enriches archetypes via Forge backend (AWS Bedrock).
/// Offline local synthesis always available — no client API keys required.
@MainActor
final class AriaArchetypeStudio: ObservableObject {
    static let shared = AriaArchetypeStudio()

    @Published private(set) var customArchetypes: [AriaCustomArchetype] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSourceUsed: AriaCustomArchetype.Source?

    private let defaults = UserDefaults.standard
    private let storageKey = "forge.aria.customArchetypes.v1"

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AriaCustomArchetype].self, from: data) {
            customArchetypes = decoded
        }
    }

    func archetype(id: String) -> AriaCustomArchetype? {
        customArchetypes.first { $0.id == id || $0.slug == id }
    }

    func findByName(_ name: String) -> AriaCustomArchetype? {
        let n = name.lowercased()
        return customArchetypes.first {
            $0.name.lowercased() == n || $0.slug == n.replacingOccurrences(of: " ", with: "_")
        }
    }

    /// Invent or refine an archetype. Backend (Bedrock) first → local forge.
    func createArchetype(
        from description: String,
        preferredName: String? = nil,
        forceLocal: Bool = false
    ) async -> AriaCustomArchetype {
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return save(AriaCustomArchetype.skeleton(
                name: preferredName ?? "Untitled",
                description: "No description yet",
                source: .local
            ))
        }

        if let preferredName, let existing = findByName(preferredName) {
            return await enrich(existing, with: trimmed)
        }

        if !forceLocal, let remote = await synthesizeWithBackend(description: trimmed, name: preferredName) {
            lastSourceUsed = remote.source == .claude ? .bedrock : remote.source
            let saved = save(remote)
            AriaContextStore.shared.addInsight(
                "ARIA invented archetype “\(saved.name)” (\(saved.source.displayName)): \(saved.tagline)"
            )
            return saved
        }

        let local = synthesizeLocally(description: trimmed, preferredName: preferredName)
        lastSourceUsed = .local
        let saved = save(local)
        AriaContextStore.shared.addInsight(
            "ARIA drafted archetype “\(saved.name)” on-device: \(saved.tagline)"
        )
        return saved
    }

    func enrich(_ archetype: AriaCustomArchetype, with extraContext: String) async -> AriaCustomArchetype {
        isGenerating = true
        defer { isGenerating = false }

        let blended = """
        Existing archetype \(archetype.name): \(archetype.tagline). \(archetype.speechGuidance)
        New observation: \(extraContext)
        """
        if let remote = await synthesizeWithBackend(description: blended, name: archetype.name) {
            var refined = remote
            refined.id = archetype.id
            refined.source = .hybrid
            lastSourceUsed = .bedrock
            return save(refined)
        }

        var merged = archetype
        merged.inspiredByDescription += " | " + extraContext
        if let inferred = AriaPersonalArchetype.detect(in: extraContext) {
            merged.relatedBuiltin = inferred.rawValue
            merged.speechGuidance = inferred.speechGuidance
            merged.tagline = inferred.tagline
        }
        var speechBridge = AriaSpeechStyleProfile(
            formality: AriaSpeechStyleProfile.Formality(rawValue: merged.formality) ?? .neutral,
            pace: .measured,
            length: AriaSpeechStyleProfile.LengthBias(rawValue: merged.lengthBias) ?? .medium,
            humor: AriaSpeechStyleProfile.HumorStyle(rawValue: merged.humor) ?? .none,
            emotionalExpressiveness: AriaSpeechStyleProfile.Expressiveness(rawValue: merged.expressiveness) ?? .balanced,
            vocabulary: .simple,
            emojiComfort: .light,
            signaturePhrases: [],
            triggerPhrases: merged.avoid,
            channelBias: .unknown,
            sampleLines: [merged.exampleScript],
            lastUpdated: Date()
        )
        if AriaSpeechStyleProfile.learn(from: extraContext, into: &speechBridge) {
            merged.formality = speechBridge.formality.rawValue
            merged.humor = speechBridge.humor.rawValue
            merged.expressiveness = speechBridge.emotionalExpressiveness.rawValue
            merged.lengthBias = speechBridge.length.rawValue
            merged.avoid = Array(Set(merged.avoid + speechBridge.triggerPhrases))
        }
        merged.updatedAt = Date()
        merged.source = .hybrid
        lastSourceUsed = .local
        return save(merged)
    }

    // MARK: Backend (Bedrock path lives on server)

    private func synthesizeWithBackend(description: String, name: String?) async -> AriaCustomArchetype? {
        let url = AriaService.shared.baseURL.appendingPathComponent("ai/archetype")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45
        let body: [String: Any] = [
            "user_id": AriaContextStore.shared.context.userId,
            "description": description,
            "preferred_name": name as Any,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let payload = (obj["archetype"] as? [String: Any]) ?? obj
            return parsePayload(payload, fallbackName: name, description: description)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func parsePayload(
        _ obj: [String: Any],
        fallbackName: String?,
        description: String
    ) -> AriaCustomArchetype {
        let name = (obj["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? fallbackName
            ?? "Custom Archetype"
        var arch = AriaCustomArchetype.skeleton(name: name, description: description, source: .backend)
        if let id = obj["id"] as? String { arch.id = id }
        arch.tagline = obj["tagline"] as? String ?? description
        arch.speechGuidance = obj["speechGuidance"] as? String ?? arch.speechGuidance
        arch.avoid = (obj["avoid"] as? [String]) ?? arch.avoid
        arch.supportStance = obj["supportStance"] as? String ?? arch.supportStance
        arch.formality = obj["formality"] as? String ?? "neutral"
        arch.humor = obj["humor"] as? String ?? "none"
        arch.expressiveness = obj["expressiveness"] as? String ?? "balanced"
        arch.lengthBias = obj["lengthBias"] as? String ?? "medium"
        arch.exampleScript = obj["exampleScript"] as? String ?? arch.exampleScript
        if let rel = obj["relatedBuiltin"] as? String, rel != "null" {
            arch.relatedBuiltin = rel
        }
        let src = (obj["source"] as? String) ?? "backend"
        arch.source = AriaCustomArchetype.Source(rawValue: src) ?? .backend
        if arch.source == .claude { arch.source = .bedrock }
        arch.updatedAt = Date()
        return arch
    }

    // MARK: Local synthesis

    func synthesizeLocally(description: String, preferredName: String?) -> AriaCustomArchetype {
        let lower = description.lowercased()
        let builtin = AriaPersonalArchetype.detect(in: description)
        let name: String = {
            if let preferredName, !preferredName.isEmpty { return preferredName }
            if let builtin { return "Custom \(builtin.label)" }
            if lower.contains("storm") || lower.contains("intense") { return "Quiet Storm" }
            if lower.contains("wall") || lower.contains("shut") { return "Glass Wall" }
            if lower.contains("light") || lower.contains("joke") { return "Bright Edge" }
            if lower.contains("logic") || lower.contains("data") { return "Clear Signal" }
            if lower.contains("soft") || lower.contains("gentle") { return "Warm Anchor" }
            if lower.contains("teen") || lower.contains("daughter") { return "Private Flame" }
            return "Living Pattern"
        }()

        var arch = AriaCustomArchetype.skeleton(name: name, description: description, source: .local)
        if let builtin {
            arch.relatedBuiltin = builtin.rawValue
            arch.tagline = "\(builtin.tagline) Refined from: \(description.prefix(120))"
            arch.speechGuidance = builtin.speechGuidance
            arch.avoid = builtin.avoid
            arch.supportStance = "Hold the \(builtin.label.lowercased()) pattern without boxing them in forever."
            arch.exampleScript = "I'm here. What would help?"
            switch builtin {
            case .analyst:
                arch.formality = "neutral"; arch.humor = "dry"; arch.expressiveness = "reserved"
            case .spark, .jester:
                arch.formality = "casual"; arch.humor = "playful"; arch.lengthBias = "terse"
            case .sensitiveTeen, .caretakerTeen:
                arch.formality = "casual"; arch.lengthBias = "terse"
                arch.avoid += ["lectures", "public call-outs"]
            case .sovereign, .rebel:
                arch.avoid += ["orders", "you should"]
            default: break
            }
        } else {
            arch.tagline = String(description.prefix(160))
            arch.speechGuidance = "Listen for their tempo. Reflect their words. Ask before advising."
            arch.exampleScript = "I notice ____. What do you need from me — ideas or just company?"
        }
        return arch
    }

    @discardableResult
    private func save(_ archetype: AriaCustomArchetype) -> AriaCustomArchetype {
        if let idx = customArchetypes.firstIndex(where: { $0.id == archetype.id }) {
            customArchetypes[idx] = archetype
        } else if let idx = customArchetypes.firstIndex(where: { $0.slug == archetype.slug }) {
            var a = archetype
            a.id = customArchetypes[idx].id
            customArchetypes[idx] = a
            persist()
            return a
        } else {
            customArchetypes.insert(archetype, at: 0)
        }
        if customArchetypes.count > 80 {
            customArchetypes = Array(customArchetypes.prefix(80))
        }
        persist()
        return archetype
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(customArchetypes) {
            defaults.set(data, forKey: storageKey)
        }
    }

    func apply(_ custom: AriaCustomArchetype, toPersonId personId: String?) {
        let id = personId ?? AriaPersonRegistry.shared.activePersonId
        guard let id else { return }
        AriaPersonRegistry.shared.applyCustomArchetype(custom, personId: id)
    }
}

// MARK: - Chat intents

enum AriaArchetypeIntent {
    case create(description: String, name: String?)
    case enrich(extra: String)
    case list
    case assign(name: String)

    static func parse(_ text: String) -> AriaArchetypeIntent? {
        let lower = text.lowercased()
        if lower.contains("list archetypes") || lower.contains("what archetypes") {
            return .list
        }
        if lower.contains("create an archetype") || lower.contains("invent an archetype")
            || lower.contains("new archetype") || lower.contains("make an archetype")
            || lower.contains("forge an archetype") || lower.contains("design an archetype")
            || lower.contains("build a type") || lower.contains("personality type for")
            || lower.contains("learn more") && lower.contains("archetype") {
            return .create(description: text, name: extractName(from: lower))
        }
        if lower.contains("she's like") || lower.contains("he's like") || lower.contains("they're like")
            || lower.contains("her energy is") || lower.contains("type of person who") {
            return .create(description: text, name: nil)
        }
        if lower.contains("deepen") && lower.contains("archetype")
            || lower.contains("enrich archetype") || lower.contains("refine archetype")
            || lower.contains("expand this archetype") {
            return .enrich(extra: text)
        }
        if lower.contains("call her") && lower.contains("archetype") {
            return .assign(name: extractName(from: lower) ?? "Custom")
        }
        return nil
    }

    private static func extractName(from lower: String) -> String? {
        for p in ["called ", "named ", "archetype ", "type "] {
            if let r = lower.range(of: p) {
                let rest = String(lower[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let words = rest.split(separator: " ").prefix(3).map(String.init)
                let joined = words.joined(separator: " ")
                    .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if joined.count >= 3 { return joined.capitalized }
            }
        }
        return nil
    }
}
