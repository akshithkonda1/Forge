import SwiftUI
import ForgeCore

/// Settings vault: view / add / edit / delete ARIA notes, pause memory
/// without wiping it, edit who-you-are, and set tone + check-ins.
struct AriaMemoryControlsView: View {
    @StateObject private var model = AriaMemoryControlsViewModel()
    @State private var showEditor = false
    @State private var showLifestyleInterview = false
    @State private var confirmForgetPersona = false
    @State private var confirmDeleteFact: AriaKnowledgeFact?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            ForgeScreenStack(top: FDS.Spacing.sm) {
                Text(AriaFactPrivacy.privacyLine)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()

                memoryCard
                personaCard
                toneCard
                checkInCard

                ForEach(AriaKnowledgeCategory.managedCases, id: \.self) { folder in
                    folderCard(folder)
                }
            }
        }
        .forgeScreenBackground(accent: .ember)
        .navigationTitle("ARIA memory & voice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .foregroundColor(.ember)
                    .accessibilityLabel("Done")
            }
        }
        .onAppear { model.reload() }
        .transaction(freezeMotion)
        .sheet(isPresented: $showEditor) {
            editorSheet
                .transaction(freezeMotion)
        }
        .fullScreenCover(isPresented: $showLifestyleInterview) {
            LifestyleInterviewOverlay {
                showLifestyleInterview = false
                model.reload()
                AriaContextStore.shared.applyLivingCharacterTags(
                    QualityOfLifeLivingStore.livingTags()
                )
            }
            .transaction(freezeMotion)
        }
        .confirmationDialog(
            "Forget who I am?",
            isPresented: $confirmForgetPersona,
            titleVisibility: .visible
        ) {
            Button("Forget who I am", role: .destructive) {
                model.clearPersona()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This clears the on-device living profile. Notes in the folders stay until you delete them.")
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { confirmDeleteFact != nil },
                set: { if !$0 { confirmDeleteFact = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let fact = confirmDeleteFact {
                    model.delete(fact)
                }
                confirmDeleteFact = nil
            }
            Button("Keep it", role: .cancel) {
                confirmDeleteFact = nil
            }
        }
    }

    // MARK: Cards

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            toggleRow(
                icon: "brain.head.profile",
                label: AriaMemoryAccess.rememberMeLabel,
                subtitle: model.controls.memoryStatusLine,
                isOn: Binding(
                    get: { model.memoryOn },
                    set: { model.setMemoryEnabled($0) }
                ),
                hint: AriaMemoryAccess.rememberMeHint,
                value: AriaMemoryAccess.rememberMeValue(isOn: model.memoryOn)
            )
            Text(model.memoryOn
                 ? "ARIA uses the notes below. Turn this off and I stop using them — nothing is deleted."
                 : "Memory is off. Notes stay here until you delete them. ARIA isn't using them.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .forgeContentCard(accent: .ember)
    }

    private var personaCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            toggleRow(
                icon: "person.fill",
                label: AriaMemoryAccess.personaLabel,
                subtitle: nil,
                isOn: Binding(
                    get: { model.controls.prefs.personaEnabled },
                    set: { model.setPersonaEnabled($0) }
                ),
                hint: AriaMemoryAccess.personaHint,
                value: AriaMemoryAccess.rememberMeValue(isOn: model.controls.prefs.personaEnabled)
            )
            Text(model.controls.persona.archetype.title)
                .font(ForgeType.title)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            personaChips
            Text("Simple chips only, never a medical read.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            personaActions
        }
        .forgeContentCard(accent: .ember)
    }

    @ViewBuilder
    private var personaChips: some View {
        let hours = model.controls.persona.sleepNeedPreferenceHours
        let move = model.controls.persona.movementPreference
        if hours != nil || move != nil {
            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.chipGap) {
                if let hours {
                    ForgeChip(label: String(format: "Sleep want: %.1f h", hours), icon: "moon.fill")
                }
                if let move {
                    ForgeChip(label: "Typical movement: \(move.title)", icon: "figure.walk")
                }
            }
        }
    }

    private var showsForgetPersona: Bool {
        model.controls.interviewCompleted
            || model.controls.persona.archetype != .balanced
            || model.controls.persona.movementPreference != nil
    }

    private var personaActions: some View {
        let actionLabel = AriaMemoryAccess.personaActionLabel(
            interviewCompleted: model.controls.interviewCompleted
        )
        return ForgeAdaptiveStack(spacing: ForgeLayout.tileGap) {
            ForgeSecondaryButton(title: actionLabel, accent: .ember) {
                QualityOfLifeLivingStore.clearInterviewCompleted()
                showLifestyleInterview = true
            }
            .accessibilityLabel(actionLabel)
            .accessibilityAddTraits(.isButton)
            if showsForgetPersona {
                ForgeSecondaryButton(title: AriaMemoryAccess.forgetPersonaLabel, accent: .danger) {
                    confirmForgetPersona = true
                }
                .accessibilityLabel(AriaMemoryAccess.forgetPersonaLabel)
                .accessibilityHint(AriaMemoryAccess.forgetPersonaHint)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private var toneCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(AriaMemoryAccess.howITalkHeader, tint: .steel)
            Text("Friend first. Not a clinician.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(AriaCompanionTone.allCases, id: \.self) { tone in
                    let selected = model.controls.prefs.tone == tone
                    optionRow(
                        title: tone.title,
                        line: tone.line,
                        selected: selected,
                        label: AriaMemoryAccess.toneLabel(tone, selected: selected)
                    ) {
                        model.setTone(tone)
                    }
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(AriaMemoryAccess.checkInsHeader, tint: .steel)
            Text("How often I ask how life is going. On this phone.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(AriaCheckInCadence.allCases, id: \.self) { cadence in
                    let selected = model.controls.prefs.checkInCadence == cadence
                    optionRow(
                        title: cadence.title,
                        line: cadence.detail,
                        selected: selected,
                        label: AriaMemoryAccess.checkInLabel(cadence, selected: selected)
                    ) {
                        model.setCheckInCadence(cadence)
                    }
                }
            }
        }
        .forgeContentCard(tint: .steel)
    }

    private func folderCard(_ folder: AriaKnowledgeCategory) -> some View {
        let items = model.facts(in: folder)
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: folder.title, tint: .steel) {
                ForgeCardMeta(text: "\(items.count)")
                    .accessibilityLabel("\(items.count) notes")
            }
            Text(folder.blurb)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            folderToggleRow(folder)
            if items.isEmpty {
                ForgeEmptyNote(title: "Nothing in this folder yet.", systemImage: folder.systemImage, tint: .steel)
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(items.prefix(20)) { fact in
                        noteRow(fact, in: folder)
                    }
                }
            }
            ForgeTextLink(title: "Add a note", accent: .ember) {
                model.beginAdd(to: folder)
                showEditor = true
            }
            .accessibilityLabel(AriaMemoryAccess.addNoteLabel(folder: folder))
            .accessibilityAddTraits(.isButton)
        }
        .forgeContentCard(tint: .steel)
    }

    // MARK: Pieces

    /// Agenda-row anatomy for a card's lead switch: icon well, label (with an
    /// optional status line), then the switch. It sits at the card padding.
    private func toggleRow(
        icon: String,
        label: String,
        subtitle: String?,
        isOn: Binding<Bool>,
        hint: String,
        value: String
    ) -> some View {
        HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: icon, tint: .ember)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(label)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .forgeWrapping()
                if let subtitle {
                    Text(subtitle)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForgeToggle(isOn: isOn)
                .accessibilityLabel(label)
                .accessibilityHint(hint)
                .accessibilityValue(value)
        }
        .frame(minHeight: ForgeUX.minTap)
    }

    private func folderToggleRow(_ folder: AriaKnowledgeCategory) -> some View {
        HStack(spacing: ForgeLayout.rowGap) {
            Text(AriaMemoryAccess.folderUseLabel(folder))
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
            ForgeToggle(isOn: Binding(
                get: { model.isFolderOn(folder) },
                set: { model.setFolder(folder, enabled: $0) }
            ))
            .accessibilityLabel(AriaMemoryAccess.folderUseLabel(folder))
            .accessibilityHint(AriaMemoryAccess.folderUseHint)
            .accessibilityValue(AriaMemoryAccess.rememberMeValue(isOn: model.isFolderOn(folder)))
        }
        .frame(minHeight: ForgeUX.minTap)
    }

    /// One radio-style choice: indicator, title, line. The whole row is the
    /// tap target and carries the selected trait.
    private func optionRow(
        title: String,
        line: String,
        selected: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            ForgeHaptics.play(.selection)
            action()
        } label: {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? Color.ember : Color.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(title)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .forgeWrapping()
                    Text(line)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .frame(minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(line)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// A note: summary over its dateline, then Edit and Delete as 44 pt text
    /// links set well apart. A long press offers the same two actions.
    private func noteRow(_ fact: AriaKnowledgeFact, in folder: AriaKnowledgeCategory) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(fact.summary)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            Text(dateline(fact))
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(2)
            HStack(spacing: ForgeLayout.groupBreak) {
                ForgeTextLink(title: "Edit", accent: .ember) {
                    model.beginEdit(fact)
                    showEditor = true
                }
                .accessibilityLabel(AriaMemoryAccess.editNoteLabel(
                    folder: folder,
                    summary: fact.summary
                ))
                .accessibilityAddTraits(.isButton)
                ForgeTextLink(title: "Delete", accent: .danger) {
                    confirmDeleteFact = fact
                }
                .accessibilityLabel(AriaMemoryAccess.deleteNoteLabel(
                    folder: folder,
                    summary: fact.summary
                ))
                .accessibilityAddTraits(.isButton)
                Spacer(minLength: 0)
            }
            .padding(.top, ForgeLayout.pairGap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .contextMenu {
            Button {
                model.beginEdit(fact)
                showEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmDeleteFact = fact
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var editorSheet: some View {
        NavigationStack {
            ScrollView {
                ForgeScreenStack(top: FDS.Spacing.lg) {
                    Text("Kinds and days-until only. No calendar titles, people on the invite, or places.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                    if model.editingID == nil {
                        Picker(AriaMemoryAccess.folderPickerLabel, selection: $model.draftCategory) {
                            ForEach(AriaKnowledgeCategory.managedCases, id: \.self) { folder in
                                Text(folder.title).tag(folder)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minHeight: ForgeUX.minTap)
                        .accessibilityLabel(AriaMemoryAccess.folderPickerLabel)
                    }
                    TextField("A short note", text: $model.draftSummary, axis: .vertical)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(3...8)
                        .padding(FDS.Spacing.md)
                        .forgeInsetTile(radius: FDS.Radius.md)
                        .accessibilityLabel(AriaMemoryAccess.noteFieldLabel)
                    if let addError = model.addError {
                        Text(addError)
                            .font(HomeType.body)
                            .foregroundStyle(Color.danger)
                            .forgeWrapping()
                    }
                }
            }
            .forgeScreenBackground(accent: .ember)
            .navigationTitle(model.editingID == nil ? "Add a note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AriaMemoryAccess.cancelEditorLabel) { showEditor = false }
                        .accessibilityLabel(AriaMemoryAccess.cancelEditorLabel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AriaMemoryAccess.saveNoteLabel) {
                        if model.commitDraft() {
                            showEditor = false
                        }
                    }
                    .foregroundColor(.ember)
                    .disabled(model.draftSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(AriaMemoryAccess.saveNoteLabel)
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
        .presentationDetents(reduceMotion ? [.large] : [.medium, .large])
    }

    private func freezeMotion(_ transaction: inout Transaction) {
        guard !AriaMemoryAccess.shouldAnimate(reduceMotion: reduceMotion) else { return }
        transaction.disablesAnimations = true
        transaction.animation = nil
    }

    private func dateline(_ fact: AriaKnowledgeFact) -> String {
        let day = fact.createdAt.formatted(date: .abbreviated, time: .omitted)
        return "\(day) · \(fact.source)"
    }
}
