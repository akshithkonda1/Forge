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
            // Explicit sources only — never pick up Finder " 2.swift" duplicates.
            path: "Sources/ForgeCore",
            sources: [
                "DesignSystem/ForgeDS.swift",
                "DesignSystem/ForgePalette.swift",
                "HealthKit/HealthKitQueryHelpers.swift",
                "Intelligence/CircadianRhythm.swift",
                "Intelligence/HydrationEngine.swift",
                "Intelligence/ContextRules.swift",
                "Intelligence/MindfulnessSuggestionEngine.swift",
                "Intelligence/SessionClock.swift",
                "Intelligence/SleepStoryEngine.swift",
                "Intelligence/SmartStackRelevance.swift",
                "Intelligence/WindDownPredictor.swift",
                "Intelligence/WorkoutCoaching.swift",
                "Intelligence/WorkoutSuggestionEngine.swift",
                "Models/HealthDeviceCatalog.swift",
                "Models/HRZones.swift",
                "Models/LifestyleContext.swift",
                "Models/MindfulnessPractice.swift",
                "Models/PartnerInvitePayload.swift",
                "Models/SupportedPersonMatch.swift",
                "Models/Readiness.swift",
                "Models/SleepModels.swift",
                "Models/WatchARIAContext.swift",
                "Models/WorkoutLiveState.swift",
                "Models/WorkoutModels.swift",
                "Auth/ForgeAuthModels.swift",
                "Security/SecureStore.swift",
                "Security/SecureStoreMigration.swift",
                "Utils/CompanionConfig.swift",
                "Utils/PublishGate.swift",
                "Utils/WatchSnapshotStore.swift",
                "Utils/HomeWidgetSnapshot.swift",
            ]
        ),
        .testTarget(
            name: "ForgeCoreTests",
            dependencies: ["ForgeCore"],
            path: "Tests/ForgeCoreTests",
            // Explicit sources only — never pick up Finder " 2.swift" duplicates.
            sources: [
                "CircadianRhythmTests.swift",
                "CompanionConfigTests.swift",
                "ContextRulesTests.swift",
                "HealthDeviceCatalogTests.swift",
                "HomeWidgetSnapshotTests.swift",
                "HydrationEngineTests.swift",
                "MindfulnessSuggestionEngineTests.swift",
                "PartnerInvitePayloadTests.swift",
                "SupportedPersonMatchTests.swift",
                "PublishGateTests.swift",
                "SecureStoreTests.swift",
                "SessionClockTests.swift",
                "ForgeAuthTests.swift",
                "CognitoRefreshTests.swift",
                "ReadinessCalculatorTests.swift",
                "SleepIntelligenceTests.swift",
                "SmartStackRelevanceTests.swift",
                "WorkoutCoachingTests.swift",
                "WorkoutModelsTests.swift",
            ]
        ),
    ]
)
