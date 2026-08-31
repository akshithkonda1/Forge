// swift-tools-version: 6.4
import PackageDescription

// ForgeCore — shared foundation for the Forge iOS app and ForgeWatch.
//
// Everything in here is deliberately UI-framework-light: design tokens,
// readiness math, mindfulness practice definitions, the context-aware
// suggestion engine, and thin HealthKit query helpers. The suggestion
// engine and readiness calculator are pure Swift so they can be unit
// tested without a device or simulator.
//
// Forge is developed against iOS 27 / watchOS 27 (Xcode 27). `.v27`
// needs tools 6.4. macOS stays listed so `swift test` works on CI
// without an iOS/watchOS simulator destination.
let package = Package(
    name: "ForgeCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v27),
        .watchOS(.v27),
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
                "HealthKit/FakeHealthPack.swift",
                "Intelligence/AriaGuidancePolicy.swift",
                "Intelligence/AriaIntentResolver.swift",
                "Intelligence/CircadianRhythm.swift",
                "Intelligence/HydrationEngine.swift",
                "Intelligence/ContextRules.swift",
                "Intelligence/HabitEngine.swift",
                "Intelligence/HabitFeedbackStore.swift",
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
                "Utils/PartnerSupportGlance.swift",
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
                "PartnerSupportGlanceTests.swift",
                "SupportedPersonMatchTests.swift",
                "PublishGateTests.swift",
                "SecureStoreTests.swift",
                "SessionClockTests.swift",
                "AriaIntentResolverTests.swift",
                "FakeHealthPackTests.swift",
                "ForgeAuthTests.swift",
                "CognitoRefreshTests.swift",
                "ReadinessCalculatorTests.swift",
                "SleepIntelligenceTests.swift",
                "SmartStackRelevanceTests.swift",
                "WorkoutCoachingTests.swift",
                "WorkoutModelsTests.swift",
            ]
        ),
    ],
    // tools 6.4 is required for `.iOS(.v27)`, but ForgeCore is still Swift 5.
    // Do not silently switch the package into Swift 6 language mode.
    swiftLanguageModes: [.v5]
)
