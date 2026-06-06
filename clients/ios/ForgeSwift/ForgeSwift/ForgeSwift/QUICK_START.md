# Quick Start Guide - AI-Powered AppStore

## 5-Minute Implementation

### Step 1: Replace Your ChatView Send Logic

**Before:**
```swift
Button("Send") {
    let response = appStore.trainerResponse(for: inputText)
    // Handle response...
}
```

**After:**
```swift
Button("Send") {
    Task {
        await appStore.sendMessage(inputText)
    }
}
```

### Step 2: Show Loading State

```swift
struct ChatView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(appStore.chatMessages) { message in
                    MessageView(message: message)
                }
                
                // Add this loading indicator
                if appStore.isGeneratingResponse {
                    HStack {
                        ProgressView()
                        Text("Thinking...")
                    }
                }
            }
            
            // Your input field...
        }
    }
}
```

### Step 3: That's It!

Your app now uses:
- ✅ Real AI on iOS 18.2+ devices
- ✅ Automatic fallback on older devices
- ✅ Context-aware responses
- ✅ Proper async handling

---

## Testing

### Test AI is Working

```swift
struct ContentView: View {
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack {
            if appStore.aiModelAvailable {
                Text("✅ AI Available")
                    .foregroundColor(.green)
            } else {
                Text("⚠️ Using Fallback")
                    .foregroundColor(.orange)
            }
            
            Button("Test AI") {
                Task {
                    await appStore.sendMessage("Hello")
                }
            }
        }
    }
}
```

---

## Advanced Usage

### Use Computed Properties

```swift
// Readiness trend
Text("Trend: \(appStore.readinessTrend == .improving ? "📈" : "📉")")

// Weekly frequency
Text("Workouts this week: \(appStore.weeklyWorkoutFrequency)")

// Recommended intensity
Text("Today's intensity: \(appStore.recommendedIntensity)")

// Should train?
if appStore.shouldTrainToday {
    WorkoutButton()
} else {
    RestDayView()
}
```

### Update Metrics from HealthKit

```swift
import HealthKit

func syncHealthData() async {
    let healthStore = HKHealthStore()
    
    // Fetch HRV
    if let hrv = await fetchHRV(from: healthStore) {
        appStore.updateMetrics(hrv: hrv)
    }
    
    // Fetch sleep
    if let sleep = await fetchSleep(from: healthStore) {
        appStore.addSleepData(sleep)
    }
    
    // Readiness automatically recalculates!
}
```

### Custom AI Prompt

To customize the AI's personality, edit the instructions in `FoundationModelsResponseGenerator`:

```swift
let instructions = """
You are an AI personal trainer named Forge.

Your style:
- Direct and motivating
- Reference specific metrics
- Adapt to user's readiness
- Keep responses under 100 words

// Add your custom instructions here
"""
```

---

## Troubleshooting

### "AI not available" on iOS 18.2+

1. Check Settings → Apple Intelligence → Enable
2. Ensure device is compatible (iPhone 15 Pro+, M1+ iPad/Mac)
3. Wait for model to download (Settings → Apple Intelligence → Download)

### Responses seem slow

- **Foundation Models**: 1-3 seconds normal
- **Network issues**: Shouldn't affect (all on-device)
- **Long conversations**: Model processes full history

### Fallback always being used

Check availability:
```swift
if #available(iOS 18.2, *) {
    let model = SystemLanguageModel.default
    print("Status: \(model.availability)")
} else {
    print("iOS version too old")
}
```

---

## Production Checklist

Before shipping:

- [ ] Test on real iOS 18.2+ device
- [ ] Test fallback on iOS 15-18.1
- [ ] Add error handling for AI failures
- [ ] Implement rate limiting (avoid spam)
- [ ] Add user feedback mechanism
- [ ] Monitor AI response quality
- [ ] Set up analytics for AI usage
- [ ] Review Apple's AI guidelines
- [ ] Test with airplane mode (should work)
- [ ] Add accessibility labels

---

## Example: Complete Minimal Chat

```swift
import SwiftUI

@main
struct MyApp: App {
    @StateObject private var appStore = AppStore()
    
    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(appStore)
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var appStore: AppStore
    @State private var input = ""
    
    var body: some View {
        VStack {
            // Messages
            ScrollView {
                ForEach(appStore.chatMessages) { msg in
                    HStack {
                        if msg.role == .user { Spacer() }
                        Text(msg.content)
                            .padding()
                            .background(msg.role == .user ? .blue : .gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        if msg.role == .trainer { Spacer() }
                    }
                }
                
                if appStore.isGeneratingResponse {
                    ProgressView()
                }
            }
            
            // Input
            HStack {
                TextField("Message", text: $input)
                Button("Send") {
                    Task {
                        await appStore.sendMessage(input)
                        input = ""
                    }
                }
                .disabled(input.isEmpty || appStore.isGeneratingResponse)
            }
            .padding()
        }
    }
}
```

That's 30 lines for a full AI chat app! 🎉

---

## Performance Tips

1. **Limit conversation history**: Keep last 10-20 messages
   ```swift
   appStore.chatMessages = Array(appStore.chatMessages.suffix(20))
   ```

2. **Debounce rapid messages**: Prevent spam
   ```swift
   @State private var lastMessageTime = Date.distantPast
   
   func canSendMessage() -> Bool {
       Date().timeIntervalSince(lastMessageTime) > 1.0
   }
   ```

3. **Clear old data**: Reset chat periodically
   ```swift
   Button("New Session") {
       appStore.chatMessages = []
   }
   ```

---

## Next Steps

1. **Read the full guide**: `APPSTORE_USAGE_GUIDE.md`
2. **See advanced UI**: `AI_INTEGRATION_EXAMPLE.swift`
3. **Understand changes**: `REFACTOR_SUMMARY.md`

---

## Need Help?

**Common issues:**

| Problem | Solution |
|---------|----------|
| AI not responding | Check `isGeneratingResponse` state |
| Responses not appearing | Verify `chatMessages` updates |
| Crashes on iOS 15 | Wrap Foundation Models in `#available` |
| Old behavior | Make sure using `sendMessage()` not `trainerResponse()` |

---

## Resources

- [Foundation Models Docs](https://developer.apple.com/documentation/foundationmodels)
- [Apple Intelligence Guidelines](https://developer.apple.com/design/human-interface-guidelines/technologies/generative-ai)
- [Swift Concurrency Guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)

---

**You're ready to ship AI-powered personal training! 🚀**
