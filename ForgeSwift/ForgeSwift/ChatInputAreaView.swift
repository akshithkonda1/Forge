import SwiftUI

/// Makes the multi-specialist routing visible while it's happening, not
/// just afterward in ChatHeaderView's caption. This takes over the UI slot
/// AriaResearchProgress used to occupy between send and reply.
///
/// All workers show "thinking" for the actual duration of the wait, rather
/// than a staggered per-chip reveal: supportingBriefs() runs every
/// non-primary brief() concurrently over synchronous, near-instant local
/// computation, so real per-worker timing would flip every chip to "done"
/// within microseconds of each other. Faking a staggered reveal would be
/// less honest than showing "these specialists are being consulted" for
/// the real wait and then simply resolving to the reply.
struct AriaSpecialistActivityView: View {
    let workers: [AriaCoachWorker]
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            Text(workers.count > 1 ? "Consulting your specialists" : "Thinking")
                .font(HomeType.label)
                .foregroundColor(.aurora)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.chipGap) {
                ForEach(workers) { worker in
                    ForgeChip(
                        label: worker.label,
                        icon: worker.kind.icon,
                        energy: worker.kind.accent,
                        selected: true
                    )
                    .opacity(pulse ? 1 : 0.72)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeContentCard(tint: .aurora, padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .contain)
        .onAppear {
            // Event state: this card only exists while ARIA is working, and
            // it stays still under Reduce Motion.
            if reduceMotion {
                pulse = true
            } else {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

private struct CoachAgentChipRow: View {
    @EnvironmentObject var store: AppStore

    private var context: AriaCoachAgentRouter.Context {
        AriaCoachAgentRouter.context(pinned: store.pinnedCoachAgent, activeTab: store.activeTab)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ForgeLayout.chipGap) {
                pinChip(nil, title: "Auto", icon: "sparkles")
                // The five modes ARIA tracks, plus Cycle -- reachable here
                // too, still consent-gated, just not one of the five
                // headline modes. Not .allCases: that would also surface a
                // redundant direct pin to .aria, which "Auto" already covers.
                ForEach(AriaCoachAgent.trackedModes + [.cycle]) { agent in
                    if AriaCoachAgentRouter.isAvailable(agent, context: context) {
                        pinChip(agent, title: agent.label, icon: agent.icon)
                    }
                }
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            // Room for the chips' 44 pt tap outset.
            .padding(.vertical, FDS.Spacing.sm)
        }
        .accessibilityLabel("Personal coaches")
    }

    private func pinChip(_ agent: AriaCoachAgent?, title: String, icon: String) -> some View {
        let selected = store.pinnedCoachAgent == agent
        let energy: Color = agent?.accent ?? Color.ember
        return ForgeChipButton(
            label: title,
            icon: icon,
            energy: energy,
            selected: selected
        ) {
            store.pinnedCoachAgent = agent
            if let agent { store.lastRoutedCoachAgent = agent }
        }
    }
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isTyping
    }

    /// The quick-action rail rises in; under Reduce Motion it only fades.
    private var railTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !store.isInAriaFirstBond {
                CoachAgentChipRow()
            }

            suggestionRail

            inputRow
        }
        .forgeBarChrome(edge: .bottom)
    }

    // MARK: Suggestion rail

    @ViewBuilder
    private var suggestionRail: some View {
        if !store.lastSuggestedActions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ForgeLayout.chipGap) {
                    ForEach(store.lastSuggestedActions, id: \.self) { label in
                        suggestedChip(label)
                    }
                }
                .padding(.horizontal, ForgeLayout.screenInset)
                .padding(.vertical, FDS.Spacing.sm)
            }
        } else if showQuickActions && !isInputFocused && !store.chatMessages.isEmpty {
            // The empty state shows its own prompts, so the rail waits for a
            // first message instead of repeating them.
            quickActionRail
        }
    }

    private func suggestedChip(_ label: String) -> some View {
        let lower = label.lowercased()
        let yesLike = lower.hasPrefix("yes")
        let noLike = lower.hasPrefix("no")
        let icon = yesLike ? "checkmark" : (noLike ? "xmark" : "arrow.up.right")
        let tint: Color = yesLike ? Color.vitality : (noLike ? Color.steel : Color.ember)
        return SmartChip(label: label, icon: icon, color: tint, disabled: isTyping) {
            onSend(label)
            choreographedHaptic(.quickChipTap)
        }
    }

    private var quickActionRail: some View {
        let chips = smartQuickActions(
            mood:         mood,
            readiness:    store.readiness.overall,
            messageCount: store.chatMessages.count
        )
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ForgeLayout.chipGap) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    SmartChip(label: chip.label, icon: chip.icon, color: Color.ember, disabled: isTyping) {
                        onSend(chip.label)
                        choreographedHaptic(.quickChipTap)
                        withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 0.22)) { showQuickActions = false }
                    }
                }
            }
            .padding(.horizontal, ForgeLayout.screenInset)
            .padding(.vertical, FDS.Spacing.sm)
        }
        .transition(railTransition)
    }

    // MARK: Input row

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: FDS.Spacing.sm) {
            micButton
            textFieldBlock
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .padding(.top, FDS.Spacing.sm)
        .padding(.bottom, FDS.Spacing.sm)
    }

    private var micButton: some View {
        Button(action: onMicTap) {
            ZStack {
                Circle()
                    .fill(Color.ember.opacity(0.14))
                    .overlay(Circle().stroke(Color.ember.opacity(0.32), lineWidth: ForgeUX.hairline))
                Image(systemName: "mic.fill")
                    .font(.system(size: 19))
                    .foregroundColor(.ember)
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityLabel("Talk to ARIA")
        .disabled(isTyping)
        .opacity(isTyping ? 0.42 : 1)
        .animation(reduceMotion ? nil : FDS.Spring.snap, value: isTyping)
    }

    private var fieldBorder: Color {
        isInputFocused ? Color.ember.opacity(0.55) : Color.white.opacity(0.12)
    }

    private var textFieldBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: FDS.Radius.xxl, style: .continuous)
                .fill(Color.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: FDS.Radius.xxl, style: .continuous)
                        .stroke(fieldBorder, lineWidth: 1)
                )

            TextField("Ask ARIA anything…", text: $inputText, axis: .vertical)
                .font(HomeType.body)
                .foregroundColor(.textPrimary)
                .tint(Color.ember)
                .focused($isInputFocused)
                .disabled(isTyping)
                .padding(.leading, FDS.Spacing.lg)
                .padding(.trailing, 56)
                .padding(.vertical, 14)
                .lineLimit(1...5)
                .onSubmit { onSend(inputText) }
                .onChange(of: inputText) { _, text in
                    charCount = text.count
                    // Subtle typing haptic every 10 chars
                    if charCount % 10 == 0 && charCount > 0 {
                        choreographedHaptic(.typing)
                    }
                }

            sendButton
        }
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.18), value: isInputFocused)
    }

    private var sendButton: some View {
        Button { onSend(inputText) } label: {
            ZStack {
                Circle()
                    .fill(canSend
                        ? AnyShapeStyle(FDS.Gradient.emberDeep)
                        : AnyShapeStyle(Color.white.opacity(0.06)))
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(canSend ? .white : .textMuted)
            }
            .frame(width: 40, height: 40)
            .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
            .contentShape(Circle())
            .animation(reduceMotion ? nil : FDS.Spring.snap, value: canSend)
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityLabel("Send")
        .disabled(!canSend)
        .padding(2)
    }
}

struct SmartChip: View {
    let label:    String
    let icon:     String
    let color:    Color
    let disabled: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            ForgeChip(label: label, icon: icon, energy: color, selected: true)
                .forgeTapOutset(vertical: ForgeLayout.chipTapOutset)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .buttonStyle(ForgePressStyle())
        .accessibilityLabel(label)
    }
}
