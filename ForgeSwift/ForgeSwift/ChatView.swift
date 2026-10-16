import SwiftUI
import ForgeCore

/// Legacy press style, kept for call sites outside the chat transcript.
/// Delegates to the shared `ForgePressStyle` (0.98, snap, Reduce Motion aware).
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ForgePressStyle().makeBody(configuration: configuration)
    }
}

/// Chat bubble silhouette: continuous corners, with the run's last bubble
/// carrying a tighter "tail" corner on the speaker's side.
struct ChatBubbleShape: Shape {
    let isTrainer: Bool
    var hasTail: Bool = true

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 20
        let tailRadius: CGFloat = hasTail ? 6 : radius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: isTrainer ? tailRadius : radius,
            bottomTrailingRadius: isTrainer ? radius : tailRadius,
            topTrailingRadius: radius,
            style: .continuous
        )
        return shape.path(in: rect)
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
    @State private var sendTask: Task<Void, Never>? = nil

    @FocusState private var isInputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animation that collapses to nil under Reduce Motion.
    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    private var hasTopCards: Bool {
        weeklyReview.isDue || (proactiveInsight != nil && ariaContext.shouldBeProactive())
    }

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

                // ── Messages (banners scroll with the transcript) ─
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
                    onReactionBurst:  { _ in },
                    topContent:       AnyView(transcriptTopCards)
                )

                // Reply preview
                if let target = swipeReplyTarget {
                    ReplyPreviewBar(message: target) {
                        withAnimation(motion(ForgeMotion.snappy)) { swipeReplyTarget = nil }
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
                        AriaVoiceSession.shared.markThinking()
                        sendMessage(text)
                    },
                    onCancel: {
                        speech.cancel()
                        AriaVoiceSession.shared.stop()
                        withAnimation(motion(ForgeMotion.gentle)) { showVoiceOrb = false }
                    }
                )
                .zIndex(100)
                .forgeTransition(.opacity.combined(with: .move(edge: .bottom)))
            }

        }
        .animation(motion(ForgeMotion.gentle), value: showVoiceOrb)
        .animation(motion(ForgeMotion.smooth), value: swipeReplyTarget?.id)
        .sheet(isPresented: $showContextInspector) {
            ContextInspectorView(
                contextStore: ariaContext,
                richContext: ariaContext.buildRichContext(from: store)
            )
        }
        .onAppear {
            ariaMood = ARIAMood.derive(
                readiness: store.readiness.overall,
                sleepScore: SleepData.lastNight(in: store.sleepData)?.score
            )
            speech.conversationalMood = ariaMood
            ariaContext.updateProfile(
                goals: store.userProfile.fitnessGoals.map(\.label)
            )
            Task { await store.syncChatHistoryFromCloud() }
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
        .onChange(of: store.pendingIntimacySession) { _, _ in
            tryConsumeHandoff()
        }
        .onChange(of: store.ariaVoiceLaunch) { _, _ in
            tryConsumeHandoff()
        }
        .onChange(of: store.readiness.overall) { _, val in
            withAnimation(motion(ForgeMotion.smooth)) {
                ariaMood = ARIAMood.derive(
                    readiness: val,
                    sleepScore: SleepData.lastNight(in: store.sleepData)?.score
                )
            }
        }
        .onChange(of: ariaMood) { _, mood in
            speech.conversationalMood = mood
        }
        .onDisappear {
            // Nothing should keep running once chat is off-screen.
            speech.cancel()
            AriaVoiceSession.shared.stop()
            proactiveInsightTask?.cancel()
            sendTask?.cancel()
            isTyping = false
            showVoiceOrb = false
        }
        .onChange(of: speech.recognizedText) { _, text in
            guard !text.isEmpty else { return }
            inputText = text
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AriaNeuralVoiceGate.shared.refreshCatalog()
                Task { await store.refreshDailyData() }
            }
        }
    }

    // ── Transcript top cards ──────────────────────────────────────

    @ViewBuilder
    private var transcriptTopCards: some View {
        if hasTopCards {
            VStack(spacing: ForgeLayout.rowGap) {
                if weeklyReview.isDue {
                    weeklyReviewBanner
                }
                if let insight = proactiveInsight, ariaContext.shouldBeProactive() {
                    ProactiveCardView(
                        insight: insight,
                        relationshipLevel: ariaContext.context.relationshipLevel,
                        onTap: { sendMessage("Tell me more about: \(insight)") }
                    )
                }
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.top, ForgeLayout.screenTop)
            .padding(.bottom, ForgeLayout.blockGap)
        }
    }

    private var weeklyReviewBanner: some View {
        Button {
            weeklyReview.showSheet = true
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "calendar.badge.clock", tint: .ember)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text("Weekly evaluation is due")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text("Five questions. ARIA files the answers as standing context.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                .layoutPriority(1)
                Spacer(minLength: FDS.Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: ForgeUX.minTap)
            .forgeContentCard(tint: .ember, padding: ForgeLayout.compactCardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityHint("Opens the weekly evaluation")
    }

    /// Home / tab → chat bridge (prompt + optional one-shot voice orb).
    private func tryConsumeHandoff() {
        guard store.ariaPendingChatPrompt != nil
                || store.ariaVoiceLaunch
                || store.pendingIntimacySession != nil else { return }
        consumePendingHomeHandoff()
    }

    private func consumePendingHomeHandoff() {
        let result = ARIAChatHandoff.consume(
            .init(
                pendingPrompt: store.ariaPendingChatPrompt,
                voiceLaunch: store.ariaVoiceLaunch,
                intimacySession: store.pendingIntimacySession
            )
        )
        store.ariaPendingChatPrompt = nil
        store.ariaVoiceLaunch = false
        store.pendingIntimacySession = nil

        if result.startVoice {
            startVoiceCapture()
        }

        if let session = result.intimacySession {
            store.seedIntimacyConversation(session)
            showQuickActions = true
            return
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
        speech.conversationalMood = ariaMood
        withAnimation(motion(ForgeMotion.gentle)) { showVoiceOrb = true }
        AriaVoiceSession.shared.start(store: store, speech: speech)
    }

    // ── Send ──────────────────────────────────────────────────────

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isTyping, !store.isGeneratingResponse else { return }

        // "Call 911" / "Call or text 988" / "Call Poison Control" during a
        // safety session place the call instead of chatting about it. That is
        // escalation achieved: voice off, then the relationship check-in.
        if store.ariaSafetySession != nil, let number = AriaSafetyDialer.number(forAction: trimmed) {
            ForgeHaptics.play(.press)
            AriaSafetyDialer.dial(number)
            speech.cancel()
            withAnimation(motion(ForgeMotion.gentle)) { showVoiceOrb = false }
            store.safetyEscalationAchieved()
            return
        }

        ForgeHaptics.play(.press)

        if trimmed.lowercased().contains("not feeling") {
            withAnimation(motion(ForgeMotion.smooth)) { ariaMood = .pushed }
        }

        inputText = ""
        isTyping = true
        showQuickActions = store.isInAriaFirstBond
        swipeReplyTarget = nil
        proactiveInsight = nil

        sendTask?.cancel()
        if store.ariaVoiceMode || showVoiceOrb {
            let safetyTurn = AriaService.shared.decidesSafetyOnDevice(trimmed, store: store)
            AriaVoiceSession.shared.start(store: store, speech: speech, captureMic: false, onDevice: safetyTurn)
            AriaVoiceSession.shared.markThinking()
        }
        sendTask = Task {
            await store.sendMessage(trimmed)
            guard !Task.isCancelled else { return }
            isTyping = false
            if store.isInAriaFirstBond { showQuickActions = true }
            // Voice-first safety: a triage question or an emergency turns
            // ARIA's voice on by itself, on this iPhone's own voice; triage
            // listens for the answer once the question has been asked.
            let safety = store.ariaSafetySession
            if let safety, safety.wantsVoice {
                store.ariaVoiceMode = true
                withAnimation(motion(ForgeMotion.gentle)) { showVoiceOrb = true }
                AriaVoiceSession.shared.start(store: store, speech: speech, captureMic: false, onDevice: true)
                if safety.isTriage {
                    AriaVoiceSession.shared.listenAfterSpeaking()
                }
            }
            if store.ariaVoiceMode || showVoiceOrb || AriaVoiceSession.shared.isActive,
               let reply = store.chatMessages.last(where: {
                   $0.role == .trainer && !AppStore.isSafetyCheckIn($0)
               }) {
                let spoken = AriaResponse(proseSummary: reply.content, message: reply.content)
                if safety?.isResolved == true {
                    // Responsible resolution: say it, then voice turns off.
                    // The check-in bubble is already posted under the reply.
                    store.ariaVoiceMode = false
                    withAnimation(motion(ForgeMotion.gentle)) { showVoiceOrb = false }
                    AriaVoiceSession.shared.speakAndEnd(spoken)
                } else {
                    AriaVoiceSession.shared.speakChatReply(spoken)
                }
            }
        }
    }
}

/// Flat page. ARIA's mood shows in the content (accent on the mark and
/// chips), not as washes behind the conversation.
struct ChatBackground: View {
    let mood: ARIAMood

    var body: some View {
        Color.background
    }
}
