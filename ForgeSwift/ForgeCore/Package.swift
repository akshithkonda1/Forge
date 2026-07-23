// swift-tools-version: 5.9
import PackageDescription

// ForgeCore — shared foundation for the Forge iOS app and ForgeWatch.
//
// Everything in here is deliberately UI-framework-light: design tokens,
// readiness math, mindfulness practice definitions, the context-aware
// suggestion engine, and thin HealthKit query helpers. The suggestion
// engine and readiness calculator are pure Swift so they can be unit
// tested without a device or simulator.
let package = Package(
    name: "ForgeCore",
    platforms: [
        // macOS is listed so `swift test` works on CI runners without an
        // iOS/watchOS simulator destination. Production consumers are still
        // the iPhone + Watch apps.
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "ForgeCore", targets: ["ForgeCore"]),
    ],
    targets: [
        .target(
            name: "ForgeCore",
            path: "Sources/ForgeCore",
            exclude: [
                "DesignSystem/ForgeDS 2.swift",
                "DesignSystem/ForgePalette 2.swift",
                "HealthKit/HealthKitQueryHelpers 2.swift",
                "Intelligence/ContextRules 2.swift",
                "Intelligence/MindfulnessSuggestionEngine 2.swift",
                "Intelligence/SleepStoryEngine 2.swift",
                "Intelligence/WindDownPredictor 2.swift",
                "Intelligence/WorkoutSuggestionEngine 2.swift",
                "Models/HRZones 2.swift",
                "Models/LifestyleContext 2.swift",
                "Models/MindfulnessPractice 2.swift",
                "Models/Readiness 2.swift",
                "Models/SleepModels 2.swift",
                "Models/WatchARIAContext 2.swift",
                "Models/WorkoutLiveState 2.swift",
                "Models/WorkoutModels 2.swift",
                "Utils/WatchSnapshotStore 2.swift",
            ]
        ),
        .testTarget(
            name: "ForgeCoreTests",
            dependencies: ["ForgeCore"],
            path: "Tests/ForgeCoreTests",
            exclude: [
                "ContextRulesTests 2.swift",
                "ReadinessCalculatorTests 2.swift",
            ]
        ),
    ]
)
