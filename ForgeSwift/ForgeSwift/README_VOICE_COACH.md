# Voice Coach Integration — Complete

## 🎯 What You Have Now

You've successfully integrated a **fully-featured AI voice coach** into your Forge fitness app! Here's what works:

### ✅ Core Features

- **🎙️ Voice Recognition**: Tap mic → speak → AI responds
- **🔊 Text-to-Speech**: Coach speaks announcements and responses
- **🧠 Claude AI Integration**: Powered by Anthropic's Claude Sonnet 4.5
- **📊 Context-Aware**: AI knows exactly where you are in your workout
- **⚡ Real-Time Updates**: HR, calories, sets, time all synced continuously
- **🔕 Voice Toggle**: Mute/unmute with one tap
- **🎬 Proactive Coaching**: Automatic announcements at key moments

### 🎤 Voice Announcements

The coach automatically speaks at these moments:

1. **Workout Start**: "Let's go. Push Day. First up — Bench Press. 3 sets of 8 at 185. Lock in."
2. **Set Complete**: "Set 2 down, 1 to go. 90 seconds."
3. **Rest Over**: "Rest over. Incline Press — let's go."
4. **HR Warning**: "Heart rate at 172. Take an extra 30 seconds before the next set."
5. **Workout Complete**: "That's a wrap. 47:32 of work, 487 calories burned. Well done."

### 💬 AI Conversations

Athletes can ask:

- **"Should I increase weight?"**
- **"How's my form on bench press?"**
- **"Why am I feeling tired on set 3?"**
- **"What's better — high reps or heavy weight?"**

The AI responds based on:
- Current exercise
- Set/rep progress
- Heart rate & zone
- Calories burned
- Exercise notes
- Overall workout context

---

## 📁 Files You Created

| File | Purpose |
|------|---------|
| `VoiceCoachManager.swift` | Core voice coach logic — already in your project ✅ |
| `VoiceCoachIntegration.swift` | SwiftUI UI components (VoiceToggleButton, VoiceCoachBar) |
| `VOICE_COACH_INTEGRATION_GUIDE.md` | Step-by-step integration instructions |
| `QUICK_INTEGRATION_SNIPPET.swift` | Quick copy/paste code snippets |
| `Info.plist.additions.xml` | Required permissions |
| `README_VOICE_COACH.md` | This file — project summary |

---

## 🚀 Quick Start

### 1. Add Files to Xcode

Drag these files into your Xcode project:
- ✅ `VoiceCoachManager.swift` (already done)
- ✅ `VoiceCoachIntegration.swift` (NEW — adds UI components)

### 2. Follow Integration Guide

Open `VOICE_COACH_INTEGRATION_GUIDE.md` and follow **all 12 steps**.

**tl;dr:**
- Add `@State private var voiceCoach = VoiceCoachManager()` to ActiveWorkoutView
- Replace old coach bar with `VoiceCoachBar(coach: voiceCoach)`
- Add voice announcements to `startTimers()`, `completeSet()`, etc.
- Update Info.plist with permissions

### 3. Set API Key

Get your Anthropic API key from: https://console.anthropic.com/settings/keys

Add to Info.plist:
```xml
<key>ANTHROPIC_API_KEY</key>
<string>sk-ant-api03-...</string>
```

### 4. Build & Run

1. **Build** (⌘B) — should compile with no errors
2. **Run on real device** (speech recognition doesn't work well in Simulator)
3. **Grant permissions** when prompted (microphone, speech recognition)
4. **Start a workout**
5. **Listen** for voice announcements
6. **Tap mic** to ask a question

---

## 🎨 UI Components

### VoiceToggleButton

Small circular button in workout header:
- **Active** (orange): Voice enabled
- **Muted** (gray): Voice disabled
- Tap to toggle

### VoiceCoachBar

Replaces the old static coach messages at the bottom:
- **Default**: Shows last message from coach
- **Listening** (red dot): "Listening... 'should I increase weight?'"
- **Thinking** (orange dot + spinner): "Thinking..."
- **Speaking** (green dot): "🎙️ Speaking..."
- **Mic button**: Tap to start/stop listening

---

## 🧪 Testing Checklist

### Basic Functionality

- [ ] App builds successfully
- [ ] Voice toggle button appears in header
- [ ] Voice coach bar appears at bottom
- [ ] Microphone permission requested on first mic tap
- [ ] Speech recognition permission requested

### Voice Announcements

- [ ] Workout start: "Let's go. [workout name]..."
- [ ] Set complete: "Set X down, Y to go..."
- [ ] Rest over: "Rest over. [next exercise]..."
- [ ] HR warning: "Heart rate at XXX..."
- [ ] Workout complete: "That's a wrap..."

### AI Conversations

- [ ] Tap mic → red "Listening..." appears
- [ ] Speak → transcription shows in bar
- [ ] Silence → "Thinking..." appears
- [ ] Response → green "Speaking..." + TTS audio plays
- [ ] Message persists in bar after speaking

### Edge Cases

- [ ] Voice toggle mutes all announcements
- [ ] Voice toggle stops active listening
- [ ] Multiple taps don't crash
- [ ] Works with Bluetooth headphones
- [ ] Doesn't crash if no internet (API error)
- [ ] Handles empty/unclear speech gracefully

---

## 🐛 Common Issues & Fixes

### "Speech recognition not authorized"

**Fix:**
- Go to Settings → Privacy & Security → Speech Recognition
- Enable for your app
- Restart app

### "Microphone not authorized"

**Fix:**
- Go to Settings → Privacy & Security → Microphone
- Enable for your app
- Restart app

### "No audio from TTS"

**Check:**
- Device volume is up
- Silent mode is off
- `isVoiceEnabled` is true
- No Bluetooth devices connected that might be stealing audio

### "Claude API errors"

**Debug:**
- Print `voiceCoach.error` to console
- Verify API key is correct
- Check internet connection
- Confirm API key has credits: https://console.anthropic.com/settings/billing

### "Transcription is gibberish"

**Causes:**
- Too much background noise
- Speaking too quietly/quickly
- Using iOS Simulator (doesn't support speech recognition well)

**Fix:**
- Test on real device
- Speak clearly and at normal pace
- Reduce background noise

### "Voice is too slow/fast"

**Adjust in VoiceCoachManager.swift:**
```swift
utterance.rate = 0.52  // 0.0 (slow) to 1.0 (fast)
```

### "Voice sounds robotic"

**Try different voices:**
```swift
// VoiceCoachManager.swift, speak() function
utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")  // British accent
utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")  // Australian
utterance.voice = AVSpeechSynthesisVoice(language: "en-IE")  // Irish
```

List all available voices:
```swift
AVSpeechSynthesisVoice.speechVoices().forEach { voice in
    print("\(voice.language): \(voice.name)")
}
```

---

## 🎯 Next Steps

### Level 1: Polish (30 min)

- [ ] Adjust TTS voice to your preference
- [ ] Tune silence detection threshold (currently 1.8s)
- [ ] Customize system prompt personality
- [ ] Test with real workouts

### Level 2: Enhancement (2-3 hours)

- [ ] Add conversation history UI (sheet with past messages)
- [ ] Implement suggested questions ("Ask me about..., form, weight, rest")
- [ ] Add haptic feedback when coach speaks
- [ ] Show waveform animation when listening
- [ ] Cache common responses for offline mode

### Level 3: Advanced (1-2 days)

- [ ] Backend API proxy (don't expose API key in app)
- [ ] Streaming responses (word-by-word instead of waiting for full response)
- [ ] Wake word detection ("Hey Forge...")
- [ ] Multi-language support
- [ ] Voice cloning (custom coach voice)
- [ ] Integration with Apple Watch for hands-free coaching

### Level 4: Pro Features (1+ week)

- [ ] Form analysis via camera + Vision framework
- [ ] Integration with real heart rate monitor (HealthKit)
- [ ] Personalized coaching based on workout history
- [ ] Custom workout generation via voice ("Create me a push day")
- [ ] Social sharing of AI coach wisdom
- [ ] Coach leaderboards (most helpful responses)

---

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   ActiveWorkoutView                     │
│  ┌───────────────────────────────────────────────────┐ │
│  │  @State voiceCoach = VoiceCoachManager()         │ │
│  └───────────────────────────────────────────────────┘ │
│                          │                              │
│                          ▼                              │
│         ┌────────────────────────────────┐             │
│         │   VoiceCoachBar (UI)           │             │
│         │   - Shows messages             │             │
│         │   - Mic button                 │             │
│         │   - Status indicators          │             │
│         └────────────────────────────────┘             │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              VoiceCoachManager (@Observable)            │
│  ┌───────────────────────────────────────────────────┐ │
│  │  Published State:                                 │ │
│  │  - isListening, isSpeaking, isThinking           │ │
│  │  - lastCoachMessage, transcribedText             │ │
│  │  - error, isVoiceEnabled                         │ │
│  └───────────────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────────────┐ │
│  │  Speech Recognition (Input):                      │ │
│  │  - SFSpeechRecognizer                            │ │
│  │  - AVAudioEngine                                 │ │
│  │  - Silence detection (Timer)                     │ │
│  └───────────────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────────────┐ │
│  │  AI Processing:                                   │ │
│  │  - Claude API (Anthropic)                        │ │
│  │  - Conversation history                          │ │
│  │  - Workout context injection                     │ │
│  └───────────────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────────────┐ │
│  │  Text-to-Speech (Output):                        │ │
│  │  - AVSpeechSynthesizer                           │ │
│  │  - Audio session management                      │ │
│  │  - Proactive announcements                       │ │
│  └───────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                  WorkoutContext (Data)                  │
│  - Current exercise, set, reps, weight                  │
│  - HR, calories, elapsed time, zone                     │
│  - Exercise notes                                       │
└─────────────────────────────────────────────────────────┘
```

---

## 🔐 Security Best Practices

### ⚠️ Current Setup (Development Only)

Right now, your API key is stored in `Info.plist`:

```swift
private let apiKey: String = {
    Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String ?? ""
}()
```

**This is fine for:**
- Development
- Testing
- Internal demos
- Proof of concept

**NOT acceptable for:**
- App Store release
- Public distribution
- Any app with untrusted users

### ✅ Production Solutions

#### Option 1: Backend Proxy (Recommended)

Create a backend API:

```
User → Your App → Your Backend → Anthropic API
                  ↑
                  API key lives here (safe)
```

**Benefits:**
- API key never leaves your server
- Rate limiting & usage tracking
- Cost control
- Can switch providers without app update

**Example backend (Node.js + Express):**
```javascript
app.post('/api/coach', async (req, res) => {
    const { message, context } = req.body;
    
    // Verify user is authenticated
    if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
    
    // Rate limit check
    if (await isRateLimited(req.user.id)) {
        return res.status(429).json({ error: 'Too many requests' });
    }
    
    // Call Anthropic API with YOUR key (server-side)
    const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-5',
        messages: [{ role: 'user', content: message }],
        system: buildSystemPrompt(context)
    });
    
    res.json({ message: response.content[0].text });
});
```

**Update VoiceCoachManager.swift:**
```swift
private let apiURL = URL(string: "https://your-backend.com/api/coach")!

// Remove direct Anthropic API call
// Add call to your backend instead
```

#### Option 2: iOS Keychain

Store key in Keychain (more secure than Info.plist):

```swift
// KeychainHelper.swift
class KeychainHelper {
    static func saveAPIKey(_ key: String) {
        let data = key.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "anthropic_api_key",
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "anthropic_api_key",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

**Still vulnerable to:**
- Jailbroken devices
- Reverse engineering
- Memory dumps

#### Option 3: Obfuscation (Weak Protection)

**Don't use this as sole protection**, but can add a layer:

```swift
// Obfuscated key (NOT SECURE, just harder to find)
private let apiKey: String = {
    let encoded = "c2stYW50LWFwaT..." // Base64 encoded
    guard let data = Data(base64Encoded: encoded),
          let decoded = String(data: data, encoding: .utf8) else {
        return ""
    }
    return decoded
}()
```

**Attackers can still:**
- Use a debugger
- Intercept network traffic
- Decompile your app

### 🏆 Recommended Production Setup

**For maximum security:**

1. **Backend API proxy** (API key on server)
2. **User authentication** (Firebase Auth, Sign in with Apple)
3. **Rate limiting** (prevent abuse)
4. **Usage tracking** (monitor costs)
5. **HTTPS only** (encrypt network traffic)
6. **Certificate pinning** (prevent MITM attacks)

**Cost:** Minimal — simple backend can run on free tier (Vercel, Railway, Render)

---

## 📈 Performance Tips

### Reduce API Costs

```swift
// VoiceCoachManager.swift

// 1. Shorter responses = cheaper
let body: [String: Any] = [
    "model": "claude-sonnet-4-5",
    "max_tokens": 150,  // ← Limit response length
    // ...
]

// 2. Use cheaper model for simple questions
if isSimpleQuestion(userMessage) {
    model = "claude-haiku-3-5"  // Faster & cheaper
} else {
    model = "claude-sonnet-4-5"  // Smarter but pricier
}

// 3. Cache common responses
private var cachedResponses: [String: String] = [
    "how are you": "I'm here to help you crush this workout!",
    "what's next": "Check the screen for your next exercise.",
    // ...
]
```

### Reduce Latency

```swift
// 1. Pre-warm the API on workout start
func announceWorkoutStart() {
    // Trigger a quick API call to establish connection
    Task {
        _ = try? await callClaude(messages: [
            ["role": "user", "content": "Ready"]
        ])
    }
    speak("Let's go...")
}

// 2. Stream responses (advanced)
// Instead of waiting for full response, stream word-by-word
// Requires Server-Sent Events (SSE) support
```

### Battery Optimization

```swift
// VoiceCoachManager.swift

// 1. Stop audio engine when not listening
func stopListening() {
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)  // ← Important
    // ...
}

// 2. Use on-device speech recognition when possible
recognitionRequest.requiresOnDeviceRecognition = true  // Saves battery + privacy

// 3. Don't sync context too often
// Every 5 seconds is fine — don't do it every second
```

---

## 🎓 Learn More

### Anthropic Claude API
- [API Docs](https://docs.anthropic.com/claude/reference/getting-started-with-the-api)
- [System Prompts Guide](https://docs.anthropic.com/claude/docs/system-prompts)
- [Pricing](https://www.anthropic.com/api)

### Apple Speech Frameworks
- [Speech Framework](https://developer.apple.com/documentation/speech)
- [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)
- [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession)

### SwiftUI Observation
- [@Observable Macro](https://developer.apple.com/documentation/observation/observable())
- [Swift Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)

---

## 🙏 Credits

- **Voice Coach**: Built with Claude Sonnet 4.5 by Anthropic
- **Speech Recognition**: Apple Speech Framework
- **Text-to-Speech**: AVSpeechSynthesizer
- **UI**: SwiftUI + Observation framework
- **Inspiration**: Elite personal trainers, AI assistants, and the future of fitness

---

## 📞 Support

If you run into issues:

1. Check `VOICE_COACH_INTEGRATION_GUIDE.md` troubleshooting section
2. Look for errors in Xcode console
3. Verify all 12 integration steps completed
4. Test permissions in Settings app
5. Try on a real device (not Simulator)

**Still stuck?** Check these:
- API key is correct (test on Anthropic's playground)
- Internet connection is stable
- Microphone works in other apps
- Info.plist permissions are correct
- VoiceCoachIntegration.swift is in your target

---

## 🚀 You're Ready!

You now have a **world-class AI voice coach** integrated into your fitness app. This is the kind of feature that sets apps apart — the blend of:

✅ Real-time context awareness  
✅ Natural language understanding  
✅ Proactive coaching  
✅ Hands-free interaction  
✅ Personalized responses  

**Go build something amazing!** 💪🔥

---

*Last updated: April 16, 2026*
*Version: 1.0.0*
