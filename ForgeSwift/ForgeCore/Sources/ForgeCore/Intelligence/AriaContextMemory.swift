import Foundation

/// Adaptive on-device ARIA context: STM, vault, and UserContext working set.
///
/// Raises the old hard caps (insights 15, patterns 12, vault 40/folder) with
/// a sane ceiling, then pages and retrieves instead of loading everything.
/// Dreams and health stay on-device-first and redacted from the server unless
/// the person opts in — same `apply_permissions` / coach_context pattern.
/// Bedrock stays off. Retrieval is cheap and never always-on.
///
/// Per-user engagement (which context ARIA used, and whether the person
/// replied, acted, corrected, or ignored it) plus how often each domain
/// comes up, steer retention, granularity, and decay. Ranking is a linear
/// mix of learned relevance, recency, and confidence — inspectable, no
/// black-box model. User edits and deletes always override what the store
/// has learned.
public enum AriaContextMemory: Sendable {

    public static let storageKey = "forge.aria.context.memory.v1"
    public static let backupExcluded = true
    public static let bedrockOff = true
    public static let rankFormula = "learnedRelevance + recency + 1.2*confidence + userOverride"

    public enum Domain: String, Codable, CaseIterable, Sendable {
        case sleepDreams = "sleep_dreams"
        case lifestyleHobbies = "lifestyle_hobbies"
        case people
        case goals
        case healthConstraints = "health_constraints"
        case moodMentality = "mood_mentality"

        public var isSensitive: Bool {
            self == .sleepDreams || self == .healthConstraints
        }

        public var label: String {
            switch self {
            case .sleepDreams: return "Sleep & dreams"
            case .lifestyleHobbies: return "Lifestyle & hobbies"
            case .people: return "People"
            case .goals: return "Goals"
            case .healthConstraints: return "Health constraints"
            case .moodMentality: return "Mood & mentality"
            }
        }
    }

    public enum Layer: String, Codable, CaseIterable, Sendable {
        case stm
        case vault
        case userContext
    }

    public enum EngagementKind: String, Codable, CaseIterable, Sendable {
        case surfaced
        case replied
        case acted
        case corrected
        case ignored
    }

    public enum Granularity: String, Codable, Sendable {
        case fine
        case coarse
    }

    public struct Caps: Codable, Equatable, Sendable {
        public var stm: Int
        public var vault: Int
        public var userContext: Int
        public var pageSize: Int

        public static let sane = Caps(stm: 64, vault: 320, userContext: 48, pageSize: 20)
        public static let legacy = Caps(stm: 15, vault: 40, userContext: 12, pageSize: 12)

        public init(stm: Int, vault: Int, userContext: Int, pageSize: Int) {
            self.stm = stm
            self.vault = vault
            self.userContext = userContext
            self.pageSize = pageSize
        }
    }

    /// Per-item engagement. Cheap counters — no embeddings, no model.
    public struct ItemSignals: Codable, Equatable, Sendable {
        public var surfaced: Int
        public var replied: Int
        public var acted: Int
        public var corrected: Int
        public var ignored: Int
        public var lastKind: EngagementKind?
        public var lastAt: Date?

        public init(
            surfaced: Int = 0,
            replied: Int = 0,
            acted: Int = 0,
            corrected: Int = 0,
            ignored: Int = 0,
            lastKind: EngagementKind? = nil,
            lastAt: Date? = nil
        ) {
            self.surfaced = surfaced
            self.replied = replied
            self.acted = acted
            self.corrected = corrected
            self.ignored = ignored
            self.lastKind = lastKind
            self.lastAt = lastAt
        }

        /// Linear, inspectable. Replies and actions raise relevance; ignores
        /// and corrections lower it. Surface-only is a tiny bump so unused
        /// context does not outrank engaged context.
        public var learnedRelevance: Double {
            Double(replied) * 1.0
                + Double(acted) * 1.25
                + Double(surfaced) * 0.05
                - Double(ignored) * 0.7
                - Double(corrected) * 0.9
        }
    }

    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var text: String
        public var source: String
        public var domain: Domain
        public var layer: Layer
        public var createdAt: Date
        public var updatedAt: Date
        public var confidence: Double
        public var clusterId: String?
        public var supersededBy: String?
        public var userLocked: Bool
        public var shareOptIn: Bool
        public var summary: String?
        public var signals: ItemSignals

        public init(
            id: String = UUID().uuidString,
            text: String,
            source: String,
            domain: Domain,
            layer: Layer = .stm,
            createdAt: Date = Date(),
            updatedAt: Date? = nil,
            confidence: Double = 0.55,
            clusterId: String? = nil,
            supersededBy: String? = nil,
            userLocked: Bool = false,
            shareOptIn: Bool = false,
            summary: String? = nil,
            signals: ItemSignals = ItemSignals()
        ) {
            self.id = id
            self.text = AriaFactPrivacy.sanitizeSummary(text)
            self.source = source
            self.domain = domain
            self.layer = layer
            self.createdAt = createdAt
            self.updatedAt = updatedAt ?? createdAt
            self.confidence = min(1, max(0, confidence))
            self.clusterId = clusterId
            self.supersededBy = supersededBy
            self.userLocked = userLocked
            self.shareOptIn = shareOptIn
            self.summary = summary
            self.signals = signals
        }

        public var isSensitive: Bool { domain.isSensitive }
        public var isActive: Bool { supersededBy == nil }
    }

    public struct Tombstone: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var domain: Domain
        public var deletedAt: Date
        public var reachedServer: Bool
        public var fingerprint: String

        public init(
            id: String,
            domain: Domain,
            deletedAt: Date = Date(),
            reachedServer: Bool = false,
            fingerprint: String = ""
        ) {
            self.id = id
            self.domain = domain
            self.deletedAt = deletedAt
            self.reachedServer = reachedServer
            self.fingerprint = fingerprint
        }
    }

    public struct DomainStats: Codable, Equatable, Sendable {
        public var surfaced: Int
        public var replied: Int
        public var acted: Int
        public var corrected: Int
        public var ignored: Int
        /// How often this domain comes up (ingest), separate from engagement.
        public var mentions: Int
        public var lastAt: Date?

        public init(
            surfaced: Int = 0,
            replied: Int = 0,
            acted: Int = 0,
            corrected: Int = 0,
            ignored: Int = 0,
            mentions: Int = 0,
            lastAt: Date? = nil
        ) {
            self.surfaced = surfaced
            self.replied = replied
            self.acted = acted
            self.corrected = corrected
            self.ignored = ignored
            self.mentions = mentions
            self.lastAt = lastAt
        }

        public var volume: Int { mentions }

        public var useful: Double {
            let good = Double(replied + acted)
            let bad = Double(ignored + corrected)
            return good - (0.6 * bad)
        }
    }

    /// Named terms so a reviewer can see why one item beat another.
    public struct RankExplanation: Equatable, Sendable {
        public var learnedRelevance: Double
        public var recency: Double
        public var confidence: Double
        public var userOverride: Double
        public var total: Double
        public var formula: String
    }

    public struct Page: Equatable, Sendable {
        public var items: [Item]
        public var nextCursor: String?
        public var total: Int
    }

    public struct SharePolicy: Codable, Equatable, Sendable {
        public var shareDreams: Bool
        public var shareHealth: Bool

        public static let onDeviceOnly = SharePolicy(shareDreams: false, shareHealth: false)

        public init(shareDreams: Bool = false, shareHealth: Bool = false) {
            self.shareDreams = shareDreams
            self.shareHealth = shareHealth
        }
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public var items: [Item]
        public var tombstones: [Tombstone]
        public var stats: [Domain: DomainStats]
        public var share: SharePolicy
        public var caps: Caps
        /// Context ARIA actually used on the last turn.
        public var lastUsedIds: [String]

        public init(
            items: [Item] = [],
            tombstones: [Tombstone] = [],
            stats: [Domain: DomainStats] = [:],
            share: SharePolicy = .onDeviceOnly,
            caps: Caps = .sane,
            lastUsedIds: [String] = []
        ) {
            self.items = items
            self.tombstones = tombstones
            self.stats = stats
            self.share = share
            self.caps = caps
            self.lastUsedIds = lastUsedIds
        }

        public var active: [Item] { items.filter(\.isActive) }
    }
}

// MARK: - Classify, ingest, retrieve

extension AriaContextMemory {

    public static func fingerprint(domain: Domain, text: String) -> String {
        "\(domain.rawValue)|\(text.lowercased())"
    }

    public static func classify(_ text: String, source: String = "") -> Domain {
        let blob = (text + " " + source).lowercased()
        if blob.contains("dream") || blob.contains("nightmare") || blob.contains("lucid") {
            return .sleepDreams
        }
        if blob.contains("seizure") || blob.contains("epilep") || blob.contains("injur")
            || blob.contains("condition") || blob.contains("doctor") || blob.contains("medication") {
            return .healthConstraints
        }
        if blob.contains("goal") || blob.contains("this season") || blob.contains("working toward") {
            return .goals
        }
        if blob.contains("hobby") || blob.contains("free day") || blob.contains("pottery")
            || blob.contains("cooking") || blob.contains("walk") {
            return .lifestyleHobbies
        }
        if blob.contains("partner") || blob.contains("friend") || blob.contains("people")
            || blob.contains("mom") || blob.contains("dad") {
            return .people
        }
        if blob.contains("mood") || blob.contains("stress") || blob.contains("drained")
            || blob.contains("quiet stretch") || blob.contains("lots on") {
            return .moodMentality
        }
        if blob.contains("sleep") || blob.contains("night") || blob.contains("insomnia") {
            return .sleepDreams
        }
        return .lifestyleHobbies
    }

    public static func ingest(
        _ snap: Snapshot,
        text: String,
        source: String,
        layer: Layer = .stm,
        now: Date = Date(),
        userLocked: Bool = false,
        shareOptIn: Bool = false
    ) -> Snapshot {
        var next = snap
        let domain = classify(text, source: source)
        let item = Item(
            text: text,
            source: source,
            domain: domain,
            layer: layer,
            createdAt: now,
            userLocked: userLocked,
            shareOptIn: shareOptIn
        )
        guard !item.text.isEmpty else { return next }
        let fp = fingerprint(domain: domain, text: item.text)
        if next.tombstones.contains(where: { $0.id == item.id || $0.fingerprint == fp }) {
            return next
        }
        var stats = next.stats[domain] ?? DomainStats()
        stats.mentions += 1
        stats.lastAt = now
        next.stats[domain] = stats
        next = supersedeIfContradicts(next, incoming: item, now: now)
        next.items.insert(item, at: 0)
        next = deduplicate(next)
        next = linkRelated(next)
        next = enforceCaps(next, now: now)
        return next
    }

    public static func deduplicate(_ snap: Snapshot) -> Snapshot {
        var seen: Set<String> = []
        var kept: [Item] = []
        for item in snap.items {
            let key = fingerprint(domain: item.domain, text: item.text)
            if seen.contains(key) { continue }
            seen.insert(key)
            kept.append(item)
        }
        var next = snap
        next.items = kept
        return next
    }

    public static func linkRelated(_ snap: Snapshot) -> Snapshot {
        var next = snap
        var clusters: [Domain: String] = [:]
        for i in next.items.indices {
            if next.items[i].clusterId == nil {
                let id = clusters[next.items[i].domain] ?? UUID().uuidString
                clusters[next.items[i].domain] = id
                next.items[i].clusterId = id
            }
        }
        return next
    }

    public static func summarizeClusters(_ snap: Snapshot, now: Date = Date()) -> Snapshot {
        var next = snap
        let grouped = Dictionary(grouping: next.active) { $0.domain }
        for (domain, members) in grouped {
            let gran = granularity(domain, in: next)
            guard gran == .coarse, members.count >= 3 else { continue }
            let locked = members.filter(\.userLocked)
            let fold = members.filter { !$0.userLocked }.sorted { $0.updatedAt > $1.updatedAt }
            guard fold.count >= 3 else { continue }
            let keep = Array(fold.prefix(1)) + locked
            let dropped = fold.dropFirst()
            let line = clusterSummary(domain: domain, members: Array(fold.prefix(5)))
            if let idx = next.items.firstIndex(where: { $0.id == keep.first?.id }) {
                next.items[idx].summary = line
                next.items[idx].updatedAt = now
            }
            let survivor = keep.first?.id
            for old in dropped {
                if let idx = next.items.firstIndex(where: { $0.id == old.id }) {
                    next.items[idx].supersededBy = survivor
                    next.items[idx].updatedAt = now
                }
            }
        }
        return next
    }

    public static func consolidate(_ snap: Snapshot, now: Date = Date()) -> Snapshot {
        var next = summarizeClusters(snap, now: now)
        let stm = next.items.filter { $0.layer == .stm && $0.isActive }
        let stale = stm.filter { now.timeIntervalSince($0.updatedAt) > 14 * 24 * 3600 && !$0.userLocked }
        for item in stale {
            if let idx = next.items.firstIndex(where: { $0.id == item.id }) {
                next.items[idx].layer = .vault
                next.items[idx].summary = next.items[idx].summary ?? shorten(item.text)
                next.items[idx].updatedAt = now
            }
        }
        return enforceCaps(next, now: now)
    }

    public static func decay(_ snap: Snapshot, now: Date = Date()) -> Snapshot {
        var next = snap
        for i in next.items.indices {
            if next.items[i].userLocked { continue }
            let half = decayHalfLifeDays(for: next.items[i], in: next)
            let ageDays = now.timeIntervalSince(next.items[i].updatedAt) / 86_400
            let factor = pow(0.5, max(0, ageDays) / half)
            next.items[i].confidence = min(next.items[i].confidence, max(0.12, next.items[i].confidence * factor))
            if next.items[i].confidence < 0.18, next.items[i].layer == .stm, !next.items[i].userLocked {
                next.items[i].supersededBy = next.items[i].supersededBy ?? "decayed"
            }
        }
        return next
    }

    public static func supersedeIfContradicts(
        _ snap: Snapshot,
        incoming: Item,
        now: Date
    ) -> Snapshot {
        var next = snap
        let needle = incoming.text.lowercased()
        for i in next.items.indices {
            let old = next.items[i]
            guard old.isActive, old.domain == incoming.domain, !old.userLocked else { continue }
            if contradicts(old.text.lowercased(), needle) {
                next.items[i].supersededBy = incoming.id
                next.items[i].updatedAt = now
            }
        }
        return next
    }

    public static func edit(_ snap: Snapshot, id: String, text: String, now: Date = Date()) -> Snapshot {
        var next = snap
        let cleaned = AriaFactPrivacy.sanitizeSummary(text)
        guard !cleaned.isEmpty, let idx = next.items.firstIndex(where: { $0.id == id }) else {
            return next
        }
        next.items[idx].text = cleaned
        next.items[idx].userLocked = true
        next.items[idx].updatedAt = now
        next.items[idx].supersededBy = nil
        next.items[idx].confidence = max(next.items[idx].confidence, 0.8)
        return next
    }

    public static func delete(_ snap: Snapshot, id: String, now: Date = Date()) -> Snapshot {
        var next = snap
        guard let item = next.items.first(where: { $0.id == id }) else { return next }
        next.items.removeAll { $0.id == id }
        next.lastUsedIds.removeAll { $0 == id }
        next.tombstones.append(
            Tombstone(
                id: id,
                domain: item.domain,
                deletedAt: now,
                fingerprint: fingerprint(domain: item.domain, text: item.text)
            )
        )
        return next
    }

    public static func markServerDeleteReached(_ snap: Snapshot, id: String) -> Snapshot {
        var next = snap
        if let idx = next.tombstones.firstIndex(where: { $0.id == id }) {
            next.tombstones[idx].reachedServer = true
        }
        return next
    }

    public static func pendingServerDeletes(_ snap: Snapshot) -> [Tombstone] {
        snap.tombstones.filter { !$0.reachedServer }
    }

    public static func record(
        _ snap: Snapshot,
        itemId: String,
        kind: EngagementKind,
        now: Date = Date()
    ) -> Snapshot {
        var next = snap
        guard let item = next.items.first(where: { $0.id == itemId }) else { return next }
        var stats = next.stats[item.domain] ?? DomainStats()
        switch kind {
        case .surfaced: stats.surfaced += 1
        case .replied: stats.replied += 1
        case .acted: stats.acted += 1
        case .corrected: stats.corrected += 1
        case .ignored: stats.ignored += 1
        }
        stats.lastAt = now
        next.stats[item.domain] = stats
        if let idx = next.items.firstIndex(where: { $0.id == itemId }) {
            switch kind {
            case .surfaced: next.items[idx].signals.surfaced += 1
            case .replied: next.items[idx].signals.replied += 1
            case .acted: next.items[idx].signals.acted += 1
            case .corrected: next.items[idx].signals.corrected += 1
            case .ignored: next.items[idx].signals.ignored += 1
            }
            next.items[idx].signals.lastKind = kind
            next.items[idx].signals.lastAt = now
            if kind == .acted {
                next.items[idx].confidence = min(1, next.items[idx].confidence + 0.08)
                next.items[idx].updatedAt = now
            } else if kind == .replied {
                next.items[idx].confidence = min(1, next.items[idx].confidence + 0.04)
                next.items[idx].updatedAt = now
            } else if kind == .corrected, !next.items[idx].userLocked {
                next.items[idx].confidence = max(0.12, next.items[idx].confidence * 0.8)
            } else if kind == .ignored, !next.items[idx].userLocked {
                next.items[idx].confidence = max(0.12, next.items[idx].confidence * 0.85)
            }
        }
        return next
    }

    /// ARIA used these items this turn. Records `.surfaced` on each.
    public static func markUsed(
        _ snap: Snapshot,
        itemIds: [String],
        now: Date = Date()
    ) -> Snapshot {
        var next = snap
        next.lastUsedIds = itemIds
        for id in itemIds {
            next = record(next, itemId: id, kind: .surfaced, now: now)
        }
        return next
    }

    /// Apply an outcome to the context ARIA used (or an explicit id list).
    public static func recordOutcome(
        _ snap: Snapshot,
        kind: EngagementKind,
        itemIds: [String]? = nil,
        now: Date = Date()
    ) -> Snapshot {
        let ids = itemIds ?? snap.lastUsedIds
        var next = snap
        for id in ids {
            next = record(next, itemId: id, kind: kind, now: now)
        }
        return next
    }

    public static func retrieve(
        _ snap: Snapshot,
        domain: Domain? = nil,
        query: String = "",
        cursor: String? = nil,
        now: Date = Date(),
        limit: Int? = nil
    ) -> Page {
        let size = limit ?? snap.caps.pageSize
        var pool = rank(snap, now: now)
        if let domain {
            pool = pool.filter { $0.domain == domain }
        }
        if !query.isEmpty {
            let q = query.lowercased()
            pool = pool.filter { $0.text.lowercased().contains(q) || ($0.summary?.lowercased().contains(q) ?? false) }
        }
        let start: Int = {
            guard let cursor, let idx = pool.firstIndex(where: { $0.id == cursor }) else { return 0 }
            return idx + 1
        }()
        let slice = Array(pool.dropFirst(start).prefix(size))
        let next = (start + slice.count) < pool.count ? slice.last?.id : nil
        return Page(items: slice, nextCursor: next, total: pool.count)
    }

    public static func workingSet(_ snap: Snapshot, now: Date = Date()) -> [Item] {
        Array(rank(snap, now: now).prefix(snap.caps.userContext))
    }

    public static func rank(_ snap: Snapshot, now: Date) -> [Item] {
        snap.active.sorted { a, b in
            explain(a, in: snap, now: now).total > explain(b, in: snap, now: now).total
        }
    }

    public static func explain(_ item: Item, in snap: Snapshot, now: Date) -> RankExplanation {
        let recency = max(0, 1 - now.timeIntervalSince(item.updatedAt) / (60 * 24 * 3600))
        let domainUseful = snap.stats[item.domain]?.useful ?? 0
        let learned = item.signals.learnedRelevance + (0.25 * domainUseful)
        let confidence = item.confidence
        let userOverride = item.userLocked ? 10.0 : 0
        let total = learned + recency + (1.2 * confidence) + userOverride
        return RankExplanation(
            learnedRelevance: learned,
            recency: recency,
            confidence: confidence,
            userOverride: userOverride,
            total: total,
            formula: rankFormula
        )
    }

    public static func learnedVisible(_ snap: Snapshot) -> [String] {
        workingSet(snap).prefix(12).map { item in
            let body = item.summary ?? item.text
            return "\(item.domain.label): \(body)"
        }
    }

    public static func serverContext(_ snap: Snapshot) -> [String: String] {
        var out: [String: String] = [:]
        let allowed = snap.active.filter { item in
            if item.domain == .sleepDreams { return snap.share.shareDreams && item.shareOptIn }
            if item.domain == .healthConstraints { return snap.share.shareHealth && item.shareOptIn }
            return true
        }
        let ranked = allowed.sorted { $0.updatedAt > $1.updatedAt }.prefix(12)
        if !ranked.isEmpty {
            out["context_summaries"] = ranked.map { $0.summary ?? shorten($0.text) }.joined(separator: " | ")
        }
        out["context_domains"] = ranked.map(\.domain.rawValue).joined(separator: ",")
        return out
    }

    public static func containsSensitiveServerLeak(
        _ payload: [String: String],
        share: SharePolicy
    ) -> Bool {
        let blob = payload.values.joined(separator: " ").lowercased()
        if !share.shareDreams, blob.contains("dream") { return true }
        if !share.shareHealth, blob.contains("seizure") || blob.contains("epilep") { return true }
        return false
    }

    public static func granularity(_ domain: Domain, in snap: Snapshot) -> Granularity {
        let useful = snap.stats[domain]?.useful ?? 0
        return useful >= 2 ? .fine : .coarse
    }

    public static func decayHalfLifeDays(_ domain: Domain, in snap: Snapshot) -> Double {
        let useful = snap.stats[domain]?.useful ?? 0
        if useful >= 4 { return 28 }
        if useful >= 1 { return 16 }
        return 8
    }

    public static func decayHalfLifeDays(for item: Item, in snap: Snapshot) -> Double {
        var half = decayHalfLifeDays(item.domain, in: snap)
        let rel = item.signals.learnedRelevance
        if rel >= 2 { half *= 1.5 }
        else if rel <= -1 { half *= 0.55 }
        return max(4, min(45, half))
    }

    public static func retentionPriority(_ domain: Domain, in snap: Snapshot) -> Double {
        let stats = snap.stats[domain] ?? DomainStats()
        return 1.0 + stats.useful + (0.15 * Double(stats.volume))
    }

    public static func userContextLines(_ snap: Snapshot, now: Date = Date()) -> [String] {
        workingSet(snap, now: now).map { $0.summary ?? $0.text }
    }
}

// MARK: - Internals

extension AriaContextMemory {
    static func score(_ item: Item, in snap: Snapshot, now: Date) -> Double {
        explain(item, in: snap, now: now).total
    }

    static func enforceCaps(_ snap: Snapshot, now: Date = Date()) -> Snapshot {
        var next = snap
        func trim(_ layer: Layer, cap: Int) {
            let ranked = next.items.enumerated()
                .filter { $0.element.layer == layer && $0.element.isActive && !$0.element.userLocked }
                .sorted { score($0.element, in: next, now: now) > score($1.element, in: next, now: now) }
                .map(\.element.id)
            if ranked.count <= cap { return }
            let drop = Set(ranked.suffix(from: cap))
            next.items.removeAll { drop.contains($0.id) }
        }
        trim(.stm, cap: snap.caps.stm)
        trim(.vault, cap: snap.caps.vault)
        trim(.userContext, cap: snap.caps.userContext)
        return next
    }

    static func contradicts(_ old: String, _ incoming: String) -> Bool {
        let pairs = [
            ("quiet stretch", "up for a little more"),
            ("lots on lately", "a calmer patch"),
            ("single", "partnered"),
            ("won't train", "want to train"),
        ]
        for (a, b) in pairs {
            if (old.contains(a) && incoming.contains(b)) || (old.contains(b) && incoming.contains(a)) {
                return true
            }
        }
        return false
    }

    static func clusterSummary(domain: Domain, members: [Item]) -> String {
        let bits = members.prefix(3).map { shorten($0.text) }.joined(separator: "; ")
        return "\(domain.label) lately: \(bits)"
    }

    static func shorten(_ text: String) -> String {
        if text.count <= 96 { return text }
        return String(text.prefix(93)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// On-device snapshot. File is excluded from iCloud backup (dreams / health).
public enum AriaContextMemoryStore: Sendable {
    public static let fileName = "aria-context-memory.json"
    public static let directoryName = "ForgeAriaContext"

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func load(from directory: URL? = nil) -> AriaContextMemory.Snapshot {
        let root = directory ?? defaultDirectory()
        let url = root.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AriaContextMemory.Snapshot.self, from: data) else {
            return AriaContextMemory.Snapshot()
        }
        return decoded
    }

    @discardableResult
    public static func save(
        _ snap: AriaContextMemory.Snapshot,
        to directory: URL? = nil
    ) -> URL? {
        let root = directory ?? defaultDirectory()
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = AriaContextMemory.backupExcluded
        var dir = root
        try? dir.setResourceValues(values)
        let url = root.appendingPathComponent(fileName)
        guard let data = try? JSONEncoder().encode(snap) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }
}

/// Dream notes as sleep context. Continuity / replay of the day — lifestyle
/// coach, never a dream dictionary, never a diagnosis.
public enum AriaDreamJournal: Sendable {
    public static let researchLine =
        "Dreams often replay what the day was already about. I keep the note on this phone — not a diagnosis, not a dream dictionary."

    public static let storageKey = "forge.aria.dream.journal.v1"

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var night: String
        public var note: String
        public var createdAt: Date
        public var shareOptIn: Bool

        public init(
            id: String = UUID().uuidString,
            night: String,
            note: String,
            createdAt: Date = Date(),
            shareOptIn: Bool = false
        ) {
            self.id = id
            self.night = night
            self.note = AriaFactPrivacy.sanitizeSummary(note)
            self.createdAt = createdAt
            self.shareOptIn = shareOptIn
        }
    }

    public static func toMemoryItem(_ entry: Entry) -> AriaContextMemory.Item {
        AriaContextMemory.Item(
            id: entry.id,
            text: "Dream \(entry.night): \(entry.note)",
            source: "dream-journal",
            domain: .sleepDreams,
            layer: .vault,
            createdAt: entry.createdAt,
            shareOptIn: entry.shareOptIn
        )
    }

    public static func containsBanned(_ line: String) -> Bool {
        if ForgePersonalization.containsBannedCopy(line) { return true }
        let lower = line.lowercased()
        return ["interpret this as", "means you have"].contains { lower.contains($0) }
    }
}
