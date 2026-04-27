import SwiftUI

// MARK: - Voice Coach Integration Guide
// This file provides integration guidance for the Voice Coach system.
// The actual UI components are implemented in VoiceCoachViews.swift

// MARK: - Integration Notes
/*
 To integrate voice coaching into your workout views:
 
 1. Import the VoiceCoachManager as an environment object or pass it as a parameter
 2. Use VoiceCoachBar (from VoiceCoachViews.swift) to replace the old CoachBarView
 3. Use VoiceToggleButton (from VoiceCoachViews.swift) in your header toolbar
 
 Example usage in WorkoutView:
 
     @StateObject private var voiceCoach = VoiceCoachManager()
     
     var body: some View {
         VStack {
             // Your workout content
             
             // Replace old CoachBarView with:
             VoiceCoachBar(coach: voiceCoach)
                 .padding(.horizontal, 20)
                 .padding(.bottom, 20)
         }
     }
 */

