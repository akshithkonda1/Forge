import SwiftUI
import UIKit
import ForgeCore

// ============================================================
// MARK: - Settings → Life Context
// ============================================================
//
// Privacy contract
// ----------------
// What ARIA sees: what these switches allow — Reminders counts while
// Reminders is on and connected, and the Life Context brief while Messages is
// on. On-device ARIA only; neither is ever sent to a remote model.
// What stays on-device: everything shown here. The viewer lists the facts
// themselves (Forge-written summaries, never message text) so the user can
// audit them, delete one, or forget all — deletion rewrites or removes the
// sealed file, it does not hide rows.

/// The Life Context section of Settings: per-source switches, the "what Forge
/// knows" viewer, and one-tap forget. Every switch defaults to off.
struct LifeContextSettingsSection: View {
    @ObservedObject private var reminders = RemindersManager.shared
    @ObservedObject private var messages = MessageContextStore.shared
    @Environment(\.openURL) private var openURL

    @State private var showKnowledge = false
    @State private var confirmForget = false
    @State private var confirmRememberOff = false
    @State private var forgetResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Same section rhythm as the other Settings groups: 24 above, 12 below.
            ForgeSectionHeader(
                title: "Life Context",
                subtitle: "Optional, and on this iPhone. ARIA reads counts and short facts — never a reminder title, a message, or a calendar title. Mail and GitHub stay off this phone."
            )
            .padding(.top, FDS.Spacing.xl)
            .padding(.bottom, FDS.Spacing.md)

            SectionCard {
                remindersRow
                LifeContextRowDivider()
                messagesRow
                LifeContextRowDivider()
                rememberRow
                LifeContextRowDivider()
                Button { showKnowledge = true } label: {
                    SettingsRow(
                        icon: "eye.fill",
                        iconColor: .steel,
                        label: "What Forge knows",
                        trailingText: messages.facts.isEmpty ? "Nothing yet" : "\(messages.facts.count)",
                        showChevron: true
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What Forge knows")
                .accessibilityValue(messages.facts.isEmpty ? "Nothing yet" : "\(messages.facts.count) facts")
                .accessibilityHint("Review or delete life-context facts")
                LifeContextRowDivider()
                Button { confirmForget = true } label: {
                    SettingsRow(icon: "trash.fill", iconColor: .danger, label: "Forget all life-context facts")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Forget all life-context facts")
                .accessibilityHint("Erases every fact, its encryption keys, and any pending shares")
                if let forgetResult {
                    statusText(forgetResult)
                        .accessibilityLabel(forgetResult)
                }
            }
        }
        .sheet(isPresented: $showKnowledge) {
            NavigationStack {
                LifeContextKnowledgeView()
            }
        }
        .confirmationDialog(
            "Forget all life-context facts?",
            isPresented: $confirmForget,
            titleVisibility: .visible
        ) {
            Button("Forget all", role: .destructive) {
                let verified = messages.forgetAll()
                forgetResult = verified
                    ? "Erased. Facts, keys and pending shares are gone from this iPhone."
                    : (messages.lastError ?? "Couldn't confirm the erase. Try again.")
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("This erases the facts, the keys that encrypt them, and anything still waiting from the Share Sheet. It can't be undone.")
        }
        .confirmationDialog(
            "Stop remembering?",
            isPresented: $confirmRememberOff,
            titleVisibility: .visible
        ) {
            Button("Turn off and erase saved copy", role: .destructive) {
                messages.setRememberEnabled(false)
            }
            Button("Keep remembering", role: .cancel) {}
        } message: {
            Text("The encrypted copy on this iPhone is deleted. What you confirmed stays only until Forge closes.")
        }
    }

    // MARK: Rows

    private var remindersRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(icon: "checklist", iconColor: .steel, label: "Reminders") {
                ForgeToggle(isOn: Binding(
                    get: { reminders.isEnabled },
                    set: { enabled in Task { await reminders.setEnabled(enabled) } }
                ))
                .accessibilityLabel("Reminders")
                .accessibilityHint("Lets ARIA count overdue and due reminders. Titles stay on this iPhone.")
            }
            remindersStatus
        }
    }

    @ViewBuilder
    private var remindersStatus: some View {
        switch reminders.accessState {
        case .off:
            statusText("Off. Forge doesn't read Reminders.")
        case .notConnected:
            Button {
                FDS.haptic(.press)
                Task {
                    try? await reminders.requestAccess()
                    await reminders.ingestIfAuthorized()
                }
            } label: {
                statusAction("Connect Reminders", color: .ember)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect Reminders")
            .accessibilityHint("Asks iOS for access to Reminders")
        case .denied:
            Button {
                FDS.haptic(.press)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                statusAction("Reminders access is off in iOS Settings. Open Settings", color: .textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reminders access is off. Open iOS Settings")
        case .connected:
            statusText(reminders.workload?.summaryLine ?? "Counting your reminders…")
                .accessibilityLabel("Reminders workload: \(reminders.workload?.summaryLine ?? "counting")")
        }
    }

    private var messagesRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(icon: "bubble.left.and.bubble.right.fill", iconColor: .ember, label: "Messages") {
                ForgeToggle(isOn: Binding(
                    get: { messages.settings.messagesEnabled },
                    set: { messages.setMessagesEnabled($0) }
                ))
                .accessibilityLabel("Messages")
                .accessibilityHint("Lets you share a conversation to Forge from the Share Sheet")
            }
            statusText(messages.settings.messagesEnabled
                ? "Share a conversation to Forge from the Share Sheet. You review what Forge found before anything is kept."
                : "Off. The Share Sheet reads nothing.")
        }
    }

    private var rememberRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(icon: "lock.fill", iconColor: .success, label: "Remember life context") {
                ForgeToggle(isOn: Binding(
                    get: { messages.settings.rememberEnabled },
                    set: { enabled in
                        if !enabled, messages.hasSavedCopy {
                            confirmRememberOff = true
                        } else {
                            messages.setRememberEnabled(enabled)
                        }
                    }
                ))
                .accessibilityLabel("Remember life context")
                .accessibilityHint("Keeps confirmed facts after Forge closes, encrypted on this iPhone")
            }
            statusText(messages.settings.rememberEnabled
                ? "On. Facts you confirm are encrypted on this iPhone — not in iCloud, not in backups."
                : "Off. Confirmed facts last until Forge closes. Nothing is written down.")
        }
    }

    /// Leading edge of a row label: row inset 16 + 32 pt icon well + 12 pt gap.
    private static let labelInset: CGFloat = 60

    /// Footnote under a toggle row, aligned to the label column.
    private func statusText(_ text: String, color: Color = .textSecondary) -> some View {
        Text(text)
            .font(HomeType.body)
            .foregroundStyle(color)
            .forgeWrapping()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Self.labelInset)
            .padding(.trailing, FDS.Spacing.lg)
            .padding(.top, -4)
            .padding(.bottom, ForgeLayout.rowGap)
    }

    /// A status that is also an action: label column, chevron, 44 pt tall.
    private func statusAction(_ text: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: ForgeLayout.rowGap) {
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(color)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.leading, Self.labelInset)
        .padding(.trailing, FDS.Spacing.lg)
        .frame(minHeight: ForgeUX.minTap)
        .contentShape(Rectangle())
    }
}

/// Inset hairline between the rows of the Life Context card, aligned to the
/// label column like the rest of Settings.
private struct LifeContextRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderHairline)
            .frame(height: ForgeUX.hairline)
            .padding(.leading, 60)
            .accessibilityHidden(true)
    }
}

// ============================================================
// MARK: - What Forge knows
// ============================================================

/// The audit view: every life-context fact, the brief ARIA reads, and a
/// review step for anything just shared.
struct LifeContextKnowledgeView: View {
    @ObservedObject private var store = MessageContextStore.shared
    @ObservedObject private var reminders = RemindersManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete: LifeContextFact?

    var body: some View {
        ScrollView {
            ForgeScreenStack(top: FDS.Spacing.lg) {
                Text("Forge keeps short facts it wrote itself — never your messages. ARIA reads them on this iPhone only.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()

                if !store.pendingReview.isEmpty {
                    pendingCard
                }
                briefCard
                remindersCard
                lifeOpsCard
                factsCard
                #if FORGE_DUMMY_ORCHESTRA
                syntheticCard
                #endif
                if let error = store.lastError {
                    Text(error)
                        .font(HomeType.body)
                        .foregroundStyle(Color.danger)
                        .forgeWrapping()
                        .accessibilityLabel("Error: \(error)")
                }
            }
        }
        .forgeScreenBackground(accent: .steel)
        .navigationTitle("What Forge knows")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .foregroundColor(.ember)
                    .accessibilityLabel("Done")
            }
        }
        .onAppear { store.drainShareInbox() }
        .confirmationDialog(
            "Delete this fact?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let fact = confirmDelete {
                    store.delete(fact)
                }
                confirmDelete = nil
            }
            Button("Keep it", role: .cancel) {
                confirmDelete = nil
            }
        } message: {
            Text("It is removed from this iPhone, including the encrypted copy.")
        }
    }

    // MARK: Cards

    private var pendingCard: some View {
        card(title: "Review: \(store.pendingSourceName ?? "Shared conversation")", accent: .ember) {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(store.pendingReview) { fact in
                    factRow(fact, deletable: false)
                }
            }
            Text(store.settings.rememberEnabled
                 ? "Remember keeps these, encrypted. Discard drops them now."
                 : "Remember life context is off, so these last only until Forge closes.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            VStack(spacing: ForgeLayout.tileGap) {
                ForgePrimaryButton(title: "Remember") {
                    store.rememberPending()
                }
                .accessibilityLabel("Remember these facts")
                ForgeSecondaryButton(title: "Discard", accent: .steel) {
                    store.discardPending()
                }
                .accessibilityLabel("Discard these facts")
            }
        }
    }

    @ViewBuilder
    private var briefCard: some View {
        if let brief = store.contextBrief() {
            card(title: "What ARIA reads", accent: .steel) {
                leadLine(brief, note: "On this iPhone only. Never sent to a remote model.")
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var remindersCard: some View {
        if let workload = reminders.workload, reminders.accessState == .connected {
            card(title: "From Reminders", accent: .steel) {
                leadLine(workload.summaryLine, note: "Counts only. Titles and notes are never kept.")
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var lifeOpsCard: some View {
        let digest = LifeOpsBoard.digest()
        if !digest.isQuiet {
            card(title: "Life Ops", accent: .ember) {
                leadLine(
                    digest.summaryLine,
                    note: "Calendar kinds and reminder counts — never titles, mail, or GitHub. On this iPhone only."
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Life Ops: \(digest.summaryLine)")
        }
    }

    private var factsCard: some View {
        card(
            title: "From shared conversations",
            accent: .ember,
            meta: store.facts.isEmpty ? nil : "\(store.facts.count)"
        ) {
            if store.facts.isEmpty {
                factsEmpty
            } else {
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(Array(store.facts.reversed())) { fact in
                        factRow(fact, deletable: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var factsEmpty: some View {
        if store.settings.messagesEnabled {
            ForgeEmptyNote(
                title: "Nothing yet",
                message: "Share a conversation to Forge from the Share Sheet.",
                systemImage: "tray"
            )
        } else {
            ForgeEmptyNote(
                title: "Messages is off in Life Context, so Forge has nothing here.",
                systemImage: "tray"
            )
        }
    }

    #if FORGE_DUMMY_ORCHESTRA
    private var syntheticCard: some View {
        card(title: "Debug", accent: .steel) {
            ForgeSecondaryButton(
                title: store.isProcessing ? "Reading…" : "Load synthetic conversation",
                accent: store.settings.messagesEnabled ? .ember : .textMuted
            ) {
                Task {
                    guard let key = try? store.hashKey() else { return }
                    await store.ingest(from: SyntheticMessageProvider(hashKey: key))
                }
            }
            .disabled(!store.settings.messagesEnabled || store.isProcessing)
            .accessibilityLabel("Load synthetic conversation")
            .accessibilityHint("Debug only. Runs the engine on a scripted conversation.")
        }
    }
    #endif

    // MARK: Pieces

    /// Standard card: eyebrow header (optional count), then the body at the
    /// block gap. The domain colour washes the card and tints the eyebrow.
    private func card<Content: View>(
        title: String,
        accent: Color,
        meta: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            cardHeader(title: title, accent: accent, meta: meta)
            content()
        }
        .forgeContentCard(tint: accent)
    }

    @ViewBuilder
    private func cardHeader(title: String, accent: Color, meta: String?) -> some View {
        if let meta {
            ForgeCardHeader(title, meta: meta, tint: accent)
        } else {
            ForgeCardHeader(title, tint: accent)
        }
    }

    /// A lead sentence over a quieter note, 4 pt apart.
    private func leadLine(_ line: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(line)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            Text(note)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    /// Agenda-row anatomy: 36 pt icon well, title over detail, trailing 44 pt
    /// delete. The row is at least 44 pt tall.
    private func factRow(_ fact: LifeContextFact, deletable: Bool) -> some View {
        HStack(alignment: .center, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: Self.icon(for: fact.kind), tint: .ember)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(fact.summary)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text(Self.detail(for: fact))
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if deletable {
                Button {
                    FDS.haptic(.press)
                    confirmDelete = fact
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(fact.summary)")
            }
        }
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
    }

    private static func icon(for kind: LifeContextFact.Kind) -> String {
        switch kind {
        case .plan: return "fork.knife"
        case .event: return "star.fill"
        case .travel: return "airplane"
        case .commitment: return "checkmark.circle"
        case .healthSignal: return "heart.text.square"
        case .stressSignal: return "waveform.path.ecg"
        case .relationship: return "person.2.fill"
        }
    }

    private static func detail(for fact: LifeContextFact) -> String {
        var parts = [fact.kind.displayName]
        if let date = fact.date {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append("\(fact.confidenceBand.rawValue.capitalized) confidence")
        return parts.joined(separator: " · ")
    }
}
