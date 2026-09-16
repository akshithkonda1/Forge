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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(AriaFactPrivacy.privacyLine)
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                memoryCard
                personaCard
                toneCard
                checkInCard

                ForEach(AriaKnowledgeCategory.managedCases, id: \.self) { folder in
                    folderCard(folder)
                }
            }
            .padding(20)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("ARIA memory & voice")
        .navigationBarTitleDisplayMode(.large)
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

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(icon: "brain.head.profile", iconColor: .ember, label: AriaMemoryAccess.rememberMeLabel) {
                ForgeToggle(isOn: Binding(
                    get: { model.memoryOn },
                    set: { model.setMemoryEnabled($0) }
                ))
                .accessibilityLabel(AriaMemoryAccess.rememberMeLabel)
                .accessibilityHint(AriaMemoryAccess.rememberMeHint)
                .accessibilityValue(AriaMemoryAccess.rememberMeValue(isOn: model.memoryOn))
            }
            Text(model.memoryOn
                 ? "ARIA uses the notes below. Turn this off and I stop using them — nothing is deleted."
                 : "Memory is off. Notes stay here until you delete them. ARIA isn't using them.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            Text(model.controls.memoryStatusLine)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .forgeGlassCard(cornerRadius: 16, accent: .ember)
    }

    private var personaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(icon: "person.fill", iconColor: .ember, label: AriaMemoryAccess.personaLabel) {
                ForgeToggle(isOn: Binding(
                    get: { model.controls.prefs.personaEnabled },
                    set: { model.setPersonaEnabled($0) }
                ))
                .accessibilityLabel(AriaMemoryAccess.personaLabel)
                .accessibilityHint(AriaMemoryAccess.personaHint)
                .accessibilityValue(AriaMemoryAccess.rememberMeValue(isOn: model.controls.prefs.personaEnabled))
            }
            Text(model.controls.persona.archetype.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 16)
            if let hours = model.controls.persona.sleepNeedPreferenceHours {
                Text(String(format: "Sleep want: %.1f h", hours))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 16)
            }
            if let move = model.controls.persona.movementPreference {
                Text("Typical movement: \(move.title)")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 16)
            }
            Text("Closed chips only. Not a family tree, not a diagnosis.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 16)
            HStack(spacing: 16) {
                Button {
                    QualityOfLifeLivingStore.clearInterviewCompleted()
                    showLifestyleInterview = true
                } label: {
                    Text(AriaMemoryAccess.personaActionLabel(
                        interviewCompleted: model.controls.interviewCompleted
                    ))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.ember)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AriaMemoryAccess.personaActionLabel(
                    interviewCompleted: model.controls.interviewCompleted
                ))
                .accessibilityAddTraits(.isButton)
                if model.controls.interviewCompleted
                    || model.controls.persona.archetype != .balanced
                    || model.controls.persona.movementPreference != nil {
                    Button {
                        confirmForgetPersona = true
                    } label: {
                        Text(AriaMemoryAccess.forgetPersonaLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AriaMemoryAccess.forgetPersonaLabel)
                    .accessibilityHint(AriaMemoryAccess.forgetPersonaHint)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var toneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AriaMemoryAccess.howITalkHeader)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Friend first. Not a clinician.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
            ForEach(AriaCompanionTone.allCases, id: \.self) { tone in
                let selected = model.controls.prefs.tone == tone
                Button {
                    model.setTone(tone)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selected ? .ember : .textTertiary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tone.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(tone.line)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AriaMemoryAccess.toneLabel(tone, selected: selected))
                .accessibilityHint(tone.line)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(16)
        .forgeGlassCard(cornerRadius: 16, accent: .steel)
    }

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AriaMemoryAccess.checkInsHeader)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("How often I ask how life is going. On this phone.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
            ForEach(AriaCheckInCadence.allCases, id: \.self) { cadence in
                let selected = model.controls.prefs.checkInCadence == cadence
                Button {
                    model.setCheckInCadence(cadence)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selected ? .ember : .textTertiary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cadence.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(cadence.detail)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AriaMemoryAccess.checkInLabel(cadence, selected: selected))
                .accessibilityHint(cadence.detail)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(16)
        .forgeGlassCard(cornerRadius: 16, accent: .steel)
    }

    private func folderCard(_ folder: AriaKnowledgeCategory) -> some View {
        let items = model.facts(in: folder)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: folder.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ember)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(folder.blurb)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .accessibilityLabel("\(items.count) notes")
            }
            SettingsRow(icon: nil, label: AriaMemoryAccess.folderUseLabel(folder)) {
                ForgeToggle(isOn: Binding(
                    get: { model.isFolderOn(folder) },
                    set: { model.setFolder(folder, enabled: $0) }
                ))
                .accessibilityLabel(AriaMemoryAccess.folderUseLabel(folder))
                .accessibilityHint(AriaMemoryAccess.folderUseHint)
                .accessibilityValue(AriaMemoryAccess.rememberMeValue(isOn: model.isFolderOn(folder)))
            }
            if items.isEmpty {
                Text("Nothing in this folder yet.")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
            } else {
                ForEach(items.prefix(20)) { fact in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(fact.summary)
                            .font(.system(size: 13))
                            .foregroundColor(.textPrimary)
                        HStack {
                            Text(dateline(fact))
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                            Spacer()
                            Button("Edit") {
                                model.beginEdit(fact)
                                showEditor = true
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.ember)
                            .accessibilityLabel(AriaMemoryAccess.editNoteLabel(
                                folder: folder,
                                summary: fact.summary
                            ))
                            .accessibilityAddTraits(.isButton)
                            Button("Delete", role: .destructive) {
                                confirmDeleteFact = fact
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.danger)
                            .accessibilityLabel(AriaMemoryAccess.deleteNoteLabel(
                                folder: folder,
                                summary: fact.summary
                            ))
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            Button {
                model.beginAdd(to: folder)
                showEditor = true
            } label: {
                Text("Add a note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ember)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel(AriaMemoryAccess.addNoteLabel(folder: folder))
            .accessibilityAddTraits(.isButton)
        }
        .padding(16)
        .forgeGlassCard(cornerRadius: 16, accent: .steel)
    }

    private var editorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Kinds and days-until only. No calendar titles, people on the invite, or places.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                if model.editingID == nil {
                    Picker(AriaMemoryAccess.folderPickerLabel, selection: $model.draftCategory) {
                        ForEach(AriaKnowledgeCategory.managedCases, id: \.self) { folder in
                            Text(folder.title).tag(folder)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel(AriaMemoryAccess.folderPickerLabel)
                }
                TextField("A short note", text: $model.draftSummary, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(12)
                    .background(Color.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(AriaMemoryAccess.noteFieldLabel)
                if let addError = model.addError {
                    Text(addError)
                        .font(.system(size: 13))
                        .foregroundColor(.danger)
                }
                Spacer()
            }
            .padding(20)
            .background(Color.background.ignoresSafeArea())
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
