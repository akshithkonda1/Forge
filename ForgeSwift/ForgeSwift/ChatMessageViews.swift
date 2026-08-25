import SwiftUI

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
                                onReactionBurst: onReactionBurst,
                                displayedContent: store.visibleContent(for: msg)
                            )
                            .id(msg.id)
                            .animation(.linear(duration: 0.05), value: store.streamingVisibleCount)
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

struct MessageBubbleView: View {
    let message:          ChatMessage
    let mood:             ARIAMood
    let onSwipeReply:     () -> Void
    var onReaction:       ((String, String) -> Void)? = nil
    let onReactionBurst:  (CGPoint) -> Void
    /// When set (streaming reveal), shows a progressive substring of the message.
    var displayedContent: String? = nil

    @State private var appeared        = false
    @State private var showTimestamp   = false
    @State private var showReactions   = false
    @State private var selectedReact:  String? = nil
    @State private var dragOffset:     CGFloat = 0
    @State private var replyTriggered  = false

    var isTrainer: Bool { message.role == .trainer }
    private var isHighConfidence: Bool { (message.confidence ?? 0) >= 0.85 }
    private var bodyText: String { displayedContent ?? message.content }

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
                    // Memory reference pill — shown when ARIA recalled a past insight
                    if isTrainer, let memory = message.memoryReference {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.steel.opacity(0.8))
                            Text(memory)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textTertiary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.steel.opacity(0.08))
                        .cornerRadius(FDS.Radius.pill)
                        .overlay(Capsule().stroke(Color.steel.opacity(0.18), lineWidth: 0.5))
                        .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
                    }

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
                            Text(bodyText)
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
