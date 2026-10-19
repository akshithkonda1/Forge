import Foundation
import os

// MARK: - Runtime performance instrumentation
//
// Forge's performance story has two halves. Policy is ForgeRuntimeGuard:
// Hz caps, thermal shedding, memory and file budgets, "compact off the
// main thread", all locked by ForgeStabilityTests. This file is the
// measurement half: os_signpost intervals and events on the paths that
// matter, so Instruments (os_signpost template) or Console can answer
// "where does launch / HealthKit / ARIA time actually go" on a real
// device instead of guessing from the policy.
//
// Subsystem: `com.forge.core` — one for every target, so the phone app,
// Watch, widgets and the share extension all report into the same trace.
//
// Categories (the tracks you filter by in Instruments):
//   launch    app start through first meaningful work (AppStore init,
//             migration, coordinator activation)
//   healthkit HealthKit reads — the app's heaviest repeated I/O. Every
//             quantity read funnels through `quantitySamples`; the sleep
//             cache refresh and segment loads carry their own spans
//   aria      an ARIA turn end to end
//   store     context-store ingest / compact / file-budget work
//
// Rules:
//   • Names are StaticString — no string building, no allocations
//     beyond the signpost itself, and a no-op when nothing is
//     listening (signposts are compiled-in but nearly free when no
//     recorder is attached).
//   • Durations only — never log sample values, user text or anything
//     derived from health data. Signposts carry fixed operation names
//     and structure, nothing else: traces are exportable and health
//     data is not. `StaticString` names make attaching payloads
//     impossible, by design.
//   • A Span may cross await points (begin/end is manual). `measure`
//     wraps synchronous or async blocks and always ends the interval,
//     including on throw.

public enum ForgePerf {

    public enum Category: String, CaseIterable, Sendable {
        case launch
        case healthkit
        case aria
        case store
    }

    /// One subsystem for every target — see the header comment.
    public static let subsystem = "com.forge.core"

    private static let signposters: [Category: OSSignposter] = {
        var map: [Category: OSSignposter] = [:]
        // `OSSignposter` takes StaticString, so each category is spelled
        // out here instead of built from `rawValue`.
        map[.launch] = OSSignposter(subsystem: "com.forge.core", category: "launch")
        map[.healthkit] = OSSignposter(subsystem: "com.forge.core", category: "healthkit")
        map[.aria] = OSSignposter(subsystem: "com.forge.core", category: "aria")
        map[.store] = OSSignposter(subsystem: "com.forge.core", category: "store")
        return map
    }()

    private static func signposter(for category: Category) -> OSSignposter {
        // The map is built from Category.allCases, so this is always present.
        guard let poster = signposters[category] else {
            fatalError("ForgePerf is missing a signposter for \(category.rawValue)")
        }
        return poster
    }

    /// A manually ended interval. Safe to hold across await points; end
    /// it exactly once with `end()`.
    public struct Span {
        private let signposter: OSSignposter
        private let name: StaticString
        private let state: OSSignpostIntervalState

        fileprivate init(
            signposter: OSSignposter,
            name: StaticString,
            state: OSSignpostIntervalState
        ) {
            self.signposter = signposter
            self.name = name
            self.state = state
        }

        public func end() {
            signposter.endInterval(name, state)
        }
    }

    /// Begin a named interval in a category. Pair with `Span.end()`.
    ///
    /// Each interval gets its own signpost ID, so concurrent spans with
    /// the same name (two `quantitySamples` in flight at once, say) pair
    /// correctly in Instruments instead of interleaving.
    public static func begin(_ name: StaticString, category: Category) -> Span {
        let poster = signposter(for: category)
        let id = poster.makeSignpostID()
        return Span(
            signposter: poster,
            name: name,
            state: poster.beginInterval(name, id: id)
        )
    }

    /// A point event with no duration — "this happened".
    public static func event(_ name: StaticString, category: Category) {
        signposter(for: category).emitEvent(name)
    }

    /// Measure a synchronous block. The interval always closes, also on throw.
    @discardableResult
    public static func measure<T>(
        _ name: StaticString,
        category: Category,
        _ body: () throws -> T
    ) rethrows -> T {
        let poster = signposter(for: category)
        let id = poster.makeSignpostID()
        let state = poster.beginInterval(name, id: id)
        defer { poster.endInterval(name, state) }
        return try body()
    }

    /// Measure an async block — awaits inside the interval are included.
    /// `async rethrows` mirrors the synchronous variant: call sites with a
    /// non-throwing block stay free of `try`.
    @discardableResult
    public static func measure<T>(
        _ name: StaticString,
        category: Category,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let poster = signposter(for: category)
        let id = poster.makeSignpostID()
        let state = poster.beginInterval(name, id: id)
        defer { poster.endInterval(name, state) }
        return try await body()
    }
}
