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
            Text("Life Context")
                .forgeSectionLabel()
                .padding(.top, 28)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            Text("Optional, and on this iPhone. ARIA reads counts and short facts — never a reminder title, a message, or a calendar title. Mail and GitHub stay off this phone.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            SectionCard {
                remindersRow
                Divider().background(Color.borderColor)
                messagesRow
                Divider().background(Color.borderColor)
                rememberRow
                Divider().background(Color.borderColor)
                Button { showKnowledge = true } label: {
                    SettingsRow(
                        icon: "eye.fill",
                        iconColor: .steel,
                        label: "What Forge knows",
                        trailingText: messages.facts.isEmpty ? "Nothing yet" : "\(messages.facts.count)",
                        showChevron: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What Forge knows")
                .accessibilityValue(messages.facts.isEmpty ? "Nothing yet" : "\(messages.facts.count) facts")
                .accessibilityHint("Review or delete life-context facts")
                Divider().background(Color.borderColor)
                Button { confirmForget = true } label: {
                    SettingsRow(icon: "trash.fill", iconColor: .danger, label: "Forget all life-context facts")
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
                Task {
                    try? await reminders.requestAccess()
                    await reminders.ingestIfAuthorized()
                }
            } label: {
                statusText("Connect Reminders", color: .ember)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect Reminders")
            .accessibilityHint("Asks iOS for access to Reminders")
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                statusText("Reminders access is off in iOS Settings. Open Settings", color: .textSecondary)
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

    private func statusText(_ text: String, color: Color = .textTertiary) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
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
            VStack(alignment: .leading, spacing: 16) {
                Text("Forge keeps short facts it wrote itself — never your messages. ARIA reads them on this iPhone only.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !store.pendingReview.isEmpty {
                    pendingCard
                }
                briefCard
                if let workload = reminders.workload, reminders.accessState == .connected {
                    card(title: "From Reminders", accent: .steel) {
                        Text(workload.summaryLine)
                            .font(.system(size: 14))
                            .foregroundColor(.textPrimary)
                        Text("Counts only. Titles and notes are never kept.")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
                let digest = LifeOpsBoard.digest()
                if !digest.isQuiet {
                    card(title: "Life Ops", accent: .ember) {
                        Text(digest.summaryLine)
                            .font(.system(size: 14))
                            .foregroundColor(.textPrimary)
                        Text("Calendar kinds and reminder counts — never titles, mail, or GitHub. On this iPhone only.")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Life Ops: \(digest.summaryLine)")
                }
                factsCard
                #if FORGE_DUMMY_ORCHESTRA
                syntheticCard
                #endif
                if let error = store.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.danger)
                        .accessibilityLabel("Error: \(error)")
                }
            }
            .padding(20)
        }
        .background(Color.background.ignoresSafeArea())
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
            ForEach(store.pendingReview) { fact in
                factRow(fact, deletable: false)
            }
            Text(store.settings.rememberEnabled
                 ? "Remember keeps these, encrypted. Discard drops them now."
                 : "Remember life context is off, so these last only until Forge closes.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    store.rememberPending()
                } label: {
                    Text("Remember")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.ember)
                        .cornerRadius(12)
                }
                .accessibilityLabel("Remember these facts")
                Button {
                    store.discardPending()
                } label: {
                    Text("Discard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.surfaceElevated)
                        .cornerRadius(12)
                }
                .accessibilityLabel("Discard these facts")
            }
        }
    }

    @ViewBuilder
    private var briefCard: some View {
        if let brief = store.contextBrief() {
            card(title: "What ARIA reads", accent: .steel) {
                Text(brief)
                    .font(.system(size: 14))
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("On this iPhone only. Never sent to a remote model.")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var factsCard: some View {
        card(title: "From shared conversations", accent: .ember) {
            if store.facts.isEmpty {
                Text(store.settings.messagesEnabled
                     ? "Nothing yet. Share a conversation to Forge from the Share Sheet."
                     : "Messages is off in Life Context, so Forge has nothing here.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(store.facts.reversed())) { fact in
                    factRow(fact, deletable: true)
                }
            }
        }
    }

    #if FORGE_DUMMY_ORCHESTRA
    private var syntheticCard: some View {
        card(title: "Debug", accent: .steel) {
            Button {
                Task {
                    guard let key = try? store.hashKey() else { return }
                    await store.ingest(from: SyntheticMessageProvider(hashKey: key))
                }
            } label: {
                Text(store.isProcessing ? "Reading…" : "Load synthetic conversation")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(store.settings.messagesEnabled ? Color.ember : Color.textMuted)
            }
            .disabled(!store.settings.messagesEnabled || store.isProcessing)
            .accessibilityLabel("Load synthetic conversation")
            .accessibilityHint("Debug only. Runs the engine on a scripted conversation.")
        }
    }
    #endif

    // MARK: Pieces

    private func card<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(cornerRadius: 16, accent: accent)
    }

    private func factRow(_ fact: LifeContextFact, deletable: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.icon(for: fact.kind))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.ember)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(fact.summary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.detail(for: fact))
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if deletable {
                Button {
                    confirmDelete = fact
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(fact.summary)")
            }
        }
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
