import SwiftUI
import AVFoundation
import Speech

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  FORGE × ARIA — ULTIMATE CHAT                                          ║
// ║  Psychoactively useful · Addictive · Fun · Award-winning              ║
// ║                                                                        ║
// ║  ARIA Mood System (energized/focused/calm/pushed)                     ║
// ║  Momentum streak engine + fire badges                                 ║
// ║  Smart contextual chips that update with time of day                  ║
// ║  Haptic choreography (every interaction has a unique feel)            ║
// ║  Message reactions with micro-confetti burst                          ║
// ║  Celebration moments for milestones                                   ║
// ║  Progressive disclosure of ARIA's personality                        ║
// ║  Swipe-to-reply on messages                                           ║
// ║  XP / dopamine reward loop on send                                   ║
// ║  Full VoiceState machine + AuroraOrbView integration                 ║
// ║  All FDS tokens · Proper Task cancellation                            ║
// ╚═══════════════════════════════════════════════════════════════════════╝

// MARK: - Rounded Corner Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat; var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

// ============================================================
// MARK: - ARIA Mood System
// ============================================================
// ARIA's mood is derived from user's readiness + time of day.
// It shapes quick chips, greeting tone, and accent color.

enum ARIAMood: Equatable {
    case energized   // High readiness + morning
    case focused     // Medium readiness + daytime
    case calm        // Evening or low readiness
    case pushed      // User said "not feeling it"

    var displayName: String {
        switch self {
        case .energized: return "Energized"
        case .focused:   return "Focused"
        case .calm:      return "Calm"
        case .pushed:    return "Supportive"
        }
    }

    var emoji: String {
        switch self {
        case .energized: return "⚡️"
        case .focused:   return "🎯"
        case .calm:      return "🌙"
        case .pushed:    return "🤝"
        }
    }

    var accentColor: Color {
        switch self {
        case .energized: return Color.ember
        case .focused:   return Color(hex: "4A90D9")
        case .calm:      return Color(hex: "A855F7")
        case .pushed:    return Color(hex: "22C55E")
        }
    }

    var typingStyle: String {
        switch self {
        case .energized: return "Let's Go!!! Let's seize the day!!"
        case .focused:   return "Noted. Let's lock in. "
        case .calm:      return "Of course, you do you. "
        case .pushed:    return "I've got you. "
        }
    }

    static func derive(readiness: Int) -> ARIAMood {
        let hour = Calendar.current.component(.hour, from: Date())
        if readiness >= 80 && hour < 15 { return .energized }
        if readiness >= 60              { return .focused }
        if hour >= 20                   { return .calm }
        return .focused
    }
}

// ============================================================
// MARK: - Smart Context-Aware Quick Actions
// ============================================================

private func smartQuickActions(mood: ARIAMood, readiness: Int, messageCount: Int) -> [(label: String, icon: String, color: Color)] {
    let hour = Calendar.current.component(.hour, from: Date())

    // Core actions — always present but reordered by context
    var actions: [(label: String, icon: String, color: Color)] = []

    // Time-of-day first action
    if hour < 10 {
        actions.append(("Morning brief", "sunrise.fill", mood.accentColor))
    } else if hour >= 20 {
        actions.append(("Wind down plan", "moon.zzz.fill", Color(hex: "A855F7")))
    } else {
        actions.append(("What now?", "sparkles", mood.accentColor))
    }

    // Readiness-reactive
    if readiness >= 85 {
        actions.append(("I'm fired up 🔥", "bolt.fill", Color.ember))
    } else if readiness < 55 {
        actions.append(("Easy day options", "leaf.fill", Color(hex: "22C55E")))
    } else {
        actions.append(("Today's workout", "dumbbell.fill", Color.ember))
    }

    // Always useful
    actions.append(("How'd I sleep?", "moon.fill", Color(hex: "4A90D9")))
    actions.append(("Am I progressing?", "chart.line.uptrend.xyaxis", Color(hex: "22C55E")))

    if messageCount == 0 {
        actions.append(("Something hurts", "heart.text.square.fill", Color(hex: "EF4444")))
    } else {
        actions.append(("Change my plan", "arrow.triangle.2.circlepath", Color(hex: "F59E0B")))
    }

    actions.append(("Motivate me", "flame.fill", Color.ember))

    return actions
}

// ============================================================
// MARK: - Voice State Machine
// ============================================================

enum VoiceState: Equatable {
    case idle, listening, processing, speaking
    case error(String)

    var orbState: AROrbState {
        switch self {
        case .idle:       return .idle
        case .listening:  return .listening
        case .processing: return .processing
        case .speaking:   return .speaking
        case .error:      return .idle
        }
    }

    var label: String {
        switch self {
        case .idle:           return "Tap to speak"
        case .listening:      return "Listening…"
        case .processing:     return "Thinking…"
        case .speaking:       return "ARIA speaking"
        case .error(let m):   return m
        }
    }

    var sublabel: String {
        switch self {
        case .idle:       return "Say anything to ARIA"
        case .listening:  return "Speak clearly"
        case .processing: return "Analyzing your biometrics"
        case .speaking:   return "Tap to interrupt"
        case .error:      return "Try again"
        }
    }
}

// ============================================================
// MARK: - Haptic Choreography Engine
// ============================================================
// Every interaction has a distinct, intentional haptic signature.

enum HapticEvent {
    case messageSent        // Light + delay + success
    case messageReceived    // Soft impact
    case reactionAdded      // Selection + light
    case milestone          // Heavy + notification success
    case voiceStart         // Medium + rigid
    case quickChipTap       // Selection
    case celebration        // Sequence of impacts
    case typing             // Very light
}

func choreographedHaptic(_ event: HapticEvent) {
    switch event {
    case .messageSent:
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    case .messageReceived:
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    case .reactionAdded:
        UISelectionFeedbackGenerator().selectionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    case .milestone:
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    case .voiceStart:
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    case .quickChipTap:
        UISelectionFeedbackGenerator().selectionChanged()
    case .celebration:
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                UIImpactFeedbackGenerator(style: i % 2 == 0 ? .heavy : .medium).impactOccurred()
            }
        }
    case .typing:
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.3)
    }
}

// ============================================================
// MARK: - Speech Manager (real SFSpeechRecognizer)
// ============================================================

/// Shared dictation engine for Chat + Onboarding.
/// Partial results stream into `recognizedText`; silence or stop finalizes.
@MainActor
final class SpeechManager: ObservableObject {
    @Published var recognizedText: String = ""
    @Published var amplitude: Float = 0.0
    @Published var voiceState: VoiceState = .idle
    @Published var authorizationDenied = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.6
    private var levelTimer: Timer?
    /// When true, stopListening will not clear recognizedText (caller consumes it).
    private var preserveTranscriptOnStop = false

    var isListening: Bool { voiceState == .listening }

    func startListening() {
        guard speechRecognizer?.isAvailable != false else {
            voiceState = .error("Speech unavailable")
            return
        }

        // Tear down any prior session cleanly
        hardStop(clearText: true)
        recognizedText = ""
        authorizationDenied = false
        voiceState = .listening
        amplitude = 0.15

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginRecognition()
                case .denied, .restricted:
                    self.authorizationDenied = true
                    self.voiceState = .error("Mic / speech access needed")
                case .notDetermined:
                    self.voiceState = .idle
                @unknown default:
                    self.voiceState = .idle
                }
            }
        }
    }

    /// Stop listening. If `submit` is true and text exists, leaves `recognizedText` set
    /// and briefly moves through `.processing` → `.idle` so UI can react.
    func stopListening(submit: Bool = true) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        preserveTranscriptOnStop = submit && !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if preserveTranscriptOnStop {
            voiceState = .processing
            hardStop(clearText: false)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Deliver final idle so overlays can fire onRecognized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                self.voiceState = .idle
                self.preserveTranscriptOnStop = false
            }
        } else {
            hardStop(clearText: true)
            voiceState = .idle
            amplitude = 0
        }
    }

    func cancel() {
        hardStop(clearText: true)
        voiceState = .idle
        amplitude = 0
    }

    // MARK: - Private

    private func beginRecognition() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            voiceState = .error("Microphone error")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            voiceState = .error("No microphone input")
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)
            self?.updateAmplitude(from: buffer)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.recognizedText = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal {
                        self.stopListening(submit: true)
                        return
                    }
                }
                if let error, (error as NSError).code != 1, (error as NSError).code != 216 {
                    // 1/216 often cancellation — ignore
                    if self.voiceState == .listening {
                        self.voiceState = .error("Couldn't hear that")
                        self.hardStop(clearText: false)
                    }
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            voiceState = .listening
            startLevelPulseFallback()
        } catch {
            voiceState = .error("Microphone error")
            hardStop(clearText: true)
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.voiceState == .listening else { return }
                guard !self.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.stopListening(submit: true)
            }
        }
    }

    private func updateAmplitude(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        var sum: Float = 0
        for i in 0..<frameCount {
            let s = channel[i]
            sum += s * s
        }
        let rms = sqrt(sum / Float(frameCount))
        let level = min(1, max(0.08, rms * 12))
        Task { @MainActor in
            self.amplitude = level
        }
    }

    /// Gentle pulse when audio level taps are quiet
    private func startLevelPulseFallback() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.voiceState == .listening else { return }
                if self.amplitude < 0.12 {
                    self.amplitude = Float.random(in: 0.12...0.28)
                }
            }
        }
    }

    private func hardStop(clearText: Bool) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        amplitude = 0
        if clearText { recognizedText = "" }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// ============================================================
// MARK: - Momentum / XP Engine
// ============================================================

@MainActor
final class MomentumEngine: ObservableObject {
    @Published var xp:             Int    = 0
    @Published var level:          Int    = 1
    @Published var showXPBurst:    Bool   = false
    @Published var lastXPGain:     Int    = 0
    @Published var showLevelUp:    Bool   = false

    private let xpPerLevel = 100

    func award(xp amount: Int) {
        lastXPGain = amount
        xp        += amount
        withAnimation(FDS.Spring.hero) { showXPBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(FDS.Spring.standard) { self.showXPBurst = false }
        }
        checkLevelUp()
    }

    private func checkLevelUp() {
        let newLevel = (xp / xpPerLevel) + 1
        if newLevel > level {
            level = newLevel
            choreographedHaptic(.milestone)
            withAnimation(FDS.Spring.hero) { showLevelUp = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                withAnimation(FDS.Spring.standard) { self.showLevelUp = false }
            }
        }
    }

    var xpProgress: Double { Double(xp % xpPerLevel) / Double(xpPerLevel) }
    var xpToNext:   Int    { xpPerLevel - (xp % xpPerLevel) }
}

// ============================================================
// MARK: - Scale Button Style
// ============================================================

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(FDS.Spring.snap, value: configuration.isPressed)
    }
}

// ============================================================
// MARK: - Chat Bubble Shape
// ============================================================

struct ChatBubbleShape: Shape {
    let isTrainer: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18; let tail: CGFloat = 6
        var p = Path()
        if isTrainer {
            p.addRoundedRect(in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height - tail),
                             cornerSize: CGSize(width: r, height: r))
            p.move(to: CGPoint(x: 0, y: rect.height - tail))
            p.addLine(to: CGPoint(x: 0, y: rect.height))
            p.addLine(to: CGPoint(x: r, y: rect.height - tail))
        } else {
            p.addRoundedRect(in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height - tail),
                             cornerSize: CGSize(width: r, height: r))
            p.move(to: CGPoint(x: rect.width, y: rect.height - tail))
            p.addLine(to: CGPoint(x: rect.width, y: rect.height))
            p.addLine(to: CGPoint(x: rect.width - r, y: rect.height - tail))
        }
        return p
    }
}

// ============================================================
// MARK: - Root Chat View
// ============================================================

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var speech = SpeechManager()
    @StateObject private var momentum = MomentumEngine()
    @StateObject private var ariaContext = AriaContextStore.shared

    @State private var inputText:         String = ""
    @State private var isTyping:          Bool   = false
    @State private var showVoiceOrb:      Bool   = false
    @State private var showQuickActions:  Bool   = true
    @State private var ariaMood:          ARIAMood = .focused
    @State private var swipeReplyTarget:  ChatMessage? = nil
    @State private var showMilestone:     Bool   = false
    @State private var reactionBurstAt:   CGPoint = .zero
    @State private var showReactionBurst: Bool   = false
    @State private var showContextInspector = false
    @State private var proactiveInsight: String?

    @FocusState private var isInputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────
            ChatBackground(mood: ariaMood)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────
                ChatHeaderView(
                    mood:              ariaMood,
                    momentum:          momentum,
                    relationshipLevel: ariaContext.context.relationshipLevel,
                    onAvatarLongPress: { showContextInspector = true }
                )

                if let insight = proactiveInsight, ariaContext.shouldBeProactive() {
                    ProactiveCardView(
                        insight: insight,
                        relationshipLevel: ariaContext.context.relationshipLevel,
                        onTap: { sendMessage("Tell me more about that") }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                // ── Messages ─────────────────────────────────────
                MessageListView(
                    isTyping:         $isTyping,
                    showQuickActions: $showQuickActions,
                    ariaMood:         ariaMood,
                    swipeReply:       $swipeReplyTarget,
                    onQuickAction:    sendMessage,
                    onReaction:       { messageId, emoji in
                        Task {
                            await FeedbackService.shared.processReaction(
                                userId: ariaContext.context.userId,
                                messageId: messageId,
                                reaction: emoji
                            )
                        }
                    },
                    onReactionBurst:  { pt in
                        reactionBurstAt   = pt
                        showReactionBurst = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            showReactionBurst = false
                        }
                    }
                )

                // Reply preview bar
                if let target = swipeReplyTarget {
                    ReplyPreviewBar(message: target) {
                        withAnimation(FDS.Spring.snap) { swipeReplyTarget = nil }
                    }
                }

                // ── Input ────────────────────────────────────────
                ChatInputAreaView(
                    inputText:        $inputText,
                    isTyping:         $isTyping,
                    isInputFocused:   $isInputFocused,
                    showQuickActions: $showQuickActions,
                    mood:             ariaMood,
                    replyTarget:      swipeReplyTarget,
                    onSend:           sendMessage,
                    onMicTap: {
                        choreographedHaptic(.voiceStart)
                        withAnimation(FDS.Spring.hero) { showVoiceOrb = true }
                        speech.startListening()
                    }
                )
            }

            // ── XP Burst ─────────────────────────────────────────
            if momentum.showXPBurst && !reduceMotion {
                XPBurstView(amount: momentum.lastXPGain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 100).padding(.trailing, 20)
                    .allowsHitTesting(false)
                    .zIndex(50)
            }

            // ── Level Up Banner ───────────────────────────────────
            if momentum.showLevelUp {
                LevelUpBanner(level: momentum.level)
                    .zIndex(60)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.7).combined(with: .opacity),
                        removal:   .opacity
                    ))
            }

            // ── Micro-confetti burst on reaction ─────────────────
            if showReactionBurst && !reduceMotion {
                MicroConfettiBurst(at: reactionBurstAt)
                    .allowsHitTesting(false)
                    .zIndex(70)
            }

            // ── Voice Orb Overlay ─────────────────────────────────
            if showVoiceOrb {
                VoiceOrbOverlay(
                    speech:      speech,
                    mood:        ariaMood,
                    isShowing:   $showVoiceOrb,
                    onRecognized: { text in
                        withAnimation(FDS.Spring.hero) { showVoiceOrb = false }
                        inputText = text
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { sendMessage(text) }
                    },
                    onCancel: {
                        speech.cancel()
                        withAnimation(FDS.Spring.hero) { showVoiceOrb = false }
                    }
                )
                .ignoresSafeArea()
                .zIndex(100)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(FDS.Spring.hero, value: showVoiceOrb)
        .animation(FDS.Spring.standard, value: swipeReplyTarget?.id)
        .sheet(isPresented: $showContextInspector) {
            ContextInspectorView(
                contextStore: ariaContext,
                richContext: ariaContext.buildRichContext(from: store)
            )
        }
        .onAppear {
            ariaMood = ARIAMood.derive(readiness: store.readiness.overall)
            ariaContext.configure(userId: store.userProfile.name)
            ariaContext.updateProfile(
                goals: store.userProfile.fitnessGoals.map(\.label),
                lifestyleTags: [store.userProfile.experienceLevel.label]
            )
            Task { proactiveInsight = await AriaService.shared.fetchProactiveMessage(store: store) }
            consumePendingHomeHandoff()
        }
        .onChange(of: store.ariaPendingChatPrompt) { _, prompt in
            guard prompt != nil else { return }
            consumePendingHomeHandoff()
        }
        .onChange(of: store.readiness.overall) { _, val in
            withAnimation(FDS.Spring.standard) { ariaMood = ARIAMood.derive(readiness: val) }
        }
        .onChange(of: speech.recognizedText) { _, text in
            guard !text.isEmpty else { return }
            inputText = text
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshDailyData() } }
        }
    }

    /// Home control-center → chat bridge (prompt + optional voice orb).
    private func consumePendingHomeHandoff() {
        let prompt = store.ariaPendingChatPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsVoice = store.ariaVoiceMode
        store.ariaPendingChatPrompt = nil

        if wantsVoice {
            store.ariaVoiceMode = true
            choreographedHaptic(.voiceStart)
            withAnimation(FDS.Spring.hero) { showVoiceOrb = true }
            speech.startListening()
        }

        if let prompt, !prompt.isEmpty {
            // Prefill input so user sees context; auto-send after a beat for seamless handoff.
            inputText = prompt
            if !wantsVoice {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    sendMessage(prompt)
                }
            }
        }
    }

    // ── Send ──────────────────────────────────────────────────────

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isTyping else { return }

        choreographedHaptic(.messageSent)

        if trimmed.lowercased().contains("not feeling") {
            withAnimation(FDS.Spring.standard) { ariaMood = .pushed }
        }

        inputText = ""
        isTyping = true
        showQuickActions = false
        swipeReplyTarget = nil
        proactiveInsight = nil

        let xpGain = trimmed.split(separator: " ").count > 5 ? 15 : 10
        momentum.award(xp: xpGain)

        Task {
            await store.sendMessage(trimmed)
            isTyping = false
            choreographedHaptic(.messageReceived)

            let count = store.chatMessages.filter { $0.role == .trainer }.count
            if [5, 10, 25, 50].contains(count) {
                choreographedHaptic(.milestone)
                withAnimation(FDS.Spring.hero) { showMilestone = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(FDS.Spring.standard) { showMilestone = false }
                }
            }
        }
    }
}

// ============================================================
// MARK: - Chat Background (mood-reactive)
// ============================================================

struct ChatBackground: View {
    let mood: ARIAMood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(.sRGB, red: 8.0/255.0, green: 8.0/255.0, blue: 8.0/255.0, opacity: 1.0)
            if !reduceMotion {
                // Fallback gradient animation if MeshGradientOverlay isn't available
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let colors = [
                            Color(hex: "00FFF0").opacity(0.03),
                            Color(hex: "0080FF").opacity(0.025),
                            Color(hex: "6000FF").opacity(0.02),
                            mood.accentColor.opacity(0.015)
                        ]
                        
                        for i in 0..<4 {
                            let x = size.width * CGFloat(i) / 4 + CGFloat(sin(time * 0.3 + Double(i))) * 40
                            let y = size.height / 2 + CGFloat(cos(time * 0.4 + Double(i))) * 60
                            let rect = CGRect(x: x, y: y, width: size.width / 2, height: size.height / 2)
                            
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(colors[i])
                            )
                        }
                    }
                }
                .blur(radius: 60)
                .opacity(0.18)
                
                mood.accentColor.opacity(0.04)
            }
        }
        .animation(.easeInOut(duration: 1.4), value: mood)
    }
}

// ============================================================
// MARK: - Chat Header (mood badge + XP ring)
// ============================================================

struct ChatHeaderView: View {
    @EnvironmentObject var store: AppStore
    let mood:              ARIAMood
    @ObservedObject var momentum: MomentumEngine
    var relationshipLevel: Int = 1
    var onAvatarLongPress: (() -> Void)? = nil
    @State private var pulse        = false
    @State private var appeared     = false
    @State private var showXPRing   = false

    private var scoreColor: Color {
        switch store.readiness.overall {
        case 85...:  return Color(hex: "22C55E")
        case 70..<85: return Color.ember
        case 50..<70: return Color.steel
        default:      return Color(hex: "EF4444")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // ARIA Avatar + presence + XP ring
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    // XP ring overlay
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 2.5)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: CGFloat(momentum.xpProgress))
                        .stroke(
                            AngularGradient(
                                colors: [mood.accentColor.opacity(0.6), mood.accentColor],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.0, dampingFraction: 0.72), value: momentum.xpProgress)

                    // Core avatar
                    Circle()
                        .fill(LinearGradient(
                            colors: [mood.accentColor.opacity(0.22), mood.accentColor.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(
                            LinearGradient(
                                colors: [mood.accentColor.opacity(0.6), mood.accentColor.opacity(0.18)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 1.5
                        ))

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(LinearGradient(
                            colors: [mood.accentColor, mood.accentColor.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        ))
                }

                // Presence dot
                ZStack {
                    Circle().fill(Color(hex: "080808")).frame(width: 14, height: 14)
                    Circle().fill(Color(hex: "22C55E")).frame(width: 9, height: 9)
                        .shadow(color: Color(hex: "22C55E").opacity(0.7), radius: 3)
                    Circle().fill(Color(hex: "22C55E").opacity(0.4))
                        .frame(width: 9, height: 9)
                        .scaleEffect(pulse ? 2.0 : 1.0)
                        .opacity(pulse ? 0 : 0.7)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
                }
                .offset(x: 3, y: 3)
            }
            .onAppear { pulse = true }
            .onLongPressGesture(minimumDuration: 0.45) {
                choreographedHaptic(.reactionAdded)
                onAvatarLongPress?()
            }

            // Name + mood badge
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("ARIA")
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(.textPrimary)
                        .tracking(0.5)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundColor(mood.accentColor)

                    // Mood badge
                    HStack(spacing: 3) {
                        Text(mood.emoji)
                            .font(.system(size: 10))
                        Text(mood.displayName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(mood.accentColor)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(mood.accentColor.opacity(0.12))
                    .cornerRadius(FDS.Radius.pill)
                    .overlay(Capsule().stroke(mood.accentColor.opacity(0.3), lineWidth: 0.5))
                    .id(mood)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .animation(FDS.Spring.standard, value: mood)
                }

                HStack(spacing: 5) {
                    Circle().fill(Color(hex: "22C55E")).frame(width: 5, height: 5)
                    Text("Active · Bond Lv.\(relationshipLevel) · Chat Lv.\(momentum.level)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            // Readiness chip
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(scoreColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: scoreColor.opacity(0.7), radius: 4)
                    Text("\(store.readiness.overall)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                Text("ready")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.textMuted)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.surfaceElevated)
            .cornerRadius(FDS.Radius.pill)
            .overlay(Capsule().stroke(scoreColor.opacity(0.35), lineWidth: 1))
            .shadow(color: scoreColor.opacity(0.2), radius: 8, y: 3)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.borderColor.opacity(0.3)).frame(height: 0.5), alignment: .bottom)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -10)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true } }
    }
}

// ============================================================
// MARK: - Message List
// ============================================================

struct MessageListView: View {
    @EnvironmentObject var store: AppStore
    @Binding var isTyping:          Bool
    @Binding var showQuickActions:  Bool
    let ariaMood:      ARIAMood
    @Binding var swipeReply: ChatMessage?
    let onQuickAction:    (String) -> Void
    var onReaction: ((String, String) -> Void)? = nil
    let onReactionBurst:  (CGPoint) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if store.chatMessages.isEmpty {
                    ChatEmptyStateView(mood: ariaMood, onQuickActionTap: onQuickAction)
                } else {
                    LazyVStack(spacing: 16) {
                        Color.clear.frame(height: 8)

                        // Date separator
                        DateSeparatorView()

                        ForEach(store.chatMessages) { msg in
                            MessageBubbleView(
                                message:         msg,
                                mood:            ariaMood,
                                onSwipeReply:    { withAnimation(FDS.Spring.standard) { swipeReply = msg } },
                                onReaction:      onReaction,
                                onReactionBurst: onReactionBurst
                            )
                            .id(msg.id)
                        }

                        if isTyping {
                            TypingIndicatorView(mood: ariaMood)
                                .id("typing")
                                .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                        }

                        Color.clear.frame(height: 16).id("bottom")
                    }
                    .padding(.horizontal, 14)
                }
            }
            .onChange(of: store.chatMessages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isTyping) { _, typing in if typing { scrollToBottom(proxy) } }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scrollToBottom(proxy, animated: false) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.26)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

// ============================================================
// MARK: - Date Separator
// ============================================================

struct DateSeparatorView: View {
    private var label: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textMuted)
                .tracking(0.5)
                .fixedSize()
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
        }
        .padding(.horizontal, 8)
    }
}

// ============================================================
// MARK: - Chat Empty State (animated, mood-aware)
// ============================================================

struct ChatEmptyStateView: View {
    let mood: ARIAMood
    let onQuickActionTap: (String) -> Void
    @EnvironmentObject var store: AppStore
    @State private var appeared  = false
    @State private var orbPulse  = false
    @State private var orbGlow   = false
    @State private var wavePhase: Double = 0

    // Greeting message varies by mood
    private var greeting: String {
        let first = store.userProfile.name.components(separatedBy: " ").first ?? ""
        switch mood {
        case .energized: return "You're dialed in today\(first.isEmpty ? "" : ", \(first)").\nLet's make it count. 🔥"
        case .focused:   return "Ready when you are\(first.isEmpty ? "" : ", \(first)").\nWhat's on your mind?"
        case .calm:      return "Easy does it\(first.isEmpty ? "" : ", \(first)").\nHow are you feeling tonight?"
        case .pushed:    return "Rough day? That's okay.\nI'm here for whatever you need."
        }
    }

    private var subtext: String {
        switch mood {
        case .energized: return "Your readiness is peaking — optimal window for max output."
        case .focused:   return "I'm analyzing your biometrics in real-time."
        case .calm:      return "Recovery and rest are part of the process."
        case .pushed:    return "We go at your pace. No pressure, just support."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            // Animated ARIA orb
            ZStack {
                // Outer breathing rings
                ForEach(0..<3, id: \.self) { i in
                    let ringOpacity = 0.05 - Double(i) * 0.015
                    let ringSize = CGFloat(170 + i * 48)
                    let ringAnimation = Animation.easeOut(duration: 2.2 + Double(i) * 0.4)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 0.55)

                    Circle()
                        .fill(mood.accentColor.opacity(ringOpacity))
                        .frame(width: ringSize, height: ringSize)
                        .scaleEffect(orbPulse ? 1.15 : 1.0)
                        .opacity(orbPulse ? 0 : 0.8)
                        .animation(ringAnimation, value: orbPulse)
                }

                // Bloom
                Circle()
                    .fill(RadialGradient(
                        colors: [mood.accentColor.opacity(orbGlow ? 0.28 : 0.12), .clear],
                        center: .center, startRadius: 0, endRadius: 75
                    ))
                    .frame(width: 150, height: 150).blur(radius: 22)

                // Core orb
                Circle()
                    .fill(LinearGradient(
                        colors: [mood.accentColor.opacity(0.24), mood.accentColor.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(
                        LinearGradient(colors: [mood.accentColor.opacity(0.55), mood.accentColor.opacity(0.1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5
                    ))
                    .shadow(color: mood.accentColor.opacity(orbGlow ? 0.55 : 0.2), radius: orbGlow ? 28 : 12)

                // Screen-blend bloom
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.white.opacity(orbGlow ? 0.12 : 0.04), .clear],
                        center: .center, startRadius: 0, endRadius: 48
                    ))
                    .frame(width: 96, height: 96).blendMode(.screen)

                // Waveform inside orb
                TimelineView(.animation(minimumInterval: 1.0/30.0)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let mid = size.height / 2
                        var path = Path()
                        for xi in 0...Int(size.width) {
                            let x = CGFloat(xi)
                            let y = mid + 14 * CGFloat(sin(Double(x/size.width) * .pi * 4 + t * 1.8))
                            if xi == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        ctx.stroke(path, with: .color(Color.white.opacity(0.35)), lineWidth: 1.5)
                    }
                }
                .frame(width: 60, height: 30)
                .clipShape(Circle().scale(0.58))

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [mood.accentColor, mood.accentColor.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .shadow(color: mood.accentColor.opacity(0.5), radius: 10)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(FDS.Spring.floaty.delay(0.08), value: appeared)
            .padding(.bottom, 28)

            // Greeting
            VStack(spacing: 8) {
                Text(greeting)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text(subtext)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(FDS.Spring.hero.delay(0.18), value: appeared)
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.bottom, 32)

            // Smart suggested prompts
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ARIA SUGGESTS")
                        .font(.system(size: 9, weight: .black))
                        .tracking(2.8)
                        .foregroundColor(.textMuted)
                    Spacer()
                    Text("based on \(mood.displayName.lowercased()) mode")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(mood.accentColor.opacity(0.7))
                }
                .padding(.horizontal, 4)

                let prompts: [(String, String)] = [
                    mood == .energized ? ("Let's go heavy today", "bolt.fill") : ("What's right for today?", "sparkles"),
                    ("How'd I sleep?", "moon.fill"),
                    ("Am I making progress?", "chart.line.uptrend.xyaxis"),
                ]

                ForEach(Array(prompts.enumerated()), id: \.offset) { i, prompt in
                    Button { onQuickActionTap(prompt.0) } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(mood.accentColor.opacity(0.14))
                                    .frame(width: 32, height: 32)
                                Image(systemName: prompt.1)
                                    .font(.system(size: 13))
                                    .foregroundColor(mood.accentColor)
                            }
                            Text(prompt.0)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textMuted)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color.surfaceElevated)
                        .cornerRadius(FDS.Radius.md)
                        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md)
                            .stroke(Color.borderColor.opacity(0.5), lineWidth: 0.5))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)
                    .animation(FDS.Spring.hero.delay(0.28 + Double(i) * 0.07), value: appeared)
                }
            }
            .padding(.horizontal, FDS.Spacing.lg)

            Spacer(minLength: 36)
        }
        .onAppear {
            appeared = true
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) { orbPulse = true }
            withAnimation(.easeInOut(duration: FDS.Duration.breathe).repeatForever(autoreverses: true)) { orbGlow = true }
        }
    }
}

// ============================================================
// MARK: - Message Bubble (swipe-to-reply, reactions, specular)
// ============================================================

struct MessageBubbleView: View {
    let message:          ChatMessage
    let mood:             ARIAMood
    let onSwipeReply:     () -> Void
    var onReaction:       ((String, String) -> Void)? = nil
    let onReactionBurst:  (CGPoint) -> Void

    @State private var appeared        = false
    @State private var showTimestamp   = false
    @State private var showReactions   = false
    @State private var selectedReact:  String? = nil
    @State private var dragOffset:     CGFloat = 0
    @State private var replyTriggered  = false

    var isTrainer: Bool { message.role == .trainer }
    private var isHighConfidence: Bool { (message.confidence ?? 0) >= 0.85 }

    private let reactions: [(emoji: String, label: String)] = [
        ("🔥", "Fire"), ("💪", "Strong"), ("✅", "Got it"),
        ("😤", "Let's go"), ("🎯", "Locked in"), ("❤️", "Love")
    ]

    var body: some View {
        VStack(alignment: isTrainer ? .leading : .trailing, spacing: 5) {
            HStack(alignment: .bottom, spacing: 8) {
                if !isTrainer { Spacer(minLength: 52) }

                // ARIA mini-avatar
                if isTrainer {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [mood.accentColor.opacity(0.18), mood.accentColor.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 28, height: 28)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundColor(mood.accentColor)
                    }
                    .offset(y: -3)
                }

                // Bubble + swipe
                VStack(alignment: isTrainer ? .leading : .trailing, spacing: 6) {
                    // Swipe-to-reply gesture wrapper
                    ZStack(alignment: isTrainer ? .trailing : .leading) {
                        // Reply icon revealed on swipe
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 14))
                            .foregroundColor(mood.accentColor.opacity(min(1.0, abs(dragOffset) / 44.0)))
                            .scaleEffect(min(1.2, abs(dragOffset) / 36.0))
                            .offset(x: isTrainer ? 8 : -8)

                        Button {
                            withAnimation(FDS.Spring.standard) { showTimestamp.toggle() }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text(message.content)
                                .font(.system(size: 15.5, weight: .regular))
                                .foregroundColor(isTrainer ? .textPrimary : .white)
                                .lineSpacing(4.5)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .background(Group {
                                    if isTrainer {
                                        Color.surfaceElevated
                                            .overlay(ChatBubbleShape(isTrainer: true)
                                                .stroke(Color.borderColor.opacity(0.3), lineWidth: 0.5))
                                    } else {
                                        FDS.Gradient.emberDeep
                                    }
                                })
                                .clipShape(ChatBubbleShape(isTrainer: isTrainer))
                                .overlay {
                                    if isTrainer && isHighConfidence {
                                        ChatBubbleShape(isTrainer: true)
                                            .stroke(Color.steel.opacity(0.45), lineWidth: 1)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if isTrainer && isHighConfidence {
                                        Image(systemName: "sparkle")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.steel.opacity(0.8))
                                            .padding(6)
                                    }
                                }
                                .overlay(alignment: .top) {
                                    if !isTrainer {
                                        ChatBubbleShape(isTrainer: false)
                                            .fill(LinearGradient(
                                                colors: [Color.white.opacity(0.14), .clear],
                                                startPoint: .top, endPoint: .center
                                            ))
                                            .frame(maxHeight: 26)
                                    }
                                }
                                .shadow(
                                    color: isTrainer
                                        ? (isHighConfidence ? Color.steel.opacity(0.12) : .black.opacity(0.06))
                                        : Color.ember.opacity(0.38),
                                    radius: isTrainer ? (isHighConfidence ? 8 : 4) : 16,
                                    y: isTrainer ? 2 : 6
                                )
                        }
                        .buttonStyle(.plain)
                        .textSelection(.enabled)
                        .offset(x: dragOffset)
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { v in
                                    let d = isTrainer ? max(0, min(64, v.translation.width))
                                                      : min(0, max(-64, v.translation.width))
                                    dragOffset = d
                                    if abs(d) > 38 && !replyTriggered {
                                        replyTriggered = true
                                        choreographedHaptic(.reactionAdded)
                                        onSwipeReply()
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(FDS.Spring.snap) { dragOffset = 0 }
                                    replyTriggered = false
                                }
                        )
                    }

                    // Rich card
                    if let card = message.richCard {
                        RichCardView(card: card).padding(.top, 4)
                    }

                    // Timestamp
                    if showTimestamp {
                        HStack(spacing: 4) {
                            Text(formatTime(message.timestamp))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textMuted)
                            if !isTrainer {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "22C55E").opacity(0.75))
                            }
                        }
                        .padding(.horizontal, 4)
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                    }

                    // Reaction chips (shown on trainer messages after selection)
                    if let r = selectedReact {
                        HStack(spacing: 4) {
                            Text(r).font(.system(size: 14))
                            Text("You reacted")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.textMuted)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.surfaceElevated)
                        .cornerRadius(FDS.Radius.pill)
                        .overlay(Capsule().stroke(Color.borderColor, lineWidth: 0.5))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }

                if isTrainer { Spacer(minLength: 52) }
            }

            // Reaction bar (swipe up on any message or long-press)
            if showReactions {
                HStack(spacing: 6) {
                    if !isTrainer { Spacer() }
                    ForEach(reactions, id: \.emoji) { r in
                        Button {
                            withAnimation(FDS.Spring.snap) {
                                selectedReact = selectedReact == r.emoji ? nil : r.emoji
                                showReactions = false
                            }
                            if selectedReact == r.emoji {
                                onReaction?(message.id, r.emoji)
                            }
                            choreographedHaptic(.reactionAdded)
                            // Trigger confetti burst
                            onReactionBurst(CGPoint(x: UIScreen.main.bounds.width / 2, y: 300))
                        } label: {
                            Text(r.emoji)
                                .font(.system(size: 20))
                                .padding(8)
                                .background(selectedReact == r.emoji ? mood.accentColor.opacity(0.2) : Color.surfaceElevated)
                                .cornerRadius(FDS.Radius.xs)
                                .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xs)
                                    .stroke(selectedReact == r.emoji ? mood.accentColor.opacity(0.4) : Color.borderColor, lineWidth: 0.5))
                                .scaleEffect(selectedReact == r.emoji ? 1.15 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .animation(FDS.Spring.snap, value: selectedReact)
                    }
                    if isTrainer { Spacer() }
                }
                .padding(8)
                .background(Color.surface)
                .cornerRadius(FDS.Radius.sm)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                .transition(.scale(scale: 0.85, anchor: isTrainer ? .bottomLeading : .bottomTrailing).combined(with: .opacity))
                .padding(.horizontal, 36)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : (isTrainer ? -16 : 16))
        .onAppear { withAnimation(FDS.Spring.standard.delay(0.04)) { appeared = true } }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: { Label("Copy", systemImage: "doc.on.doc") }

            Button {
                withAnimation(FDS.Spring.standard) { showReactions.toggle() }
            } label: { Label("React", systemImage: "face.smiling.fill") }

            Button {
                onSwipeReply()
            } label: { Label("Reply", systemImage: "arrowshape.turn.up.left.fill") }

            Button {
                withAnimation(FDS.Spring.snap) { showTimestamp.toggle() }
            } label: { Label("Show Time", systemImage: "clock") }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: date)
    }
}

// ============================================================
// MARK: - Reply Preview Bar
// ============================================================

struct ReplyPreviewBar: View {
    let message: ChatMessage
    let onDismiss: () -> Void
    var isTrainer: Bool { message.role == .trainer }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.ember)
                .frame(width: 3)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 2) {
                Text(isTrainer ? "Replying to ARIA" : "Replying to yourself")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.ember)
                Text(message.content)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .overlay(Rectangle().fill(Color.borderColor.opacity(0.4)).frame(height: 0.5), alignment: .top)
    }
}

// ============================================================
// MARK: - Typing Indicator (mood-reactive, 4 steps, cancellable)
// ============================================================

struct TypingIndicatorView: View {
    let mood: ARIAMood
    @State private var dotAnimate = false
    @State private var stateLabel = "Analyzing…"
    @State private var stateIcon  = "brain.head.profile"
    @State private var stateColor: Color = .ember
    @State private var showLabel  = false
    @State private var cycleTask: Task<Void, Never>? = nil

    private var steps: [(String, String, Color, Double)] {[
        ("Analyzing…",       "brain.head.profile",  mood.accentColor,         0.9),
        ("Checking data…",   "gearshape.2.fill",    Color.steel,              0.85),
        ("Formulating…",     "text.bubble.fill",    Color(hex: "22C55E"),     0.75),
        ("Almost there…",    "sparkles",            Color(hex: "A855F7"),     0.6),
    ]}

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [mood.accentColor.opacity(0.18), mood.accentColor.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                Image(systemName: "flame.fill")
                    .font(.system(size: 12)).foregroundColor(mood.accentColor)
            }
            .offset(y: -3)

            VStack(alignment: .leading, spacing: 8) {
                if showLabel {
                    HStack(spacing: 6) {
                        Image(systemName: stateIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(stateColor)
                        Text(stateLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(stateColor.opacity(0.08)))
                    .overlay(Capsule().stroke(stateColor.opacity(0.22), lineWidth: 0.5))
                    .transition(.scale(scale: 0.88, anchor: .leading).combined(with: .opacity))
                }

                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(stateColor)
                            .frame(width: 8, height: 8)
                            .scaleEffect(dotAnimate ? 1.2 : 0.5)
                            .opacity(dotAnimate ? 1 : 0.28)
                            .shadow(color: stateColor.opacity(dotAnimate ? 0.5 : 0), radius: 4)
                            .animation(
                                .easeInOut(duration: 0.52).repeatForever().delay(Double(i) * 0.17),
                                value: dotAnimate
                            )
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(Color.surfaceElevated)
                .clipShape(ChatBubbleShape(isTrainer: true))
                .overlay(ChatBubbleShape(isTrainer: true).stroke(Color.borderColor.opacity(0.3), lineWidth: 0.5))
                .shadow(color: stateColor.opacity(0.1), radius: 6, y: 2)
            }
            Spacer(minLength: 52)
        }
        .onAppear {
            dotAnimate = true
            withAnimation(.easeInOut(duration: 0.2).delay(0.1)) { showLabel = true }
            stateColor = mood.accentColor
            startCycle()
        }
        .onDisappear { cycleTask?.cancel(); cycleTask = nil }
        .animation(FDS.Spring.standard, value: stateColor)
    }

    private func startCycle() {
        cycleTask = Task {
            for (label, icon, color, duration) in steps {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(FDS.Spring.standard) {
                        stateLabel = label; stateIcon = icon; stateColor = color
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { showLabel = false }
            }
        }
    }
}

// ============================================================
// MARK: - Chat Input Area (smart + mood-reactive)
// ============================================================

struct ChatInputAreaView: View {
    @EnvironmentObject var store: AppStore
    @Binding var inputText:        String
    @Binding var isTyping:         Bool
    @FocusState.Binding var isInputFocused: Bool
    @Binding var showQuickActions:  Bool
    let mood:         ARIAMood
    let replyTarget:  ChatMessage?
    let onSend:       (String) -> Void
    let onMicTap:     () -> Void
    @State private var charCount: Int = 0

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isTyping
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.borderColor.opacity(0.3)).frame(height: 0.5)

            // Smart quick chips (mood-aware, scroll horizontal)
            if showQuickActions && !isInputFocused {
                let chips = smartQuickActions(
                    mood:         mood,
                    readiness:    store.readiness.overall,
                    messageCount: store.chatMessages.count
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { i, chip in
                            SmartChip(label: chip.label, icon: chip.icon, color: chip.color, disabled: isTyping) {
                                onSend(chip.label)
                                choreographedHaptic(.quickChipTap)
                                withAnimation(.easeOut(duration: 0.22)) { showQuickActions = false }
                            }
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 11)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input row
            HStack(spacing: 11) {
                // Mic
                Button(action: onMicTap) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [mood.accentColor.opacity(0.18), mood.accentColor.opacity(0.07)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 48, height: 48)
                            .overlay(Circle().stroke(mood.accentColor.opacity(0.22), lineWidth: 0.5))
                        Image(systemName: "mic.fill")
                            .font(.system(size: 19))
                            .foregroundColor(mood.accentColor)
                    }
                    .shadow(color: mood.accentColor.opacity(0.28), radius: 9, y: 3)
                }
                .disabled(isTyping)
                .opacity(isTyping ? 0.42 : 1)
                .animation(FDS.Spring.snap, value: isTyping)

                // Text field
                ZStack(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Color.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 26).stroke(
                            isInputFocused
                                ? LinearGradient(colors: [mood.accentColor.opacity(0.65), mood.accentColor.opacity(0.32)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.borderColor.opacity(0.55), Color.borderColor.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1.5
                        ))
                        .shadow(
                            color: isInputFocused ? mood.accentColor.opacity(0.16) : .black.opacity(0.04),
                            radius: isInputFocused ? 12 : 3, y: isInputFocused ? 3 : 1
                        )

                    TextField("Ask ARIA anything…", text: $inputText, axis: .vertical)
                        .font(.system(size: 15.5))
                        .foregroundColor(.textPrimary)
                        .tint(mood.accentColor)
                        .focused($isInputFocused)
                        .disabled(isTyping)
                        .padding(.leading, 18).padding(.trailing, 60).padding(.vertical, 14)
                        .lineLimit(1...5)
                        .onSubmit { onSend(inputText) }
                        .onChange(of: inputText) { _, text in
                            charCount = text.count
                            // Subtle typing haptic every 10 chars
                            if charCount % 10 == 0 && charCount > 0 {
                                choreographedHaptic(.typing)
                            }
                        }

                    // Send button
                    Button { onSend(inputText) } label: {
                        ZStack {
                            Circle()
                                .fill(canSend
                                    ? AnyShapeStyle(FDS.Gradient.emberDeep)
                                    : AnyShapeStyle(Color.white.opacity(0.06)))
                                .frame(width: 40, height: 40)
                                .overlay(alignment: .top) {
                                    if canSend {
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [Color.white.opacity(0.18), .clear],
                                                startPoint: .top, endPoint: .center
                                            ))
                                            .frame(width: 40, height: 20).clipped()
                                    }
                                }
                                .shadow(color: canSend ? Color.ember.opacity(0.55) : .clear, radius: 12, y: 4)

                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(canSend ? .white : .textMuted)
                        }
                        .animation(FDS.Spring.snap, value: canSend)
                    }
                    .disabled(!canSend)
                    .padding(.trailing, 7)
                    .buttonStyle(ScaleButtonStyle())
                }
                .animation(.easeInOut(duration: 0.18), value: isInputFocused)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
        }
        .background(.ultraThinMaterial)
    }
}

// ============================================================
// MARK: - Smart Chip (colored, per-mood)
// ============================================================

struct SmartChip: View {
    let label:    String
    let icon:     String
    let color:    Color
    let disabled: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(color.opacity(0.08))
            .cornerRadius(FDS.Radius.pill)
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 0.5))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .buttonStyle(ScaleButtonStyle())
    }
}

// ============================================================
// MARK: - Voice Orb Overlay
// ============================================================

struct VoiceOrbOverlay: View {
    @ObservedObject var speech:  SpeechManager
    let mood:         ARIAMood
    @Binding var isShowing:      Bool
    let onRecognized: (String) -> Void
    let onCancel:     () -> Void

    @State private var stars: [StarDatum] = {
        let w = UIScreen.main.bounds.width; let h = UIScreen.main.bounds.height
        return (0..<65).map { i in
            StarDatum(id: i, x: .random(in: 0...w), y: .random(in: 0...h),
                      size: .random(in: 0.8...3.2), baseOpacity: .random(in: 0.08...0.5),
                      phaseOffset: .random(in: 0...(.pi*2)))
        }
    }()

    @State private var orbRevealed:    Bool   = false
    @State private var contentOpacity: Double = 0
    @State private var pulseKey:       Int    = 0

    private struct StarDatum: Identifiable {
        let id: Int; let x, y, size: CGFloat; let baseOpacity, phaseOffset: Double
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Star field
            TimelineView(.animation(minimumInterval: 1.0/20.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    for star in stars {
                        let o = star.baseOpacity * (0.35 + 0.65 * abs(sin(t * 0.8 + star.phaseOffset)))
                        let rect = CGRect(x: star.x - star.size/2, y: star.y - star.size/2,
                                          width: star.size, height: star.size)
                        ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(o)))
                    }
                }
            }
            .ignoresSafeArea()

            // Mood-tinted radial
            RadialGradient(
                colors: [speech.voiceState.orbState == .idle ? Color.clear : mood.accentColor.opacity(0.15), .clear],
                center: .center, startRadius: 60, endRadius: 320
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: speech.voiceState.label)

            VStack(spacing: 0) {
                Spacer()

                // AuroraOrbView — the full award-winning orb
                AuroraOrbView(
                    state:     speech.voiceState.orbState,
                    amplitude: speech.amplitude,
                    mood:      mood,
                    size:      248
                )
                .scaleEffect(orbRevealed ? 1.0 : 0.5)
                .opacity(orbRevealed ? 1 : 0)

                Spacer().frame(height: 44)

                // State labels
                VStack(spacing: 10) {
                    Text(speech.voiceState.label)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [orbAccent(speech.voiceState), .white.opacity(0.82)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .shadow(color: orbAccent(speech.voiceState).opacity(0.65), radius: 14)
                        .id(speech.voiceState.label)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal:   .opacity.combined(with: .offset(y: -8))
                        ))
                        .animation(FDS.Spring.standard, value: speech.voiceState.label)

                    Text(speech.voiceState.sublabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .opacity(contentOpacity)

                Spacer().frame(height: 52)

                // Recognized text preview
                if !speech.recognizedText.isEmpty {
                    Text("\"\(speech.recognizedText)\"")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36).padding(.bottom, 20)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }

                // Cancel
                Button(action: onCancel) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                        Text("Cancel").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(LinearGradient(
                        colors: [.white, orbAccent(speech.voiceState).opacity(0.85)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .padding(.horizontal, 36).padding(.vertical, 16)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
                    .overlay(Capsule().stroke(
                        LinearGradient(colors: [orbAccent(speech.voiceState).opacity(0.55), Color.white.opacity(0.15)],
                                       startPoint: .leading, endPoint: .trailing), lineWidth: 1.5
                    ))
                    .shadow(color: orbAccent(speech.voiceState).opacity(0.3), radius: 14, y: 4)
                }
                .buttonStyle(ScaleButtonStyle())
                .opacity(contentOpacity)
                .padding(.bottom, 72)
            }
        }
        .onChange(of: speech.voiceState) { _, state in
            if case .idle = state, !speech.recognizedText.isEmpty {
                onRecognized(speech.recognizedText)
            }
        }
        .onAppear {
            withAnimation(FDS.Spring.hero) { orbRevealed = true; contentOpacity = 1 }
        }
    }

    private func orbAccent(_ state: VoiceState) -> Color {
        switch state {
        case .idle:       return Color(hex: "00D2FF")
        case .listening:  return Color.ember
        case .processing: return Color(hex: "A855F7")
        case .speaking:   return Color(hex: "22C55E")
        case .error:      return Color(hex: "EF4444")
        }
    }
}

// ============================================================
// MARK: - XP Burst (dopamine reward)
// ============================================================

struct XPBurstView: View {
    let amount: Int
    @State private var scale:   CGFloat = 0.5
    @State private var opacity: Double  = 0
    @State private var offset:  CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "FFD700"))
            Text("+\(amount) XP")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "FFD700"))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(hex: "FFD700").opacity(0.15))
        .cornerRadius(FDS.Radius.pill)
        .overlay(Capsule().stroke(Color(hex: "FFD700").opacity(0.4), lineWidth: 1))
        .shadow(color: Color(hex: "FFD700").opacity(0.45), radius: 12, y: 4)
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(y: offset)
        .onAppear {
            withAnimation(FDS.Spring.hero) { scale = 1.1; opacity = 1 }
            withAnimation(FDS.Spring.snap.delay(0.18)) { scale = 1.0 }
            withAnimation(.easeIn(duration: 0.5).delay(0.9)) { opacity = 0; offset = -24 }
        }
    }
}

// ============================================================
// MARK: - Level Up Banner
// ============================================================

struct LevelUpBanner: View {
    let level: Int
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 52, height: 52)
                            .shadow(color: Color(hex: "FFD700").opacity(0.6), radius: 16)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LEVEL UP!")
                            .font(.system(size: 11, weight: .black))
                            .tracking(2.5)
                            .foregroundColor(Color(hex: "FFD700"))
                        Text("You reached Level \(level)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("ARIA is unlocking new insights for you.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .padding(20)
            .background(ZStack {
                Color.surface.opacity(0.96)
                LinearGradient(colors: [Color(hex: "FFD700").opacity(0.07), .clear], startPoint: .top, endPoint: .bottom)
            })
            .cornerRadius(FDS.Radius.xl)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(Color(hex: "FFD700").opacity(0.35), lineWidth: 1.5))
            .shadow(color: Color(hex: "FFD700").opacity(0.2), radius: 28, y: 10)
            .padding(.horizontal, 20).padding(.bottom, 120)
            .scaleEffect(appeared ? 1 : 0.82)
            .opacity(appeared ? 1 : 0)
            .onAppear { withAnimation(FDS.Spring.hero.delay(0.1)) { appeared = true } }
        }
    }
}

// ============================================================
// MARK: - Micro Confetti Burst (reaction reward)
// ============================================================

struct MicroConfettiBurst: View {
    let at: CGPoint
    @State private var particles: [BurstParticle] = []
    @State private var launched = false

    private struct BurstParticle: Identifiable {
        let id: Int; let color: Color; let angle: Double; let speed: CGFloat; let size: CGFloat
    }
    private let colors: [Color] = [.ember, Color(hex: "22C55E"), Color.steel,
                                    Color(hex: "FFD700"), Color(hex: "A855F7")]

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .offset(
                        x: launched ? cos(p.angle) * p.speed : 0,
                        y: launched ? sin(p.angle) * p.speed : 0
                    )
                    .opacity(launched ? 0 : 1)
                    .animation(.easeOut(duration: 0.8), value: launched)
            }
        }
        .position(at)
        .onAppear {
            particles = (0..<16).map { i in
                BurstParticle(
                    id: i,
                    color: colors[i % colors.count],
                    angle: Double(i) / 16.0 * .pi * 2,
                    speed: CGFloat.random(in: 40...90),
                    size:  CGFloat.random(in: 4...9)
                )
            }
            withAnimation { launched = true }
        }
    }
}

// ============================================================
// MARK: - Rich Cards
// ============================================================

struct RichCardView: View {
    let card: RichCardData
    var body: some View {
        switch card.type {
        case .workoutPlan: WorkoutRichCardView(card: card)
        case .dataChart:   DataChartRichCardView(card: card)
        }
    }
}

struct WorkoutRichCardView: View {
    let card: RichCardData
    @EnvironmentObject var store: AppStore
    @State private var expanded     = false
    @State private var startPressed = false
    @State private var appeared     = false

    var body: some View {
        VStack(spacing: 0) {
            FDS.Gradient.emberDeep.frame(height: 3)
                .cornerRadius(3, corners: [UIRectCorner.topLeft, UIRectCorner.topRight])

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: FDS.Radius.sm)
                        .fill(Color.ember.opacity(0.12)).frame(width: 46, height: 46)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 19)).foregroundStyle(FDS.Gradient.ember)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.workoutName ?? "Workout Plan")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.textPrimary)
                    HStack(spacing: 12) {
                        Label("\(card.workoutDuration ?? 0) min", systemImage: "clock.fill")
                        Label("\(card.workoutExercises?.count ?? 0) exercises", systemImage: "list.bullet")
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.textSecondary)
                }
                Spacer()
                Button {
                    withAnimation(FDS.Spring.standard) { expanded.toggle() }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(FDS.Gradient.ember)
                }
            }
            .padding(16)

            if expanded, let exercises = card.workoutExercises {
                Divider().background(Color.borderColor.opacity(0.3))
                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { i, ex in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.ember.opacity(0.1)).frame(width: 28, height: 28)
                                Text("\(i+1)").font(.system(size: 12, weight: .bold)).foregroundColor(.ember)
                            }
                            Text(ex.name).font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                            Spacer()
                            Text("\(ex.sets) × \(ex.reps)")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.surface).cornerRadius(FDS.Radius.xs)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .forgeEntrance(index: i, appeared: expanded)
                        if i < exercises.count - 1 {
                            Divider().background(Color.borderColor.opacity(0.22)).padding(.leading, 56)
                        }
                    }
                }
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            Divider().background(Color.borderColor.opacity(0.3))

            Button {
                store.startWorkout(); store.activeTab = .workout
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                    Text("Start This Workout").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(FDS.Gradient.emberDeep).cornerRadius(FDS.Radius.sm)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: FDS.Radius.sm)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center))
                        .frame(height: 20)
                }
                .shadow(color: Color.ember.opacity(startPressed ? 0.2 : 0.42), radius: startPressed ? 4 : 12, y: startPressed ? 1 : 5)
                .scaleEffect(startPressed ? 0.97 : 1).animation(FDS.Spring.snap, value: startPressed)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in startPressed = true }.onEnded { _ in startPressed = false })
            .padding(14)
        }
        .background(Color.surface)
        .cornerRadius(FDS.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.ember.opacity(0.2), lineWidth: 1))
        .shadow(color: Color.ember.opacity(0.08), radius: 14, y: 5)
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.1)) { appeared = true } }
    }
}

struct DataChartRichCardView: View {
    let card: RichCardData
    @State private var appeared = false
    @State private var hoverIdx: Int? = nil
    var values:   [Double] { card.chartValues ?? [] }
    var maxVal:   Double   { values.max() ?? 1 }
    var minVal:   Double   { values.min() ?? 0 }
    var barColor: Color    { card.chartColor ?? .steel }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [barColor.opacity(0.75), barColor.opacity(0.35)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 3).cornerRadius(3, corners: [UIRectCorner.topLeft, UIRectCorner.topRight])

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: FDS.Radius.xs).fill(barColor.opacity(0.14)).frame(width: 38, height: 38)
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 16)).foregroundColor(barColor)
                }
                Text(card.chartTitle ?? "Trend")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                Spacer()
                if let idx = hoverIdx, idx < values.count {
                    Text(String(format: "%.0f", values[idx]))
                        .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(barColor)
                        .transition(.opacity)
                }
            }
            .padding(14)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, val in
                        let norm = maxVal > minVal ? (val - minVal) / (maxVal - minVal) : 1
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [barColor.opacity(hoverIdx == i ? 0.95 : 0.55 + 0.45 * norm),
                                         barColor.opacity(hoverIdx == i ? 0.65 : 0.28 + 0.37 * norm)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(maxWidth: .infinity)
                            .frame(height: appeared ? max(6, 52 * CGFloat(norm)) : 4)
                            .scaleEffect(y: hoverIdx == i ? 1.07 : 1.0, anchor: .bottom)
                            .animation(FDS.Spring.hero.delay(Double(i) * 0.04), value: appeared)
                            .animation(FDS.Spring.snap, value: hoverIdx)
                            .onTapGesture {
                                withAnimation(FDS.Spring.snap) { hoverIdx = hoverIdx == i ? nil : i }
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                    }
                }
                .frame(height: 52)
                if let insight = card.chartInsight {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill").font(.system(size: 12)).foregroundColor(barColor.opacity(0.75))
                        Text(insight).font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary).lineSpacing(3)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: FDS.Radius.sm).fill(barColor.opacity(0.04)))
            .padding(12)
        }
        .background(Color.surface).cornerRadius(FDS.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(barColor.opacity(0.2), lineWidth: 1))
        .shadow(color: barColor.opacity(0.07), radius: 10, y: 4)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.1)) { appeared = true } }
    }
}

// MARK: - readinessColor helper
private func readinessColor(_ score: Int) -> Color {
    switch score {
    case 85...:   return Color(hex: "22C55E")
    case 70..<85: return Color.ember
    case 50..<70: return Color.steel
    default:      return Color(hex: "EF4444")
    }
}
