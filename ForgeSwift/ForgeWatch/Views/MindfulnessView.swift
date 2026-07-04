import SwiftUI
import ForgeCore

// MARK: - MindfulnessView
//
// The dedicated session experience: pre-session recommendation → guided
// breathing with the orb + haptics → calm debrief. Complications deep-link
// straight here pre-filled (forgewatch://mindfulness).
//
// Tone contract: nothing on these screens can ever read as pressure.
// Skipping is one tap, acknowledged warmly, and never tracked as a streak
// break.

struct MindfulnessView: View {
    @Environment(WatchHealthKitManager.self) private var health
    @Environment(ContextEngine.self) private var contextEngine
    @Environment(ARIAWatchService.self) private var aria
    @Environment(MindfulnessSessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPractice: PracticeType = .focusReset
    @State private var selectedDuration: TimeInterval = 180
    @State private var showSkipSheet = false
    @State private var didPrefill = false

    var body: some View {
        Group {
            switch session.state {
            case .idle:
                preSession
            case .active, .paused:
                ActiveSessionView()
            case .debrief:
                DebriefView()
            }
        }
        .navigationTitle("Reset")
        .onAppear(perform: prefillFromRecommendation)
    }

    // MARK: Pre-session

    private var preSession: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeDS.Spacing.md) {
                if let ack = session.lastSkipAcknowledgement {
                    Text(ack)
                        .font(.system(size: 12))
                        .foregroundStyle(ForgePalette.textSecondary)
                        .padding(.bottom, ForgeDS.Spacing.xs)
                        .accessibilityLabel(ack)
                }

                // Why this, why now — the ARIA reasoning up front.
                if let reason = currentReason {
                    Text(reason)
                        .font(.system(size: 12.5))
                        .foregroundStyle(ForgePalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                practicePicker
                durationPicker

                HapticButton(haptic: .start) {
                    session.start(practice: selectedPractice, duration: selectedDuration, health: health)
                } label: {
                    Label("Begin", systemImage: "play.fill")
                        .font(ForgeType.caption(15))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedPractice.accentColor.opacity(0.85))
                .foregroundStyle(.black)
                .primaryDoubleTapShortcut() // Double Tap starts the practice
                .accessibilityLabel("Begin \(selectedPractice.displayName), \(durationLabel(selectedDuration))")
                .accessibilityHint("Starts the guided breathing session with wrist-tap pacing.")

                Button("Not right now") { showSkipSheet = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(ForgePalette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Skips this suggestion. No judgment — you can say why or just close.")
            }
            .padding(.horizontal, 2)
        }
        .sheet(isPresented: $showSkipSheet) { skipSheet }
    }

    private var currentReason: String? {
        if let rec = aria.recommendation, rec.practice == selectedPractice {
            return rec.reason
        }
        return nil
    }

    private var practicePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ForgeDS.Spacing.sm) {
                ForEach(orderedPractices) { practice in
                    let selected = practice == selectedPractice
                    HapticButton(haptic: .click) {
                        selectedPractice = practice
                        selectedDuration = practice.defaultDuration
                    } label: {
                        Label(practice.displayName, systemImage: practice.symbolName)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, ForgeDS.Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selected
                                    ? practice.accentColor.opacity(0.4)
                                    : ForgePalette.surface)
                            )
                            .overlay(
                                Capsule().stroke(
                                    selected ? practice.accentColor : ForgePalette.surfaceElevated,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(practice.displayName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel("Practice type")
        .accessibilityHint("Swipe through breathing practices. The recommended one is first.")
    }

    private var orderedPractices: [PracticeType] {
        // Recommended practice leads; the rest follow in canonical order.
        guard let recommended = aria.recommendation?.practice else { return PracticeType.allCases }
        return [recommended] + PracticeType.allCases.filter { $0 != recommended }
    }

    private var durationPicker: some View {
        HStack(spacing: ForgeDS.Spacing.sm) {
            ForEach(selectedPractice.offeredDurations, id: \.self) { duration in
                let selected = duration == selectedDuration
                HapticButton(haptic: .click) {
                    selectedDuration = duration
                } label: {
                    Text(durationLabel(duration))
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: ForgeDS.Radius.sm)
                                .fill(selected ? ForgePalette.steel.opacity(0.4) : ForgePalette.surface)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(durationLabel(duration))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session length")
    }

    private var skipSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
                Text("All good — anything I should know?")
                    .font(ForgeType.caption(13))
                    .foregroundStyle(ForgePalette.textPrimary)
                ForEach(SkipReason.allCases) { reason in
                    HapticButton(haptic: .click) {
                        session.skip(reason: reason)
                        showSkipSheet = false
                    } label: {
                        Text(reason.label)
                            .font(.system(size: 12.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Logs this and closes. Nothing is held against you.")
                }
                Button("Just close") {
                    showSkipSheet = false
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(ForgePalette.textTertiary)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func prefillFromRecommendation() {
        guard !didPrefill else { return }
        didPrefill = true
        aria.refresh(health: health, context: contextEngine, sessionsToday: session.sessionsCompletedToday)
        if let rec = aria.recommendation {
            selectedPractice = rec.practice
            selectedDuration = rec.duration
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        duration < 120 ? "\(Int(duration))s" : "\(Int(duration / 60)) min"
    }
}

// MARK: - Active session

private struct ActiveSessionView: View {
    @Environment(WatchHealthKitManager.self) private var health
    @Environment(MindfulnessSessionManager.self) private var session

    var body: some View {
        VStack(spacing: ForgeDS.Spacing.sm) {
            if let pattern = session.activePattern, let practice = session.activePractice {
                BreathingOrb(
                    pattern: pattern,
                    accent: practice.accentColor,
                    elapsed: { session.elapsed(at: $0) },
                    isPaused: session.state == .paused
                )
                .frame(maxHeight: .infinity)
            }

            // Remaining time + live HR, quiet and small — the orb leads.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack {
                    Text(timeString(session.remaining(at: timeline.date)))
                        .font(ForgeType.metric(16))
                        .foregroundStyle(ForgePalette.textSecondary)
                        .monospacedDigit()
                        .accessibilityLabel("Time remaining \(timeString(session.remaining(at: timeline.date)))")
                    Spacer()
                    if let bpm = health.liveHeartRate {
                        Label("\(Int(bpm))", systemImage: "heart.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ForgePalette.textTertiary)
                            .accessibilityLabel("Heart rate \(Int(bpm)) beats per minute")
                    }
                }
            }

            HStack(spacing: ForgeDS.Spacing.sm) {
                HapticButton(haptic: .click) {
                    if session.state == .paused {
                        session.resume(health: health)
                    } else {
                        session.pause()
                    }
                } label: {
                    Image(systemName: session.state == .paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(session.state == .paused ? "Resume session" : "Pause session")

                HapticButton(haptic: .stop) {
                    session.endEarly(health: health)
                } label: {
                    Image(systemName: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(ForgePalette.jade)
                .accessibilityLabel("End session now")
                .accessibilityHint("Anything over thirty seconds still counts as a reset.")
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Debrief

private struct DebriefView: View {
    @Environment(WatchHealthKitManager.self) private var health
    @Environment(ContextEngine.self) private var contextEngine
    @Environment(ARIAWatchService.self) private var aria
    @Environment(MindfulnessSessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var upgradedMessage: String?

    var body: some View {
        ScrollView {
            if let debrief = session.debrief {
                VStack(alignment: .leading, spacing: ForgeDS.Spacing.md) {
                    ContextCard(
                        systemImage: debrief.practice.symbolName,
                        title: debrief.minutesLogged > 0
                            ? "\(Int(debrief.minutesLogged.rounded().clamped(min: 1))) mindful min logged"
                            : "Reset noted",
                        body_: upgradedMessage ?? debrief.message,
                        accent: debrief.practice.accentColor
                    )

                    if let line = debrief.biofeedbackLine {
                        Label(line, systemImage: "waveform.path.ecg")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ForgePalette.jade)
                            .accessibilityLabel(line)
                    }

                    if !debrief.healthKitSaved && debrief.minutesLogged > 0 {
                        Text("Couldn't reach Health just now — the session still counted for you.")
                            .font(.system(size: 11))
                            .foregroundStyle(ForgePalette.textTertiary)
                    }

                    Text("Want to go deeper? Open Forge on your iPhone and ARIA will pick this up.")
                        .font(.system(size: 11))
                        .foregroundStyle(ForgePalette.textTertiary)

                    HapticButton(haptic: .click) {
                        session.dismissDebrief()
                        dismiss()
                    } label: {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ForgePalette.steel.opacity(0.8))
                    .accessibilityLabel("Done")
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .task { await refreshAndUpgrade() }
    }

    private func refreshAndUpgrade() async {
        // The session changed today's mindful minutes → refresh signals so
        // Home + complications reflect it immediately.
        await health.refreshAll()
        aria.refresh(health: health, context: contextEngine, sessionsToday: session.sessionsCompletedToday)

        // Optionally upgrade the local debrief with backend coaching.
        guard let debrief = session.debrief else { return }
        if let deeper = await aria.deeperDebrief(
            practice: debrief.practice,
            minutes: debrief.minutesLogged,
            heartRateSettleBPM: nil
        ) {
            withAnimation(.easeInOut(duration: 0.3)) { upgradedMessage = deeper }
        }
    }
}

private extension Double {
    func clamped(min lower: Double) -> Double { Swift.max(self, lower) }
}
