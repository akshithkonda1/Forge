import Foundation

// MARK: - Custom archetype (ARIA-invented or user-taught)

/// A living archetype ARIA creates beyond the built-in catalog.
/// Can be synthesized locally or authored with Claude.
struct AriaCustomArchetype: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var slug: String
    var tagline: String
    var speechGuidance: String
    var avoid: [String]
    var supportStance: String
    /// Seeds for speech-style defaults
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
        case claude
        case backend
        case user
        case hybrid
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

// MARK: - Studio

/// Creates, stores, and enriches archetypes. Prefers Claude when an API key is
/// available; falls back to backend `/ai/archetype`, then offline synthesis.
@MainActor
final class AriaArchetypeStudio: ObservableObject {
    static let shared = AriaArchetypeStudio()

    @Published private(set) var customArchetypes: [AriaCustomArchetype] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSourceUsed: AriaCustomArchetype.Source?

    private let defaults = UserDefaults.standard
    private let storageKey = "forge.aria.customArchetypes.v1"
    private let claudeEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let claudeModel = "claude-sonnet-4-6"

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AriaCustomArchetype].self, from: data) {
            customArchetypes = decoded
        }
    }

    private var anthropicKey: String? {
        (Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        ?? UserDefaults.standard.string(forKey: "forge.anthropic.apiKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    var canCallClaude: Bool { anthropicKey != nil }

    // MARK: Catalog

    func archetype(id: String) -> AriaCustomArchetype? {
        customArchetypes.first { $0.id == id || $0.slug == id }
    }

    func findByName(_ name: String) -> AriaCustomArchetype? {
        let n = name.lowercased()
        return customArchetypes.first {
            $0.name.lowercased() == n || $0.slug == n.replacingOccurrences(of: " ", with: "_")
        }
    }

    // MARK: Create

    /// Main entry: invent or enrich an archetype from free-text description.
    /// Tries Claude → backend → local synthesis.
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
            let empty = AriaCustomArchetype.skeleton(
                name: preferredName ?? "Untitled",
                description: "No description yet",
                source: .local
            )
            return save(empty)
        }

        // Already exists with similar name?
        if let preferredName, let existing = findByName(preferredName) {
            return await enrich(existing, with: trimmed)
        }

        if !forceLocal, let key = anthropicKey {
            do {
                let crafted = try await synthesizeWithClaude(description: trimmed, name: preferredName, key: key)
                lastSourceUsed = .claude
                let saved = save(crafted)
                AriaContextStore.shared.addInsight(
                    "ARIA invented archetype “\(saved.name)” via Claude: \(saved.tagline)"
                )
                return saved
            } catch {
                lastError = "Claude unavailable (\(error.localizedDescription)); trying backend/local."
            }
        }

        if !forceLocal, let remote = await synthesizeWithBackend(description: trimmed, name: preferredName) {
            lastSourceUsed = .backend
            let saved = save(remote)
            AriaContextStore.shared.addInsight(
                "ARIA invented archetype “\(saved.name)” via backend: \(saved.tagline)"
            )
            return saved
        }

        let local = synthesizeLocally(description: trimmed, preferredName: preferredName)
        lastSourceUsed = .local
        let saved = save(local)
        AriaContextStore.shared.addInsight(
            "ARIA drafted archetype “\(saved.name)” offline: \(saved.tagline)"
        )
        return saved
    }

    /// Ask Claude to deepen an existing custom (or promote a builtin description).
    func enrich(_ archetype: AriaCustomArchetype, with extraContext: String) async -> AriaCustomArchetype {
        isGenerating = true
        defer { isGenerating = false }

        let prompt = """
        Existing archetype:
        name: \(archetype.name)
        tagline: \(archetype.tagline)
        speech: \(archetype.speechGuidance)
        avoid: \(archetype.avoid.joined(separator: "; "))

        New observation from the user:
        \(extraContext)

        Return STRICT JSON only with the same schema, refined and more specific. Keep the same name unless a clearer poetic name fits.
        """

        if let key = anthropicKey {
            do {
                let refined = try await synthesizeWithClaude(
                    description: prompt,
                    name: archetype.name,
                    key: key,
                    existingId: archetype.id
                )
                lastSourceUsed = .claude
                return save(refined)
            } catch {
                lastError = error.localizedDescription
            }
        }

        // Local merge
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

    // MARK: Claude

    private func synthesizeWithClaude(
        description: String,
        name: String?,
        key: String,
        existingId: String? = nil
    ) async throws -> AriaCustomArchetype {
        let system = """
        You are ARIA's archetype forge. Invent relational personality archetypes for coaching \
        how a user should show up for a specific person (partner, daughter, friend, etc.).
        NOT astrology fluff — behavioral, usable, respectful. Never sexualize minors.
        Respond with STRICT JSON only, no markdown:
        {
          "name": "short evocative name (2-3 words)",
          "tagline": "one sentence essence",
          "speechGuidance": "how to speak TO this person",
          "avoid": ["phrase or move 1", "2", "3"],
          "supportStance": "how the supporter should hold themselves",
          "formality": "casual|neutral|polished",
          "humor": "none|dry|playful|sarcastic",
          "expressiveness": "reserved|balanced|open",
          "lengthBias": "terse|medium|expansive",
          "exampleScript": "one short example line the user could say",
          "relatedBuiltin": "optional: analyst|nurturer|sovereign|peacemaker|warrior|artist|jester|sage|rebel|performer|guardian|spark|sensitiveTeen|caretakerTeen|null"
        }
        """
        let user = """
        Create or refine an archetype from this description:
        \(description)
        \(name.map { "Preferred name if it fits: \($0)" } ?? "")
        """
        let content: [[String: Any]] = [["type": "text", "text": user]]
        let raw = try await claudeCall(system: system, content: content, key: key)
        return parseClaudeJSON(raw, fallbackName: name, description: description, existingId: existingId, source: .claude)
    }

    private func claudeCall(system: String, content: [[String: Any]], key: String) async throws -> String {
        var req = URLRequest(url: claudeEndpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": claudeModel,
            "max_tokens": 700,
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "AriaArchetypeStudio", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "Claude HTTP \(code)"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else {
            throw NSError(domain: "AriaArchetypeStudio", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Unreadable Claude response"])
        }
        return blocks.compactMap { $0["text"] as? String }.joined()
    }

    private func parseClaudeJSON(
        _ raw: String,
        fallbackName: String?,
        description: String,
        existingId: String?,
        source: AriaCustomArchetype.Source
    ) -> AriaCustomArchetype {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"),
              let data = String(raw[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return synthesizeLocally(description: description, preferredName: fallbackName)
        }
        let name = (obj["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? fallbackName
            ?? "Custom Archetype"
        let avoid = (obj["avoid"] as? [String]) ?? ["assumptions"]
        var arch = AriaCustomArchetype.skeleton(name: name, description: description, source: source)
        if let existingId { arch.id = existingId }
        arch.tagline = obj["tagline"] as? String ?? description
        arch.speechGuidance = obj["speechGuidance"] as? String ?? arch.speechGuidance
        arch.avoid = avoid
        arch.supportStance = obj["supportStance"] as? String ?? arch.supportStance
        arch.formality = obj["formality"] as? String ?? "neutral"
        arch.humor = obj["humor"] as? String ?? "none"
        arch.expressiveness = obj["expressiveness"] as? String ?? "balanced"
        arch.lengthBias = obj["lengthBias"] as? String ?? "medium"
        arch.exampleScript = obj["exampleScript"] as? String ?? arch.exampleScript
        if let rel = obj["relatedBuiltin"] as? String, rel != "null" {
            arch.relatedBuiltin = rel
        }
        arch.updatedAt = Date()
        return arch
    }

    // MARK: Backend

    private func synthesizeWithBackend(description: String, name: String?) async -> AriaCustomArchetype? {
        let base = AriaService.shared.baseURL
        let url = base.appendingPathComponent("ai/archetype")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
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
            // Accept either nested "archetype" or flat JSON
            let payload = (obj["archetype"] as? [String: Any]) ?? obj
            let raw = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? ""
            return parseClaudeJSON(raw, fallbackName: name, description: description, existingId: nil, source: .backend)
        } catch {
            return nil
        }
    }

    // MARK: Local synthesis

    func synthesizeLocally(description: String, preferredName: String?) -> AriaCustomArchetype {
        let lower = description.lowercased()
        let builtin = AriaPersonalArchetype.detect(in: description)
        let name: String = {
            if let preferredName, !preferredName.isEmpty { return preferredName }
            if let builtin { return "Custom \(builtin.label)" }
            // Poetic name from keywords
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
            switch builtin {
            case .analyst:
                arch.formality = "neutral"; arch.humor = "dry"; arch.expressiveness = "reserved"; arch.lengthBias = "medium"
            case .spark, .jester:
                arch.formality = "casual"; arch.humor = "playful"; arch.lengthBias = "terse"
            case .sensitiveTeen, .caretakerTeen:
                arch.formality = "casual"; arch.lengthBias = "terse"; arch.humor = "playful"
                arch.avoid += ["lectures", "public call-outs"]
            case .sovereign, .rebel:
                arch.formality = "casual"; arch.avoid += ["orders", "you should"]
            case .warrior:
                arch.humor = "dry"; arch.lengthBias = "terse"
            case .nurturer:
                arch.expressiveness = "open"; arch.humor = "none"
            case .sage:
                arch.lengthBias = "expansive"; arch.formality = "neutral"
            default:
                break
            }
            arch.exampleScript = exampleForBuiltin(builtin)
        } else {
            arch.tagline = String(description.prefix(160))
            arch.speechGuidance = "Listen for their tempo. Reflect their words. Ask before advising."
            arch.exampleScript = "I notice ____. What do you need from me — ideas or just company?"
            if lower.contains("short") || lower.contains("text") {
                arch.lengthBias = "terse"; arch.formality = "casual"
            }
            if lower.contains("formal") { arch.formality = "polished" }
            if lower.contains("joke") || lower.contains("humor") { arch.humor = "playful" }
            if lower.contains("sensitive") || lower.contains("cry") { arch.expressiveness = "open" }
            if lower.contains("stoic") || lower.contains("closed") { arch.expressiveness = "reserved" }
        }
        return arch
    }

    private func exampleForBuiltin(_ b: AriaPersonalArchetype) -> String {
        switch b {
        case .analyst: return "Here's what I'm seeing. Does that match your read?"
        case .nurturer: return "I appreciate you. Want company or a quiet hand with something?"
        case .sovereign: return "No pressure — options are A or B. What do you want?"
        case .sensitiveTeen: return "I'm not mad. Want space or a snack?"
        case .warrior: return "Straight up: here's the issue. What's our move?"
        case .jester: return "Okay that was chaos — laughing with you, not at you. Then: what's next?"
        default: return "I'm here. What would help?"
        }
    }

    // MARK: Persist

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

    // MARK: Apply to person

    func apply(_ custom: AriaCustomArchetype, toPersonId personId: String?) {
        let id = personId ?? AriaPersonRegistry.shared.activePersonId
        guard let id else { return }
        AriaPersonRegistry.shared.applyCustomArchetype(custom, personId: id)
    }
}

// MARK: - Detect create intents

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
            || lower.contains("ask claude") && lower.contains("archetype")
            || lower.contains("learn more") && lower.contains("archetype")
            || lower.contains("build a type") || lower.contains("personality type for") {
            let name = extractName(from: lower)
            return .create(description: text, name: name)
        }
        if lower.contains("she's like") || lower.contains("he's like") || lower.contains("they're like")
            || lower.contains("her energy is") || lower.contains("his energy is")
            || lower.contains("type of person who") {
            return .create(description: text, name: nil)
        }
        if lower.contains("deepen") && lower.contains("archetype")
            || lower.contains("enrich archetype") || lower.contains("refine archetype")
            || lower.contains("learn more about this type") || lower.contains("expand this archetype") {
            return .enrich(extra: text)
        }
        if lower.contains("call her") && lower.contains("archetype") {
            return .assign(name: extractName(from: lower) ?? "Custom")
        }
        return nil
    }

    private static func extractName(from lower: String) -> String? {
        // "called Quiet Storm" / "named Quiet Storm"
        for p in ["called ", "named ", "archetype ", "type "] {
            if let r = lower.range(of: p) {
                let rest = String(lower[r.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let words = rest.split(separator: " ").prefix(3).map(String.init)
                let joined = words.joined(separator: " ")
                    .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if joined.count >= 3 { return joined.capitalized }
            }
        }
        return nil
    }
}
