import SwiftUI

// MARK: - Transcript

/// Where one message sits inside a run of same-speaker messages. Presentation
/// only: it drives spacing, the avatar and the bubble tail.
private struct MessageRunPosition {
    var isFirst: Bool
    var isLast: Bool
    var startsNewDay: Bool
}

struct MessageListView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isTyping:          Bool
    @Binding var showQuickActions:  Bool
    let ariaMood:      ARIAMood
    @Binding var swipeReply: ChatMessage?
    let onQuickAction:    (String) -> Void
    var onVoiceTap: (() -> Void)? = nil
    var onReaction: ((String, String) -> Void)? = nil
    let onReactionBurst:  (CGPoint) -> Void
    /// Cards that scroll away with the transcript (weekly review, proactive insight).
    var topContent: AnyView = AnyView(EmptyView())

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    topContent
                    if store.chatMessages.isEmpty {
                        ChatEmptyStateView(mood: ariaMood, onQuickActionTap: onQuickAction, onVoiceTap: onVoiceTap)
                    } else {
                        transcript
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.chatMessages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isTyping) { _, typing in if typing { scrollToBottom(proxy) } }
            .onChange(of: store.streamingVisibleCount) { _, _ in
                if store.streamingMessageId != nil { scrollToBottom(proxy, animated: false) }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scrollToBottom(proxy, animated: false) }
            }
        }
    }

    private var transcript: some View {
        let messages = store.chatMessages
        return LazyVStack(spacing: 0) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                messageRow(index: index, message: msg, messages: messages)
            }

            if isTyping {
                TypingIndicatorView(mood: ariaMood)
                    .id("typing")
                    .padding(.top, typingTopGap(messages))
                    .transition(.opacity)
            }

            Color.clear.frame(height: 1).id("bottom")
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.sm)
        .padding(.bottom, FDS.Spacing.lg)
    }

    @ViewBuilder
    private func messageRow(index: Int, message msg: ChatMessage, messages: [ChatMessage]) -> some View {
        let position = runPosition(at: index, in: messages)
        VStack(spacing: 0) {
            if position.startsNewDay {
                DateSeparatorView(date: msg.timestamp)
                    .padding(.top, index == 0 ? 0 : ForgeLayout.sectionGap)
                    .padding(.bottom, ForgeLayout.sectionGap)
            }
            MessageBubbleView(
                message:         msg,
                mood:            ariaMood,
                onSwipeReply:    { withAnimation(reduceMotion ? nil : FDS.Spring.standard) { swipeReply = msg } },
                onReaction:      onReaction,
                onReactionBurst: onReactionBurst,
                displayedContent: store.visibleContent(for: msg),
                isLastInRun:     position.isLast
            )
            .padding(.top, bubbleTopGap(index: index, position: position))
        }
        .id(msg.id)
        .animation(streamAnimation, value: streamTick(for: msg))
    }

    private var streamAnimation: Animation? {
        reduceMotion ? nil : Animation.linear(duration: 0.05)
    }

    /// Only the message being streamed reacts to the reveal counter.
    private func streamTick(for msg: ChatMessage) -> Int {
        store.streamingMessageId == msg.id ? store.streamingVisibleCount : 0
    }

    private func runPosition(at index: Int, in messages: [ChatMessage]) -> MessageRunPosition {
        let current = messages[index]
        let calendar = Calendar.current
        var startsNewDay = true
        var isFirst = true
        if index > 0 {
            let previous = messages[index - 1]
            startsNewDay = !calendar.isDate(previous.timestamp, inSameDayAs: current.timestamp)
            isFirst = startsNewDay || previous.role != current.role
        }
        var isLast = true
        if index < messages.count - 1 {
            let next = messages[index + 1]
            let nextStartsNewDay = !calendar.isDate(next.timestamp, inSameDayAs: current.timestamp)
            isLast = nextStartsNewDay || next.role != current.role
        }
        return MessageRunPosition(isFirst: isFirst, isLast: isLast, startsNewDay: startsNewDay)
    }

    /// 4 pt inside a run, 16 pt between runs.
    private func bubbleTopGap(index: Int, position: MessageRunPosition) -> CGFloat {
        if index == 0 || position.startsNewDay { return 0 }
        return position.isFirst ? ForgeLayout.sectionGap : FDS.Spacing.xs
    }

    private func typingTopGap(_ messages: [ChatMessage]) -> CGFloat {
        guard let last = messages.last else { return 0 }
        return last.role == .trainer ? FDS.Spacing.xs : ForgeLayout.sectionGap
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.26)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

struct DateSeparatorView: View {
    var date: Date = Date()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return Self.dayFormatter.string(from: date)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 0.5)
    }

    var body: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            hairline
            Text(label)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)
                .lineLimit(1)
                .fixedSize()
            hairline
        }
        .padding(.horizontal, FDS.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Message bubble

struct MessageBubbleView: View {
    let message:          ChatMessage
    let mood:             ARIAMood
    let onSwipeReply:     () -> Void
    var onReaction:       ((String, String) -> Void)? = nil
    let onReactionBurst:  (CGPoint) -> Void
    /// When set (streaming reveal), shows a progressive substring of the message.
    var displayedContent: String? = nil
    /// Last bubble of a same-speaker run: carries the avatar and the tail.
    var isLastInRun:      Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showTimestamp   = false
    @State private var showReactions   = false
    @State private var selectedReact:  String? = nil
    @State private var dragOffset:     CGFloat = 0
    @State private var replyTriggered  = false

    var isTrainer: Bool { message.role == .trainer }
    private var isHighConfidence: Bool { (message.confidence ?? 0) >= 0.85 }
    private var bodyText: String { displayedContent ?? message.content }
    private var isCompact: Bool { typeSize.isAccessibilitySize }
    private var sideReserve: CGFloat { isCompact ? 24 : 52 }
    private var avatarSize: CGFloat { 28 }
    private var speaker: String { isTrainer ? "ARIA" : "You" }
    private var richCardLeading: CGFloat { isTrainer && !isCompact ? 36 : 0 }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private let reactions: [(emoji: String, label: String)] = [
        ("🔥", "Fire"), ("💪", "Strong"), ("✅", "Got it"),
        ("😤", "Let's go"), ("🎯", "Locked in"), ("❤️", "Love")
    ]

    private func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    private var hasProvenance: Bool {
        guard isTrainer else { return false }
        let hasTools = !(message.toolCallsMade ?? []).isEmpty
        return message.memoryReference != nil
            || hasTools
            || message.replyShapeHeadline != nil
            || isHighConfidence
    }

    var body: some View {
        VStack(alignment: isTrainer ? .leading : .trailing, spacing: 0) {
            bubbleRow

            if let card = message.richCard {
                RichCardView(card: card)
                    .padding(.top, FDS.Spacing.sm)
                    .padding(.leading, richCardLeading)
            }

            if showReactions {
                reactionBar
                    .padding(.top, FDS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: isTrainer ? .leading : .trailing)
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                FDS.haptic(.success)
            } label: { Label("Copy", systemImage: "doc.on.doc") }

            Button {
                withAnimation(motion(FDS.Spring.standard)) { showReactions.toggle() }
            } label: { Label("React", systemImage: "face.smiling.fill") }

            Button {
                onSwipeReply()
            } label: { Label("Reply", systemImage: "arrowshape.turn.up.left.fill") }

            Button {
                withAnimation(motion(FDS.Spring.snap)) { showTimestamp.toggle() }
            } label: { Label("Show Time", systemImage: "clock") }
        }
    }

    // MARK: Row

    private var bubbleRow: some View {
        HStack(alignment: .bottom, spacing: FDS.Spacing.sm) {
            if !isTrainer { Spacer(minLength: sideReserve) }

            if isTrainer && !isCompact {
                avatarSlot
            }

            bubbleColumn

            if isTrainer { Spacer(minLength: sideReserve) }
        }
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if isLastInRun {
            ARIAIdentityMark(
                state: .idle,
                mood: mood,
                size: avatarSize,
                amplitude: 0.15
            )
        } else {
            Color.clear.frame(width: avatarSize, height: 1)
        }
    }

    private var bubbleColumn: some View {
        VStack(alignment: isTrainer ? .leading : .trailing, spacing: FDS.Spacing.xs) {
            swipeableBubble

            if hasProvenance {
                ChatProvenanceFooter(
                    memory: message.memoryReference,
                    tools: message.toolCallsMade ?? [],
                    replyHeadline: message.replyShapeHeadline,
                    replyDetail: message.replyShapeDetail,
                    isHighConfidence: isHighConfidence,
                    confidenceReason: message.confidenceReason
                )
            }

            if showTimestamp {
                timestampRow
                    .transition(.opacity)
            }

            if let reaction = selectedReact {
                ForgeChip(label: "\(reaction) You reacted", energy: .steel)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Bubble

    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(isTrainer: isTrainer, hasTail: isLastInRun)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isTrainer {
            Color.surfaceElevated
                .overlay(LinearGradient.premiumSurface)
        } else {
            ZStack(alignment: .top) {
                FDS.Gradient.emberDeep
                LinearGradient(
                    colors: [Color.white.opacity(0.14), .clear],
                    startPoint: .top, endPoint: .center
                )
            }
        }
    }

    @ViewBuilder
    private var bubbleStroke: some View {
        if isTrainer {
            bubbleShape.stroke(Color.white.opacity(0.16), lineWidth: ForgeUX.hairline)
        }
    }

    private var bubbleButton: some View {
        Button {
            withAnimation(motion(FDS.Spring.standard)) { showTimestamp.toggle() }
            FDS.haptic(.select)
        } label: {
            Text(bodyText)
                .font(HomeType.body)
                .foregroundStyle(isTrainer ? Color.textPrimary : Color.white)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, FDS.Spacing.lg)
                .padding(.vertical, FDS.Spacing.md)
                .background(bubbleBackground)
                .clipShape(bubbleShape)
                .overlay(bubbleStroke)
                .shadow(
                    color: Color.black.opacity(isTrainer ? 0.06 : 0.2),
                    radius: isTrainer ? 4 : 6,
                    y: 2
                )
        }
        .buttonStyle(.plain)
        .textSelection(.enabled)
        .accessibilityLabel("\(speaker): \(bodyText)")
        .accessibilityHint("Shows the time sent")
        .accessibilityValue(showTimestamp ? Self.timeFormatter.string(from: message.timestamp) : "")
        .accessibilityAction(named: "Reply") { onSwipeReply() }
    }

    private var swipeableBubble: some View {
        ZStack(alignment: isTrainer ? .trailing : .leading) {
            // Reply icon revealed on swipe
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 14))
                .foregroundStyle(mood.accentColor.opacity(min(1.0, abs(dragOffset) / 44.0)))
                .scaleEffect(min(1.2, abs(dragOffset) / 36.0))
                .offset(x: isTrainer ? 8 : -8)
                .accessibilityHidden(true)

            bubbleButton
                .offset(x: dragOffset)
                .gesture(swipeGesture)
        }
    }

    private var swipeGesture: some Gesture {
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
                withAnimation(motion(FDS.Spring.snap)) { dragOffset = 0 }
                replyTriggered = false
            }
    }

    private var timestampRow: some View {
        HStack(spacing: FDS.Spacing.xs) {
            Text(Self.timeFormatter.string(from: message.timestamp))
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
            if !isTrainer {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.vitality.opacity(0.75))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, FDS.Spacing.xs)
    }

    // MARK: Reactions

    private var reactionBar: some View {
        HStack(spacing: FDS.Spacing.xs) {
            ForEach(reactions, id: \.emoji) { r in
                reactionButton(r)
            }
        }
        .padding(FDS.Spacing.xs)
        .background(Color.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: ForgeUX.hairline))
        .shadow(color: Color.black.opacity(0.2), radius: 6, y: 2)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: isTrainer ? .bottomLeading : .bottomTrailing)))
    }

    private func reactionButton(_ r: (emoji: String, label: String)) -> some View {
        let isSelected = selectedReact == r.emoji
        return Button {
            withAnimation(motion(FDS.Spring.snap)) {
                selectedReact = selectedReact == r.emoji ? nil : r.emoji
                showReactions = false
            }
            if selectedReact == r.emoji {
                onReaction?(message.id, r.emoji)
            }
            choreographedHaptic(.reactionAdded)
        } label: {
            Text(r.emoji)
                .font(.system(size: 20))
                .accessibilityHidden(true)
                .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
                .background(isSelected ? mood.accentColor.opacity(0.2) : Color.clear, in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Provenance footer

/// One quiet footer under a trainer bubble: what ARIA remembered, which data
/// it used, how the reply was shaped and how sure it was. Regrouped from four
/// separate lines; nothing is dropped.
struct ChatProvenanceFooter: View {
    var memory: String? = nil
    var tools: [String] = []
    var replyHeadline: String? = nil
    var replyDetail: String? = nil
    var isHighConfidence: Bool = false
    var confidenceReason: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var memoryExpanded = false
    @State private var confidenceExpanded = false

    private var toolsLine: String {
        "ARIA used your data · " + tools.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
            ForgeFlowLayout(spacing: FDS.Spacing.xs, lineSpacing: FDS.Spacing.xs) {
                if let memory {
                    memoryChip(memory)
                }
                if isHighConfidence {
                    confidenceChip
                }
                if let replyHeadline {
                    ReplyShapeChip(headline: replyHeadline, detail: replyDetail)
                }
            }

            if memoryExpanded, let memory {
                detailText(memory)
            }
            if confidenceExpanded, let reason = confidenceReason, !reason.isEmpty {
                detailText(reason)
            }
            if !tools.isEmpty {
                detailText(toolsLine, color: Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailText(_ text: String, color: Color = Color.textSecondary) -> some View {
        Text(text)
            .font(HomeType.micro)
            .foregroundStyle(color)
            .forgeWrapping()
            .padding(.horizontal, FDS.Spacing.xs)
    }

    private func memoryChip(_ memory: String) -> some View {
        Button {
            FDS.haptic(.press)
            withAnimation(reduceMotion ? nil : FDS.Spring.standard) { memoryExpanded.toggle() }
        } label: {
            ForgeChip(label: memory, icon: "clock.arrow.circlepath", energy: .steel)
                .forgeTapOutset(vertical: ForgeLayout.chipTapOutset)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(memory)
        .accessibilityHint(memoryExpanded ? "Hides the full note" : "Shows the full note")
    }

    @ViewBuilder
    private var confidenceChip: some View {
        let chip = ForgeChip(label: "High confidence", icon: "checkmark.seal", energy: .steel, selected: true)
        if let reason = confidenceReason, !reason.isEmpty {
            Button {
                FDS.haptic(.press)
                withAnimation(reduceMotion ? nil : FDS.Spring.standard) { confidenceExpanded.toggle() }
            } label: {
                chip.forgeTapOutset(vertical: ForgeLayout.chipTapOutset)
            }
            .buttonStyle(.plain)
            .accessibilityHint(confidenceExpanded ? "Hides the reason" : "Shows why ARIA is confident")
        } else {
            chip
        }
    }
}

// MARK: - Reply preview

/// Reply context shown just above the composer. No band of its own: it sits
/// on the screen background with an ember rule, a micro label, a one-line
/// excerpt and a 44 pt dismiss target.
struct ReplyPreviewBar: View {
    let message: ChatMessage
    let onDismiss: () -> Void
    var isTrainer: Bool { message.role == .trainer }

    var body: some View {
        HStack(spacing: ForgeLayout.rowGap) {
            Capsule()
                .fill(Color.ember)
                .frame(width: 3)
                .padding(.vertical, FDS.Spacing.xs)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(isTrainer ? "Replying to ARIA" : "Replying to yourself")
                    .font(HomeType.micro)
                    .foregroundStyle(Color.ember)
                Text(message.content)
                    .font(HomeType.label)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: FDS.Spacing.xs)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.textTertiary)
                    .frame(minWidth: ForgeUX.minTap, minHeight: ForgeUX.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.sm)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Typing indicator

/// ARIA's single thinking bubble. Specialist chips (when several coaches are
/// consulted) replace the cycling label inside the same bubble. The dots move
/// only while ARIA is replying, and rest under Reduce Motion.
struct TypingIndicatorView: View {
    let mood: ARIAMood
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var dotAnimate = false
    @State private var stateLabel = "Reading you…"
    @State private var stateIcon  = "ellipsis"
    @State private var stateColor: Color = .ember
    @State private var showLabel  = false
    @State private var cycleTask: Task<Void, Never>? = nil

    private var steps: [(String, String, Color, Double)] {[
        ("Reading you…",      "ellipsis", mood.accentColor, 1.1),
        ("Holding the night…", "moon.fill", Color.indigo,   1.0),
        ("Finding the thread…", "waveform", Color.ember,    0.9),
        ("Almost.",           "ellipsis", Color.aurora,     0.7),
    ]}

    private var summaryLabel: String {
        let workers = store.lastCoachWorkers
        if workers.isEmpty { return "ARIA is thinking" }
        return "ARIA is thinking, consulting " + workers.map(\.label).joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: FDS.Spacing.sm) {
            if !typeSize.isAccessibilitySize {
                ARIAIdentityMark(state: .processing, mood: mood, size: 28, amplitude: 0.4)
            }

            thinkingBubble

            Spacer(minLength: typeSize.isAccessibilitySize ? 24 : 52)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryLabel)
        .onAppear {
            if !reduceMotion { dotAnimate = true }
            withAnimation(reduceMotion ? nil : Animation.easeInOut(duration: 0.2).delay(0.1)) { showLabel = true }
            stateColor = mood.accentColor
            startCycle()
            UIAccessibility.post(notification: .announcement, argument: "ARIA is thinking")
        }
        .onDisappear { cycleTask?.cancel(); cycleTask = nil }
        .animation(reduceMotion ? nil : FDS.Spring.standard, value: stateColor)
    }

    private var thinkingBubble: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            contextRow
            dotsRow
        }
        .padding(.horizontal, FDS.Spacing.lg)
        .padding(.vertical, FDS.Spacing.md)
        .background(Color.surfaceElevated)
        .clipShape(ChatBubbleShape(isTrainer: true))
        .overlay(ChatBubbleShape(isTrainer: true).stroke(Color.white.opacity(0.10), lineWidth: ForgeUX.hairline))
    }

    @ViewBuilder
    private var contextRow: some View {
        let workers = store.lastCoachWorkers
        if !workers.isEmpty {
            specialistBlock(workers)
        } else if showLabel {
            cycleLabel
        }
    }

    private var cycleLabel: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: stateIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(stateColor)
                .accessibilityHidden(true)
            Text(stateLabel)
                .font(HomeType.label)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .transition(.opacity)
    }

    private func specialistBlock(_ workers: [AriaCoachWorker]) -> some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
            Text(workers.count > 1 ? "Consulting your specialists" : "Thinking")
                .font(HomeType.micro)
                .foregroundStyle(Color.aurora)
            ForgeFlowLayout(spacing: FDS.Spacing.xs, lineSpacing: FDS.Spacing.xs) {
                ForEach(workers) { worker in
                    ForgeChip(
                        label: worker.label,
                        icon: worker.kind.icon,
                        energy: worker.kind.accent,
                        selected: true
                    )
                }
            }
        }
    }

    private var dotsRow: some View {
        HStack(spacing: FDS.Spacing.sm) {
            ForEach(0..<3, id: \.self) { i in
                dot(i)
            }
        }
    }

    private func dot(_ index: Int) -> some View {
        let scale: CGFloat = reduceMotion ? 1 : (dotAnimate ? 1.2 : 0.5)
        let opacity: Double = reduceMotion ? 0.7 : (dotAnimate ? 1 : 0.28)
        let pulse: Animation? = reduceMotion
            ? nil
            : Animation.easeInOut(duration: 0.52).repeatForever().delay(Double(index) * 0.17)
        return Circle()
            .fill(stateColor)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(pulse, value: dotAnimate)
    }

    private func startCycle() {
        cycleTask = Task {
            for (label, icon, color, duration) in steps {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(reduceMotion ? nil : FDS.Spring.standard) {
                        stateLabel = label; stateIcon = icon; stateColor = color
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(reduceMotion ? nil : Animation.easeInOut(duration: 0.2)) { showLabel = false }
            }
        }
    }
}

// MARK: - Reply shape chip

/// Tap-to-expand honesty chip. Names the living signals that bent this turn.
struct ReplyShapeChip: View {
    let headline: String
    var detail: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var hasDetail: Bool { !(detail ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
            Button {
                FDS.haptic(.press)
                withAnimation(reduceMotion ? nil : Animation.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                ForgeChip(label: headline, icon: "point.3.connected.trianglepath.dotted", energy: .steel)
                    .forgeTapOutset(vertical: ForgeLayout.chipTapOutset)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(headline)
            .accessibilityHint(hasDetail ? "Shows what shaped this reply" : "Shows the full note")
            .accessibilityValue(expanded ? (detail ?? "") : "")

            if expanded {
                VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                    Text(headline)
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(HomeType.micro)
                            .foregroundStyle(Color.textTertiary)
                            .lineSpacing(2)
                            .forgeWrapping()
                    }
                }
                .padding(.horizontal, FDS.Spacing.xs)
                .accessibilityHidden(true)
            }
        }
    }
}
