import Foundation

/// The only door from production chat into the Dummy orchestra.
///
/// `AriaDummyOrchestrator` and its `AriaDummyTurn` helpers compile only when
/// the `FORGE_DUMMY_ORCHESTRA` condition is set. Debug and TestFlight
/// (Release) set it through the project's `FORGE_DUMMY_ORCHESTRA_CONDITION`
/// build setting; a production archive passes
/// `FORGE_DUMMY_ORCHESTRA_CONDITION=` and the Dummy compiles out.
///
/// Production code talks to this seam, never to the orchestrator type, so a
/// stripped (or deleted) Dummy leaves every caller compiling: `provider` is
/// nil, `AriaOperatingMode` never resolves to `.dummy`, tester mode
/// (`AriaService.shouldUseTestReadyDummy`) is off, and chat falls through to
/// Local testing / Live. See docs/aria-dummy-cutover.md.
@MainActor
protocol AriaDummyOrchestraProviding {
    func reply(
        text: String,
        store: AppStore,
        agent: AriaCoachAgent,
        agents: [String]?,
        replay: Bool
    ) async -> AriaResponse

    func seal(_ response: AriaResponse, prompt: String, store: AppStore)
}

@MainActor
enum AriaDummyOrchestra {
    /// Nil in a production build (Dummy compiled out).
    static var provider: (any AriaDummyOrchestraProviding)? {
        #if FORGE_DUMMY_ORCHESTRA
        return AriaDummyOrchestratorProvider()
        #else
        return nil
        #endif
    }

    /// True in builds that carry the Dummy (Debug, TestFlight). A compile-time
    /// constant, so any isolation may read it.
    nonisolated static var isCompiledIn: Bool {
        #if FORGE_DUMMY_ORCHESTRA
        return true
        #else
        return false
        #endif
    }
}
