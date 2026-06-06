// ═══════════════════════════════════════════════════════════════
// QUICK INTEGRATION SNIPPET — Copy/paste these exact changes
// ═══════════════════════════════════════════════════════════════

import SwiftUI

/*

// ─────────────────────────────────────────────────
// 1. ADD to ActiveWorkoutView state properties
// ─────────────────────────────────────────────────

@State private var voiceCoach = VoiceCoachManager()

// REMOVE these (no longer needed):
// @State private var coachIndex: Int = 0
// @State private var coachTimer: Timer? = nil

// ─────────────────────────────────────────────────
// 2. REPLACE header HStack in workoutContent()
// ─────────────────────────────────────────────────

// Line ~700: Replace the header HStack with:
HStack(spacing: 10) {
    HStack(spacing: 5) {
        Image(systemName: "clock.fill")
            .font(.system(size: 13))
            .foregroundColor(.textSecondary)
        Text(formatTime(elapsedTime))
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(.textPrimary)
    }
    
    VoiceToggleButton(coach: voiceCoach)   // ← NEW
    
    Button(action: handleEnd) {
        Text(showEndConfirm ? "Confirm" : "End")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(showEndConfirm ? .white : .danger)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(showEndConfirm ? Color.danger : Color.danger.opacity(0.12))
            .cornerRadius(10)
    }
}

// ─────────────────────────────────────────────────
// 3. REPLACE coach bar at bottom of workoutContent()
// ─────────────────────────────────────────────────

// Line ~920: Replace CoachBarView with:
VoiceCoachBar(coach: voiceCoach)
    .padding(.horizontal, 20)
    .padding(.bottom, 20)
    .padding(.top, 8)

// ─────────────────────────────────────────────────
// 4. REPLACE entire startTimers() function
// ─────────────────────────────────────────────────

func startTimers() {
    // Announce workout start
    voiceCoach.updateContext(buildContext())
    voiceCoach.announceWorkoutStart()
    
    elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        elapsedTime += 1
        // Sync context every 5 seconds
        if elapsedTime % 5 == 0 {
            voiceCoach.updateContext(buildContext())
        }
    }

    hrTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
        let target: Double = isResting ? (110 + Double.random(in: 0...20)) : (135 + Double.random(in: 0...30))
        let noise = Double.random(in: -5...5)
        simulatedHR = Int((Double(simulatedHR) + (target - Double(simulatedHR)) * 0.1 + noise).rounded())
        
        // Proactive HR warning
        if simulatedHR > 170 {
            voiceCoach.announceHRWarning(hr: simulatedHR)
        }
    }

    calTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        let rate: Double = simulatedHR > 140 ? 0.18 : simulatedHR > 120 ? 0.14 : 0.10
        estimatedCals += rate
    }
}

// ─────────────────────────────────────────────────
// 5. REPLACE stopTimers() function
// ─────────────────────────────────────────────────

func stopTimers() {
    elapsedTimer?.invalidate(); elapsedTimer = nil
    hrTimer?.invalidate(); hrTimer = nil
    calTimer?.invalidate(); calTimer = nil
    restTimer?.invalidate(); restTimer = nil
    voiceCoach.stopListening()
}

// ─────────────────────────────────────────────────
// 6. REPLACE completeSet() function
// ─────────────────────────────────────────────────

func completeSet() {
    guard let exercise = currentExercise else { return }
    let isLastSet = store.currentSet >= exercise.sets
    let isLastEx = store.currentExerciseIndex >= exercises.count - 1

    if isLastSet && isLastEx {
        voiceCoach.announceWorkoutComplete(
            duration: formatTime(elapsedTime),
            calories: Int(estimatedCals)
        )
        store.endWorkout()
        return
    }
    
    if isLastSet {
        store.nextExercise()
        let nextName = exercises.indices.contains(store.currentExerciseIndex)
            ? exercises[store.currentExerciseIndex].name : ""
        voiceCoach.announceRestOver(nextExerciseName: nextName)
    } else {
        store.nextSet()
        voiceCoach.announceSetComplete(
            setNumber: store.currentSet - 1,
            totalSets: exercise.sets,
            restSeconds: exercise.restSeconds
        )
    }
    
    voiceCoach.updateContext(buildContext())
    startRest(seconds: exercise.restSeconds)
}

// ─────────────────────────────────────────────────
// 7. ADD buildContext() helper function
// ─────────────────────────────────────────────────

func buildContext() -> WorkoutContext {
    WorkoutContext(
        workoutName: store.todayWorkout?.name ?? "",
        exerciseName: currentExercise?.name ?? "",
        currentSet: store.currentSet,
        sets: currentExercise?.sets ?? 0,
        reps: currentExercise?.reps ?? "",
        weight: currentExercise?.weight.map { "\($0)" } ?? "bodyweight",
        elapsedTime: formatTime(elapsedTime),
        heartRate: simulatedHR,
        hrZone: hrZone(for: simulatedHR).number,
        calories: Int(estimatedCals),
        restSeconds: currentExercise?.restSeconds ?? 90,
        notes: currentExercise?.notes ?? ""
    )
}

// ─────────────────────────────────────────────────
// 8. ADD hrZone() function (if not already present)
// ─────────────────────────────────────────────────

struct HRZoneInfo {
    let label: String
    let color: Color
    let number: Int
}

func hrZone(for hr: Int) -> HRZoneInfo {
    switch hr {
    case 0..<100:
        return HRZoneInfo(label: "Zone 1", color: .success, number: 1)
    case 100..<120:
        return HRZoneInfo(label: "Zone 2", color: .success, number: 2)
    case 120..<140:
        return HRZoneInfo(label: "Zone 3", color: .warning, number: 3)
    case 140..<160:
        return HRZoneInfo(label: "Zone 4", color: .ember, number: 4)
    default:
        return HRZoneInfo(label: "Zone 5", color: .danger, number: 5)
    }
}

// ─────────────────────────────────────────────────
// 9. DELETE old code
// ─────────────────────────────────────────────────

// REMOVE private let coachMsgs = [...] (top of file)
// REMOVE @State private var coachIndex (in ActiveWorkoutView)
// REMOVE @State private var coachTimer (in ActiveWorkoutView)
// REMOVE struct CoachBarView (if it exists as separate view)

*/

// ═══════════════════════════════════════════════════════════════
// That's it! See README_VOICE_COACH.md for details
// ═══════════════════════════════════════════════════════════════
