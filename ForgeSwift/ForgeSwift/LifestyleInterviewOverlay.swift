import SwiftUI
import ForgeCore

/// First open of Lifestyle — not onboarding. Tutorial, then who-you-are questions
/// that shift QoL weights and store a local living character. ARIA uses the same
/// persona Life just saved — on-device, no model trip, no family tree.
struct LifestyleInterviewOverlay: View {
    var onFinished: () -> Void

    private let lastStep = 8

    @State private var step = 0
    @State private var archetype: QualityOfLifeArchetype = .balanced
    @State private var movement: LivingMovementPreference = .mix
    @State private var hobbies: [LivingHobby] = []
    @State private var sleepNeed: Double = 8
    @State private var socialEnergy: Double = 6
    @State private var workStrain: Double = 4
    @State private var nutrition = "fuel"
    @State private var eatingRhythm: LivingEatingRhythm = .moderate

    private let nutritionChoices = ["fuel", "comfort", "chaotic", "careful"]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// First child of the scroll, so a step change can return to the top.
    private static let topAnchorID = "lifestyle-interview-top"

    // Full height in place (still the same ZStack layer in LifestyleView, not
    // a cover): the questions scroll, and the Back / Continue bar is pinned to
    // the bottom so Continue never leaves the screen at any text size.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    headerRow
                        .id(Self.topAnchorID)
                    stepContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: step) { _, _ in
                proxy.scrollTo(Self.topAnchorID, anchor: .top)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                navBar
                    .padding(.horizontal, ForgeLayout.screenInset)
                    .padding(.vertical, FDS.Spacing.sm)
                    .forgeBarChrome(edge: .bottom)
            }
        }
        // Opaque screen surface (it replaces the old 0.55 dim), so the page
        // underneath never bleeds through and never takes taps.
        .forgeScreenBackground(accent: .vitality)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The current step. Steps cross-fade (ZStack, so the outgoing and incoming
    /// steps overlap rather than stack); no motion under Reduce Motion.
    private var stepContent: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
    }

    /// ARIA eyebrow plus a quiet step-progress track (visual only; the value
    /// is announced as a percent by `ForgeProgressBar`).
    private var headerRow: some View {
        HStack(alignment: .center, spacing: FDS.Spacing.md) {
            Text("ARIA")
                .forgeSectionLabel(tint: .ember)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: FDS.Spacing.md)
            ForgeProgressBar(
                fraction: Double(step + 1) / Double(lastStep + 1),
                tint: .vitality,
                height: 4
            )
            .frame(maxWidth: 96)
        }
    }

    /// Back (secondary) and the overlay's one primary, Continue.
    private var navBar: some View {
        HStack(spacing: ForgeLayout.tileGap) {
            if step > 0 {
                ForgeSecondaryButton(title: "Back", accent: HudChrome.emberSteel) {
                    step -= 1
                }
                .frame(maxWidth: 120)
            }
            ForgePrimaryButton(title: step >= lastStep ? "That's me" : "Continue") {
                advance()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            copy(
                title: "This is Lifestyle.",
                body: "How you live a normal week — food, movement, sleep, free days. Not a second Home, and not an interrogation. I store that character locally so I can decide fast without calling the model."
            )
        case 1:
            copy(
                title: "How I grade QoL.",
                body: "I am not chasing a generic 8 hours and 10k steps. I am asking: are you happy, unstressed, mentally here, and still healthy in the life you actually live? 100 is possible. It is not the point. Life and I use the same number."
            )
        case 2:
            questionBlock(title: "Who are you, on a normal week?") {
                choice("Homebody", selected: archetype == .homebody) { archetype = .homebody }
                choice("Outdoors / camping weekends", selected: archetype == .outdoors) { archetype = .outdoors }
                choice("A mix", selected: archetype == .balanced) { archetype = .balanced }
            }
        case 3:
            questionBlock(
                title: "How do you like to move?",
                subtitle: "Not a program. The shape of a typical week."
            ) {
                ForEach(LivingMovementPreference.allCases, id: \.self) { item in
                    choice(item.title, selected: movement == item) { movement = item }
                }
            }
        case 4:
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                questionHeader(
                    title: "What fills a free day?",
                    subtitle: "Pick up to three. Hobbies, not relatives."
                )
                ForgeFlowLayout(lineSpacing: ForgeLayout.interactiveChipLineGap) {
                    ForEach(LivingHobby.allCases, id: \.self) { item in
                        ForgeChipButton(
                            label: item.title,
                            icon: hobbyIcon(item),
                            energy: .vitality,
                            selected: hobbies.contains(item)
                        ) {
                            toggleHobby(item)
                        }
                    }
                }
            }
        case 5:
            sliderBlock(
                title: "How much sleep do you actually want?",
                value: $sleepNeed,
                range: 5...9,
                label: String(format: "%.1f hours", sleepNeed)
            )
        case 6:
            sliderBlock(
                title: "Social energy this season",
                value: $socialEnergy,
                range: 0...10,
                label: String(format: "%.0f / 10", socialEnergy)
            )
        case 7:
            sliderBlock(
                title: "Work / money strain — not salary, just how heavy it feels",
                value: $workStrain,
                range: 0...10,
                label: String(format: "%.0f / 10", workStrain)
            )
        default:
            VStack(alignment: .leading, spacing: ForgeLayout.groupBreak) {
                questionBlock(title: "Food, for you, is mostly…") {
                    ForEach(nutritionChoices, id: \.self) { item in
                        choice(item.capitalized, selected: nutrition == item) { nutrition = item }
                    }
                }
                questionBlock(title: "And a normal day of eating is…") {
                    ForEach(LivingEatingRhythm.allCases, id: \.self) { item in
                        choice(item.title, selected: eatingRhythm == item) { eatingRhythm = item }
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    /// Question title (a prose title, not a metric) and optional subtitle.
    private func questionHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(title)
                .font(ForgeType.title)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
        }
    }

    /// A question over its single-select choice rows, `rowGap` between them.
    private func questionBlock<Choices: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder choices: () -> Choices
    ) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            questionHeader(title: title, subtitle: subtitle)
            VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
                choices()
            }
        }
    }

    private func copy(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(title)
                .font(ForgeType.title)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    /// Single-select row: a field-style tile on the screen background, tinted
    /// when selected (no glow), at least 44 pt, with the selected trait.
    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            FDS.haptic(.select)
            action()
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                Text(title)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: ForgeUX.icon, weight: .semibold))
                    .foregroundStyle(selected ? Color.vitality : Color.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.vertical, FDS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .fill(selected ? Color.vitality.opacity(0.14) : Color.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(
                        selected ? Color.vitality.opacity(0.32) : Color.borderHairline,
                        lineWidth: ForgeUX.hairline
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Slider question: prose title, the chosen value as a metric, the slider.
    private func sliderBlock(title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text(title)
                .font(ForgeType.title)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            Text(label)
                .font(HomeType.metric)
                .foregroundStyle(Color.vitality)
                .forgeSingleLine()
                .contentTransition(.numericText())
                .accessibilityHidden(true)
            Slider(value: value, in: range, step: 0.5)
                .tint(.vitality)
                .frame(minHeight: ForgeUX.minTap)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(label))
        }
    }

    /// Presentation only: a glyph per hobby so the chips scan at a glance.
    private func hobbyIcon(_ hobby: LivingHobby) -> String {
        switch hobby {
        case .outdoors: return "leaf.fill"
        case .gym:      return "dumbbell.fill"
        case .cooking:  return "frying.pan.fill"
        case .making:   return "hammer.fill"
        case .music:    return "music.note"
        case .reading:  return "book.fill"
        case .games:    return "gamecontroller.fill"
        case .rest:     return "sofa.fill"
        }
    }

    private func toggleHobby(_ item: LivingHobby) {
        if let idx = hobbies.firstIndex(of: item) {
            hobbies.remove(at: idx)
            return
        }
        guard hobbies.count < 3 else { return }
        hobbies.append(item)
    }

    private func advance() {
        if step < lastStep {
            step += 1
            return
        }
        let persona = QualityOfLifePersona(
            archetype: archetype,
            sleepNeedPreferenceHours: sleepNeed,
            socialEnergy0to10: socialEnergy,
            workStrain0to10: workStrain,
            nutritionRelationship: nutrition,
            eatingRhythm: eatingRhythm,
            movementPreference: movement,
            hobbies: hobbies.isEmpty ? nil : hobbies
        )
        QualityOfLifeLivingStore.savePersona(persona)
        QualityOfLifeLivingStore.markInterviewCompleted()
        AriaContextStore.shared.applyLivingCharacterTags(persona.livingTags())
        let source = "lifestyle-interview"
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .weSpokeAbout,
            kind: "lifestyle_archetype",
            summary: "You said you're a \(persona.archetype.title.lowercased()).",
            source: source
        ))
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .weSpokeAbout,
            kind: "sleep_need",
            summary: String(format: "You want about %.1f hours of sleep.", sleepNeed),
            source: source
        ))
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .weSpokeAbout,
            kind: "living_movement",
            summary: "You typically like to \(movement.title.lowercased()).",
            source: source
        ))
        if !hobbies.isEmpty {
            AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
                category: .weSpokeAbout,
                kind: "living_hobbies",
                summary: "Free days: \(hobbies.map { $0.title.lowercased() }.joined(separator: ", ")).",
                source: source
            ))
        }
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .weSpokeAbout,
            kind: "living_eating",
            summary: "Food is \(nutrition), \(eatingRhythm.title.lowercased()).",
            source: source
        ))
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .inferences,
            kind: "qol_weights",
            summary: inferenceLine(persona),
            source: source
        ))
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .inferences,
            kind: "living_character",
            summary: "Local character stored so ARIA can decide without a model round-trip.",
            source: source
        ))
        onFinished()
    }

    private func inferenceLine(_ persona: QualityOfLifePersona) -> String {
        switch persona.archetype {
        case .homebody:
            return "QoL weights sleep and nutrition over activity because you live more at home."
        case .outdoors:
            return "QoL weights activity, then vitals, nutrition, then sleep — weekends outside count."
        case .balanced, .unset:
            return "QoL stays balanced across sleep, movement, food, mind, and connection."
        }
    }
}
