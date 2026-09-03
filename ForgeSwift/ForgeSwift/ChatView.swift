import SwiftUI

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

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(FDS.Spring.snap, value: configuration.isPressed)
    }
}

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

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var speech = SpeechManager()
    @StateObject private var ariaContext = AriaContextStore.shared

    @State private var inputText:         String = ""
    @State private var isTyping:          Bool   = false
    @State private var showVoiceOrb:      Bool   = false
    @State private var showQuickActions:  Bool   = true
    @State private var ariaMood:          ARIAMood = .focused
    @State private var swipeReplyTarget:  ChatMessage? = nil
    @State private var showContextInspector = false
    @State private var proactiveInsight: String?
    @ObservedObject private var weeklyReview = WeeklyAriaReviewStore.shared

    // Cancellable timers for transient UI so nothing fires after teardown.
    @State private var proactiveInsightTask:  Task<Void, Never>? = nil

    @FocusState private var isInputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────
            ChatBackground(mood: ariaMood)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────
                ChatHeaderView(
                    mood:              ariaMood,
                    onAvatarLongPress: { showContextInspector = true }
                )

                if weeklyReview.isDue {
                    Button {
                        weeklyReview.showSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.ember)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Weekly evaluation is due")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text("Five questions. ARIA files the answers as standing context.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textTertiary)
                        }
                        .padding(14)
                        .background(Color.ember.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                                .stroke(Color.ember.opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

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
                    onVoiceTap:       startVoiceCapture,
                    onReaction:       { messageId, emoji in
                        Task {
                            await FeedbackService.shared.processReaction(
                                userId: ariaContext.context.userId,
                                messageId: messageId,
                                reaction: emoji
                            )
                        }
                    },
                    onReactionBurst:  { _ in }
                )

                // Reply preview bar
                if let target = swipeReplyTarget {
                    ReplyPreviewBar(message: target) {
                        withAnimation(FDS.Spring.snap) { swipeReplyTarget = nil }
                    }
                }

                // ── Input ────────────────────────────────────────
                if isTyping, !store.lastCoachWorkers.isEmpty {
                    AriaSpecialistActivityView(workers: store.lastCoachWorkers)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ChatInputAreaView(
                    inputText:        $inputText,
                    isTyping:         $isTyping,
                    isInputFocused:   $isInputFocused,
                    showQuickActions: $showQuickActions,
                    mood:             ariaMood,
                    replyTarget:      swipeReplyTarget,
                    onSend:           sendMessage,
                    onMicTap: startVoiceCapture
                )
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
                .zIndex(100)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
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
            ariaMood = ARIAMood.derive(
                readiness: store.readiness.overall,
                sleepScore: store.sleepData.first?.score
            )
            speech.conversationalMood = ariaMood
            ariaContext.configure(userId: store.userProfile.name)
            ariaContext.updateProfile(
                goals: store.userProfile.fitnessGoals.map(\.label),
                lifestyleTags: [store.userProfile.experienceLevel.label]
            )
            proactiveInsightTask?.cancel()
            proactiveInsightTask = Task { @MainActor in
                let insight = await AriaService.shared.fetchProactiveMessage(store: store)
                guard !Task.isCancelled else { return }
                proactiveInsight = insight
            }
            consumePendingHomeHandoff()
            weeklyReview.considerPresenting()
            store.startAriaFirstBondIfNeeded()
            if store.isInAriaFirstBond {
                showQuickActions = true
            }
        }
        .onChange(of: store.ariaPendingChatPrompt) { _, _ in
            tryConsumeHandoff()
        }
        .onChange(of: store.ariaVoiceLaunch) { _, _ in
            tryConsumeHandoff()
        }
        .onChange(of: store.readiness.overall) { _, val in
            withAnimation(FDS.Spring.standard) {
                ariaMood = ARIAMood.derive(
                    readiness: val,
                    sleepScore: store.sleepData.first?.score
                )
            }
        }
        .onChange(of: ariaMood) { _, mood in
            speech.conversationalMood = mood
        }
        .onDisappear {
            // Nothing should keep running once chat is off-screen.
            speech.cancel()
            proactiveInsightTask?.cancel()
            showVoiceOrb = false
        }
        .onChange(of: speech.recognizedText) { _, text in
            guard !text.isEmpty else { return }
            inputText = text
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshDailyData() } }
        }
    }

    /// Home / tab → chat bridge (prompt + optional one-shot voice orb).
    private func tryConsumeHandoff() {
        guard store.ariaPendingChatPrompt != nil || store.ariaVoiceLaunch else { return }
        consumePendingHomeHandoff()
    }

    private func consumePendingHomeHandoff() {
        let result = ARIAChatHandoff.consume(
            .init(pendingPrompt: store.ariaPendingChatPrompt, voiceLaunch: store.ariaVoiceLaunch)
        )
        store.ariaPendingChatPrompt = nil
        store.ariaVoiceLaunch = false

        if result.startVoice {
            startVoiceCapture()
        }

        if let prompt = result.prompt {
            inputText = prompt
            if result.autoSend {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    sendMessage(prompt)
                }
            }
        }
    }

    private func startVoiceCapture() {
        choreographedHaptic(.voiceStart, mood: ariaMood)
        speech.conversationalMood = ariaMood
        withAnimation(FDS.Spring.hero) { showVoiceOrb = true }
        speech.startListening()
    }

    // ── Send ──────────────────────────────────────────────────────

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isTyping else { return }

        choreographedHaptic(.messageSent, mood: ariaMood)

        if trimmed.lowercased().contains("not feeling") {
            withAnimation(FDS.Spring.standard) { ariaMood = .pushed }
        }

        inputText = ""
        isTyping = true
        showQuickActions = store.isInAriaFirstBond
        swipeReplyTarget = nil
        proactiveInsight = nil

        Task {
            await store.sendMessage(trimmed)
            isTyping = false
            if store.isInAriaFirstBond { showQuickActions = true }
            choreographedHaptic(.messageReceived, mood: ariaMood)
        }
    }
}

struct ChatBackground: View {
    let mood: ARIAMood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.background
            RadialGradient(
                colors: [mood.accentColor.opacity(0.12), Color.aurora.opacity(0.04), .clear],
                center: UnitPoint(x: 0.2, y: 0.05),
                startRadius: 10,
                endRadius: 380
            )
            RadialGradient(
                colors: [Color.ember.opacity(0.06), .clear],
                center: UnitPoint(x: 0.9, y: 0.9),
                startRadius: 8,
                endRadius: 300
            )
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let colors = [
                            Color(hex: "00FFF0").opacity(0.035),
                            Color(hex: "0080FF").opacity(0.03),
                            Color.aurora.opacity(0.025),
                            mood.accentColor.opacity(0.02)
                        ]
                        for i in 0..<4 {
                            let x = size.width * CGFloat(i) / 4 + CGFloat(sin(time * 0.3 + Double(i))) * 36
                            let y = size.height / 2 + CGFloat(cos(time * 0.4 + Double(i))) * 50
                            let rect = CGRect(x: x, y: y, width: size.width / 2.2, height: size.height / 2.2)
                            context.fill(Path(ellipseIn: rect), with: .color(colors[i]))
                        }
                    }
                }
                .blur(radius: 70)
                .opacity(0.22)
            }
        }
        .animation(.easeInOut(duration: 1.4), value: mood)
    }
}
