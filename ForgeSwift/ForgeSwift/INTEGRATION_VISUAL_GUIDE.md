# Voice Coach Integration — Visual Guide

## 🎯 Before & After

### BEFORE (Static Coach Messages)

```
┌─────────────────────────────────────────────────┐
│  ActiveWorkoutView                              │
│                                                 │
│  Header: [Time] [End]                          │
│                                                 │
│  Exercise: Bench Press                         │
│  Set 2 of 3 • 185 lbs × 8 reps                │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 🤖 "Control the weight — don't let it    │ │
│  │     control you"                          │ │
│  │     (Cycles through 8 static messages)   │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘

❌ No voice
❌ Not contextual
❌ Can't ask questions
❌ Generic advice
```

### AFTER (AI Voice Coach)

```
┌─────────────────────────────────────────────────┐
│  ActiveWorkoutView                              │
│                                                 │
│  Header: [Time] [🔊] [End]  ← Voice toggle     │
│                                                 │
│  Exercise: Bench Press                         │
│  Set 2 of 3 • 185 lbs × 8 reps                │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 🤖 "You're at 155 BPM — that's Zone 4.   │ │
│  │     Take the full 90 seconds rest before  │ │
│  │     your next set."               [🎤]    │ │
│  │     ↑                               ↑      │ │
│  │     Contextual AI response         Mic    │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘

✅ Voice announcements
✅ Context-aware (knows your HR, set, exercise)
✅ Ask anything via voice
✅ Personalized coaching
```

---

## 📊 Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  USER INTERACTION                                            │
│  ┌──────────────┐        ┌──────────────┐                  │
│  │ Tap Voice    │   OR   │ Tap Mic      │                  │
│  │ Toggle       │        │ Button       │                  │
│  └──────┬───────┘        └──────┬───────┘                  │
│         │                       │                            │
│         ▼                       ▼                            │
│  ┌──────────────┐        ┌──────────────┐                  │
│  │ Mute/Unmute  │        │ Start Voice  │                  │
│  │ TTS          │        │ Recognition  │                  │
│  └──────────────┘        └──────┬───────┘                  │
│                                  │                           │
└──────────────────────────────────┼───────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────┐
                    │  AVAudioEngine           │
                    │  (Captures microphone)   │
                    └──────────┬───────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │  SFSpeechRecognizer      │
                    │  (Speech → Text)         │
                    └──────────┬───────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │  Silence Timer (1.8s)    │
                    │  Detects end of speech   │
                    └──────────┬───────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │  Build Context           │
                    │  - Workout name          │
                    │  - Exercise              │
                    │  - Current set           │
                    │  - Heart rate (155)      │
                    │  - HR zone (4)           │
                    │  - Calories (243)        │
                    │  - Elapsed time (14:32)  │
                    └──────────┬───────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │  Call Claude API         │
                    │  POST /v1/messages       │
                    │  {                       │
                    │    model: "claude-...",  │
                    │    messages: [...],      │
                    │    system: "You are..."  │
                    │  }                       │
                    └──────────┬───────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │  Claude AI Response      │
                    │  "You're at 155 BPM..."  │
                    └──────────┬───────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │  AVSpeechSynthesizer     │
                    │  (Text → Speech)         │
                    └──────────┬───────────────┘
                               │
                               ▼
                    ┌──────────────────────────┐
                    │  Audio Output            │
                    │  🔊 Speaker/Headphones   │
                    └──────────────────────────┘
```

---

## 🔄 State Management Flow

### State Variables in VoiceCoachManager

```swift
@Observable class VoiceCoachManager {
    // UI drives on these:
    var isListening: Bool = false      // 🔴 Mic button active
    var isSpeaking: Bool = false       // 🟢 Coach is talking
    var isThinking: Bool = false       // 🟠 Waiting for Claude
    var lastCoachMessage: String = ""  // 💬 Display in UI
    var transcribedText: String = ""   // 👂 "Should I..."
    var error: String? = nil           // ❌ Error message
    var isVoiceEnabled: Bool = true    // 🔊 Master toggle
}
```

### State Transitions

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  IDLE STATE                                             │
│  • isListening = false                                  │
│  • isSpeaking = false                                   │
│  • isThinking = false                                   │
│  • lastCoachMessage = (previous message)                │
│                                                         │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
        ▼                         ▼
┌────────────────┐      ┌──────────────────┐
│ User taps mic  │      │ Workout event    │
└────────┬───────┘      │ (set complete)   │
         │              └─────────┬────────┘
         ▼                        │
┌────────────────┐                │
│ LISTENING      │                │
│ isListening=ON │                │
│ "Listening..." │                │
└────────┬───────┘                │
         │                        │
         ▼                        │
┌────────────────┐                │
│ User speaks    │                │
│ "Should I..."  │                │
│ transcribedText│                │
│ updates        │                │
└────────┬───────┘                │
         │                        │
         ▼                        │
┌────────────────┐                │
│ 1.8s silence   │                │
│ detected       │                │
└────────┬───────┘                │
         │                        │
         ▼                        ▼
┌─────────────────────────────────────┐
│ THINKING                            │
│ isListening = OFF                   │
│ isThinking = ON                     │
│ "Thinking..." + spinner             │
└────────────────┬────────────────────┘
                 │
                 ▼
       ┌─────────────────┐
       │ Claude API call │
       └────────┬────────┘
                │
                ▼
┌────────────────────────────────────┐
│ SPEAKING                           │
│ isThinking = OFF                   │
│ isSpeaking = ON                    │
│ lastCoachMessage = response        │
│ AVSpeechSynthesizer plays audio    │
└────────────────┬───────────────────┘
                 │
                 ▼
       ┌─────────────────┐
       │ Speech finishes │
       └────────┬────────┘
                │
                ▼
┌────────────────────────────────────┐
│ IDLE (with new message)            │
│ isSpeaking = OFF                   │
│ lastCoachMessage persists          │
└────────────────────────────────────┘
```

---

## 🎨 UI Component Hierarchy

```
ActiveWorkoutView
├── Header HStack
│   ├── Timer display
│   ├── VoiceToggleButton ← NEW
│   │   └── Shows: 🔊 (on) or 🔇 (off)
│   └── End button
│
├── Exercise details
│   ├── Exercise name
│   ├── Weight × Reps
│   └── Rest time
│
└── VoiceCoachBar ← NEW (replaces CoachBarView)
    ├── AI Icon (🤖)
    │   └── Status indicator
    │       ├── 🔴 Red dot (listening)
    │       ├── 🟢 Green dot (speaking)
    │       └── 🟠 Orange dot (thinking)
    │
    ├── Message area
    │   ├── "Listening..." (when active)
    │   ├── "Thinking..." (with spinner)
    │   ├── "🎙️ Speaking..." (when TTS)
    │   └── lastCoachMessage (default)
    │
    └── Mic button
        └── Tap to start/stop listening
```

---

## 📝 Code Changes Summary

### File: `ActiveWorkoutView` (in WorkoutView.swift)

```diff
struct ActiveWorkoutView: View {
    @EnvironmentObject var store: AppStore
    
    // ... existing state
-   @State private var coachIndex: Int = 0
-   @State private var coachTimer: Timer? = nil
+   @State private var voiceCoach = VoiceCoachManager()
    
    var body: some View {
        VStack(spacing: 0) {
            if let exercise = currentExercise {
                workoutContent(exercise: exercise)
            }
        }
        .background(Color.background.ignoresSafeArea())
        .onAppear { startTimers() }
        .onDisappear { stopTimers() }
    }
    
    func workoutContent(exercise: Exercise) -> some View {
        // Header
        HStack {
            // ...
-           HStack(spacing: 14) {
+           HStack(spacing: 10) {
                HStack(spacing: 5) { /* timer */ }
+               VoiceToggleButton(coach: voiceCoach)
                Button(action: handleEnd) { /* End */ }
            }
        }
        
        // ... exercise details ...
        
        // Coach bar
-       CoachBarView(message: coachMsgs[coachIndex % coachMsgs.count])
+       VoiceCoachBar(coach: voiceCoach)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 8)
    }
    
    func startTimers() {
+       voiceCoach.updateContext(buildContext())
+       voiceCoach.announceWorkoutStart()
        
        elapsedTimer = Timer.scheduledTimer(...) { _ in
            elapsedTime += 1
+           if elapsedTime % 5 == 0 {
+               voiceCoach.updateContext(buildContext())
+           }
        }
        
        hrTimer = Timer.scheduledTimer(...) { _ in
            // ... HR simulation ...
+           if simulatedHR > 170 {
+               voiceCoach.announceHRWarning(hr: simulatedHR)
+           }
        }
        
        calTimer = Timer.scheduledTimer(...) { /* cals */ }
-       coachTimer = Timer.scheduledTimer(...) { /* removed */ }
    }
    
    func stopTimers() {
        elapsedTimer?.invalidate(); elapsedTimer = nil
        hrTimer?.invalidate(); hrTimer = nil
        calTimer?.invalidate(); calTimer = nil
        restTimer?.invalidate(); restTimer = nil
-       coachTimer?.invalidate(); coachTimer = nil
+       voiceCoach.stopListening()
    }
    
    func completeSet() {
        guard let exercise = currentExercise else { return }
        let isLastSet = store.currentSet >= exercise.sets
        let isLastEx = store.currentExerciseIndex >= exercises.count - 1

        if isLastSet && isLastEx {
+           voiceCoach.announceWorkoutComplete(
+               duration: formatTime(elapsedTime),
+               calories: Int(estimatedCals)
+           )
            store.endWorkout()
            return
        }
        
        if isLastSet {
            store.nextExercise()
+           let nextName = exercises[store.currentExerciseIndex].name
+           voiceCoach.announceRestOver(nextExerciseName: nextName)
        } else {
            store.nextSet()
+           voiceCoach.announceSetComplete(
+               setNumber: store.currentSet - 1,
+               totalSets: exercise.sets,
+               restSeconds: exercise.restSeconds
+           )
        }
        
+       voiceCoach.updateContext(buildContext())
        startRest(seconds: exercise.restSeconds)
    }
    
+   func buildContext() -> WorkoutContext {
+       WorkoutContext(
+           workoutName: store.todayWorkout?.name ?? "",
+           exerciseName: currentExercise?.name ?? "",
+           currentSet: store.currentSet,
+           sets: currentExercise?.sets ?? 0,
+           reps: currentExercise?.reps ?? "",
+           weight: currentExercise?.weight.map { "\($0)" } ?? "bodyweight",
+           elapsedTime: formatTime(elapsedTime),
+           heartRate: simulatedHR,
+           hrZone: hrZone(for: simulatedHR).number,
+           calories: Int(estimatedCals),
+           restSeconds: currentExercise?.restSeconds ?? 90,
+           notes: currentExercise?.notes ?? ""
+       )
+   }
}
```

---

## 🧩 Integration Checklist

Use this as you integrate:

### Pre-Integration
- [ ] Read `VOICE_COACH_INTEGRATION_GUIDE.md` fully
- [ ] Have Anthropic API key ready
- [ ] Backup current project (commit to git)

### File Setup
- [ ] Add `VoiceCoachManager.swift` to project ✅ (already done)
- [ ] Add `VoiceCoachIntegration.swift` to project
- [ ] Ensure both files are in your app target

### Code Changes
- [ ] Add `@State private var voiceCoach` to ActiveWorkoutView
- [ ] Remove old `coachIndex` and `coachTimer` state
- [ ] Update header HStack (add VoiceToggleButton)
- [ ] Replace CoachBarView with VoiceCoachBar
- [ ] Update `startTimers()` with voice announcements
- [ ] Update `stopTimers()` to stop listening
- [ ] Update `completeSet()` with voice triggers
- [ ] Add `buildContext()` helper function
- [ ] Add `hrZone()` function (if not exists)

### Configuration
- [ ] Add microphone permission to Info.plist
- [ ] Add speech recognition permission to Info.plist
- [ ] Add ANTHROPIC_API_KEY to Info.plist
- [ ] Verify API key is correct

### Testing
- [ ] Build project (⌘B) — should compile
- [ ] Run on real device (speech doesn't work well in Simulator)
- [ ] Grant microphone permission when prompted
- [ ] Grant speech recognition permission when prompted
- [ ] Start a workout
- [ ] Verify voice announcement on workout start
- [ ] Complete a set → verify voice announcement
- [ ] Tap mic button → verify "Listening..." appears
- [ ] Speak a question → verify transcription shows
- [ ] Wait for response → verify TTS plays
- [ ] Tap voice toggle → verify announcements stop

### Polish
- [ ] Adjust TTS voice speed if needed
- [ ] Customize system prompt personality
- [ ] Test with Bluetooth headphones
- [ ] Test in noisy environment
- [ ] Verify works with music playing (ducking)

### Production (when ready)
- [ ] Move API key to backend proxy
- [ ] Add rate limiting
- [ ] Add error handling UI
- [ ] Add conversation history view
- [ ] Test extensively on real workouts

---

## ✅ You're All Set!

If you've followed this guide, you should now have:

1. ✅ Voice announcements at key workout moments
2. ✅ AI-powered question answering
3. ✅ Context-aware coaching
4. ✅ Clean, animated UI
5. ✅ Professional speech recognition & TTS

**Next**: Build & run on a real device, start a workout, and experience the future of fitness coaching! 💪

---

*For detailed troubleshooting, see `VOICE_COACH_INTEGRATION_GUIDE.md`*  
*For quick code snippets, see `QUICK_INTEGRATION_SNIPPET.swift`*  
*For full documentation, see `README_VOICE_COACH.md`*
