// swift-tools-version: 6.3
import PackageDescription

// ForgeCore — shared foundation for the Forge iOS app and ForgeWatch.
//
// Everything in here is deliberately UI-framework-light: design tokens,
// readiness math, mindfulness practice definitions, the context-aware
// suggestion engine, and thin HealthKit query helpers. The suggestion
// engine and readiness calculator are pure Swift so they can be unit
// tested without a device or simulator.
//
// SPM platforms are a floor, not the shipping OS. Tools 6.4 is only required
// for the `.iOS(.v27)` literal; 6.3.3 (Xcode 26.6) cannot resolve that package
// at all, so the floor stays 18 / 11 and the Xcode project still sets 26.5–27.
// macOS is listed so `swift test` works on CI without an iOS simulator.
let package = Package(
    name: "ForgeCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v18),
        .watchOS(.v11),
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
                "HealthKit/FakeCalendarPack.swift",
                "HealthKit/FakeCycleOverlay.swift",
                "HealthKit/LifeIngestError.swift",
                "HealthKit/TestReadyLaunchPolicy.swift",
                "Intelligence/AriaGuidancePolicy.swift",
                "Intelligence/AriaKnowledgeLedger.swift",
                "Intelligence/AriaHealthRiskMonitor.swift",
                "Intelligence/AriaIntentResolver.swift",
                "Intelligence/ContextualParsingEngine.swift",
                "Intelligence/AriaPromptCorrelation.swift",
                "Intelligence/AriaReplyVariety.swift",
                "Intelligence/AriaReferenceCatalog.swift",
                "Intelligence/CircadianRhythm.swift",
                "Intelligence/ScheduleCorrector.swift",
                "Intelligence/SleepWakeAdaptation.swift",
                "Intelligence/OnlineStat.swift",
                "Intelligence/SleepDepthScorer.swift",
                "Intelligence/HydrationEngine.swift",
                "Intelligence/ContextRules.swift",
                "Intelligence/HabitEngine.swift",
                "Intelligence/HabitFeedbackStore.swift",
                "Intelligence/OnboardingGraph.swift",
                "Intelligence/MindfulnessSuggestionEngine.swift",
                "Intelligence/SessionClock.swift",
                "Intelligence/SleepStoryEngine.swift",
                "Intelligence/SmartStackRelevance.swift",
                "Intelligence/WindDownPredictor.swift",
                "Intelligence/WorkoutCoaching.swift",
                "Intelligence/WorkoutSuggestionEngine.swift",
                "Intelligence/QualityOfLifeCalculator.swift",
                "Models/HealthDeviceCatalog.swift",
                "Models/HRZones.swift",
                "Models/LifestyleContext.swift",
                "Models/MindfulnessPractice.swift",
                "Models/PartnerInvitePayload.swift",
                "Models/CycleRhythmModels.swift",
                "Models/SupportedPersonMatch.swift",
                "Models/Readiness.swift",
                "Models/SleepModels.swift",
                "Models/WatchARIAContext.swift",
                "Models/WatchVitalsPayload.swift",
                "Models/WorkoutLiveState.swift",
                "Models/WorkoutModels.swift",
                "Auth/ForgeAuthModels.swift",
                "Security/SecureStore.swift",
                "Security/SecureStoreMigration.swift",
                "Security/CycleVault.swift",
                "Utils/CompanionConfig.swift",
                "Utils/PublishGate.swift",
                "Utils/WatchSnapshotStore.swift",
                "Utils/HomeWidgetSnapshot.swift",
                "Utils/PartnerSupportGlance.swift",
                "Cloud/ForgeCloudContracts.swift",
            ]
        ),
        .testTarget(
            name: "ForgeCoreTests",
            dependencies: ["ForgeCore"],
            path: "Tests/ForgeCoreTests",
            // Explicit sources only — never pick up Finder " 2.swift" duplicates.
            sources: [
                "CircadianRhythmTests.swift",
                "CycleVaultTests.swift",
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
                "AriaHealthRiskMonitorTests.swift",
                "AriaIntentResolverTests.swift",
                "ContextualParsingEngineTests.swift",
                "AriaPromptCorrelationTests.swift",
                "AriaReplyVarietyTests.swift",
                "AriaReferenceCatalogTests.swift",
                "ScheduleCorrectorTests.swift",
                "SleepWakeAdaptationTests.swift",
                "SleepDepthScorerTests.swift",
                "OnboardingGraphTests.swift",
                "FakeHealthPackTests.swift",
                "FakeCalendarPackTests.swift",
                "TestReadyLaunchPolicyTests.swift",
                "FakeCycleOverlayTests.swift",
                "LifeIngestErrorTests.swift",
                "ForgeAuthTests.swift",
                "CognitoRefreshTests.swift",
                "ReadinessCalculatorTests.swift",
                "QualityOfLifeCalculatorTests.swift",
                "AriaKnowledgeLedgerTests.swift",
                "EventTrainingPolicyTests.swift",
                "SleepIntelligenceTests.swift",
                "SmartStackRelevanceTests.swift",
                "WorkoutCoachingTests.swift",
                "WorkoutModelsTests.swift",
                "ForgeCloudContractsTests.swift",
            ]
        ),
    ],
    // ForgeCore is still Swift 5. Do not silently switch into Swift 6 mode.
    swiftLanguageModes: [.v5]
)
