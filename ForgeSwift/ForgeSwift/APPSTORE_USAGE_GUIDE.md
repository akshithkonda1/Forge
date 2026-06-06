# AppStore Usage Guide

## Overview

The refactored `AppStore` is now a production-ready state management solution with:

- ✅ **AI Integration** - Uses Apple's Foundation Models (iOS 18.2+) with automatic fallback
- ✅ **Protocol-based architecture** - Easy to extend or swap AI providers
- ✅ **Context-aware responses** - Passes full user context to AI for personalized coaching
- ✅ **Async/await** - Modern Swift concurrency for chat responses
- ✅ **Computed properties** - Readiness trends, workout recommendations
- ✅ **Automatic metric recalculation** - Updates readiness when metrics change
- ✅ **Better data management** - Methods for updating profiles, sleep, PRs

---

## Key Changes

### 1. AI Response Architecture

#### **Protocol-based Design**
```swift
protocol TrainerResponseGenerator {
    func generateResponse(for input: String, context: TrainerContext) async throws -> TrainerResponse
}
```

Two implementations:
- **`FoundationModelsResponseGenerator`** - Uses Apple's on-device LLM (iOS 18.2+)
- **`RuleBasedResponseGenerator`** - Fallback rule-based system (always available)

#### **TrainerContext**
All relevant user data is packaged into a context object:
```swift
struct TrainerContext {
    let userProfile: UserProfile
    let readiness: ReadinessData
    let dailyMetrics: DailyMetrics
    let sleepData: [SleepData]
    let workoutHistory: [WorkoutHistory]
    let currentTime: Date
    let conversationHistory: [ChatMessage]
}
```

#### **TrainerResponse**
Structured response with confidence scores:
```swift
struct TrainerResponse {
    let content: String
    let richCard: RichCardData?
    let suggestedActions: [String]?
    let confidence: Double // 0.0 to 1.0
}
```

---

### 2. Using the AI Chat System

#### **Async Message Sending (Recommended)**
```swift
// In your SwiftUI view
@EnvironmentObject var appStore: AppStore

func sendChatMessage() {
    Task {
        await appStore.sendMessage("What should I train today?")
    }
}
```

#### **With Loading State**
```swift
struct ChatView: View {
    @EnvironmentObject var appStore: AppStore
    @State private var inputText = ""
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(appStore.chatMessages) { message in
                    MessageBubble(message: message)
                }
                
                if appStore.isGeneratingResponse {
                    TypingIndicator()
                }
            }
            
            HStack {
                TextField("Ask your trainer...", text: $inputText)
                Button("Send") {
                    let text = inputText
                    inputText = ""
                    Task {
                        await appStore.sendMessage(text)
                    }
                }
                .disabled(appStore.isGeneratingResponse || inputText.isEmpty)
            }
        }
    }
}
```

---

### 3. Data Management Methods

#### **Update Metrics (e.g., from HealthKit)**
```swift
// Update specific metrics
appStore.updateMetrics(
    hrv: 58,
    restingHR: 55,
    deepSleep: 105,
    totalSleep: 450
)

// Automatically recalculates readiness score
```

#### **Add Sleep Data**
```swift
let sleep = SleepData(
    date: "2026-04-27",
    totalHours: 7.5,
    deepMinutes: 110,
    remMinutes: 95,
    lightMinutes: 220,
    awakeMinutes: 15,
    score: 92
)
appStore.addSleepData(sleep)
```

#### **Update Personal Records**
```swift
// Automatically checks if it's a new PR
appStore.updatePersonalRecord(
    exercise: "Bench Press",
    value: 235,
    unit: "lbs"
)
```

#### **Update Profile**
```swift
appStore.updateProfile(
    name: "Alex",
    coachingStyle: .balanced,
    fitnessGoals: [.buildMuscle, .improveEndurance],
    experienceLevel: .advanced
)
```

---

### 4. Computed Properties

#### **Weekly Workout Frequency**
```swift
let frequency = appStore.weeklyWorkoutFrequency
// Returns number of workouts in the past 7 days
```

#### **Readiness Trend**
```swift
switch appStore.readinessTrend {
case .improving:
    print("📈 Your recovery is improving")
case .declining:
    print("📉 Take it easy, you might be overreaching")
case .stable:
    print("➡️ Consistent recovery")
}
```

#### **Should Train Today?**
```swift
if appStore.shouldTrainToday {
    // Readiness >= 50
    showWorkoutView()
} else {
    showRecoveryAdvice()
}
```

#### **Recommended Intensity**
```swift
let intensity = appStore.recommendedIntensity
// Returns: .low, .moderate, or .high based on readiness
```

---

### 5. Foundation Models Integration

#### **Check Availability**
```swift
if appStore.aiModelAvailable {
    // Using Apple's on-device LLM
    Text("Powered by Apple Intelligence")
} else {
    // Using rule-based fallback
    Text("Using offline trainer")
}
```

#### **Custom Instructions**
The AI is initialized with custom instructions that define its personality:
```swift
let instructions = """
You are an AI personal trainer named Forge. You provide personalized fitness coaching 
with a direct, authentic, and knowledgeable tone.

Your communication style:
- Be conversational and real, not overly formal
- Reference specific biometric data when relevant (HRV, sleep, readiness scores)
- Adapt training recommendations based on recovery metrics
- Balance empathy with accountability
- Provide actionable, specific guidance
"""
```

---

## Migration Guide

### From Old Code:
```swift
// ❌ Old synchronous approach
let (content, card) = appStore.trainerResponse(for: "Hello")
```

### To New Code:
```swift
// ✅ New async approach
Task {
    await appStore.sendMessage("Hello")
}

// The response appears automatically in appStore.chatMessages
```

### Backward Compatibility
The old `trainerResponse(for:)` method still exists but returns placeholder text immediately. **Use `sendMessage(_:)` for real AI responses.**

---

## Example: Complete Chat Flow

```swift
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appStore: AppStore
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appStore.chatMessages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        
                        if appStore.isGeneratingResponse {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Thinking...")
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: appStore.chatMessages.count) { _ in
                    if let lastMessage = appStore.chatMessages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input
            HStack(spacing: 12) {
                TextField("Ask your trainer...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .lineLimit(1...5)
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(messageText.isEmpty ? .secondary : .blue)
                }
                .disabled(messageText.isEmpty || appStore.isGeneratingResponse)
            }
            .padding()
        }
        .navigationTitle("Trainer Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        messageText = ""
        isInputFocused = false
        
        Task {
            await appStore.sendMessage(text)
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)
                
                if let richCard = message.richCard {
                    RichCardView(card: richCard)
                }
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .trainer {
                Spacer()
            }
        }
    }
}
```

---

## Testing

### Test with Mock Data
```swift
// The AppStore is already initialized with mock data
let appStore = AppStore()

// Mock data includes:
// - mockChatMessages: Sample conversation history
// - mockSleepData: 14 days of sleep data
// - mockWorkoutHistory: 10 recent workouts
// - mockPersonalRecords: 5 PRs
```

### Test AI Responses
```swift
// iOS 18.2+ device
let appStore = AppStore()
Task {
    await appStore.sendMessage("What should I train today?")
    // Check appStore.chatMessages for response
}
```

### Test Readiness Calculation
```swift
let appStore = AppStore()
appStore.updateMetrics(
    hrv: 35,
    restingHR: 72,
    deepSleep: 45,
    totalSleep: 360
)

print(appStore.readiness.overall) // Should be low
print(appStore.recommendedIntensity) // Should be .low
```

---

## Future Enhancements

### 1. Persistence Layer
Add SwiftData or Core Data for persistence:
```swift
// TODO: Save state to disk
func saveState() {
    // Persist chatMessages, workoutHistory, etc.
}
```

### 2. HealthKit Integration
```swift
// TODO: Real HealthKit integration
func syncHealthData() async {
    let healthStore = HKHealthStore()
    // Fetch HRV, sleep, heart rate, etc.
    // Call updateMetrics() with real data
}
```

### 3. Remote API Integration
```swift
// TODO: Backend API for workout plans
func fetchWorkoutPlan() async throws -> WorkoutPlan {
    let url = URL(string: "https://api.forge.app/workouts/daily")!
    // Fetch and decode
}
```

### 4. Streaming Responses
```swift
// TODO: Stream AI responses token-by-token
func streamMessage(_ text: String) async throws {
    for try await chunk in responseGenerator.streamResponse(for: text, context: context) {
        // Update UI with partial response
    }
}
```

---

## Best Practices

1. **Always use async/await** for chat: `await appStore.sendMessage()`
2. **Check `isGeneratingResponse`** to show loading states
3. **Update metrics regularly** to keep readiness accurate
4. **Use computed properties** like `readinessTrend` and `shouldTrainToday`
5. **Handle AI unavailability gracefully** - fallback always works
6. **Test on real devices** for Foundation Models (Simulator may not support it)

---

## Platform Requirements

- **iOS 18.2+**: Foundation Models (on-device AI)
- **iOS 15+**: Rule-based fallback (always works)

---

## Questions?

- Check `CHATVIEW_USAGE_GUIDE.md` for UI integration examples
- Review `Models.swift` for data structures
- See `FoundationModelsResponseGenerator` for AI implementation details
