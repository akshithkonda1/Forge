import SwiftUI

// ============================================================
// MARK: - Sharing your cycle with someone
// ============================================================

/// Where the owner decides who sees a digest of their cycle, and stops it.
///
/// This is the screen the Messages extension cannot be: minting a share is a
/// consent decision, so it happens here, at full size, next to a preview of
/// exactly what the other person will see. The extension can only carry an
/// invite this screen already created.
///
/// The preview is not decoration. A promise that "they only see a general
/// picture" is unverifiable prose until you can look at it, and `SupporterDigestView`
/// renders the preview from the same digest the supporter receives — so the
/// preview cannot be kinder than the truth.
struct CycleSharingView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var cycleStore: MenstrualHealthStore
    @ObservedObject private var sharing = PartnerCycleSharing.shared
    @Environment(\.dismiss) private var dismiss

    @State private var role: CycleSupportRole = .romantic
    @State private var displayName = ""
    @State private var isMinting = false
    @State private var showPreview = false
    @State private var confirmRevoke = false
    /// Non-nil while confirming removal of one specific supporter.
    @State private var revokeTarget: PartnerCycleSharing.ShareHandle?

    private var digest: PartnerCycleDigest { cycleStore.supporterDigest }
    private var lens: PartnerSupportLens {
        PartnerSupportLens(role: role, supporterSex: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let invite = sharing.currentInvite {
                        activeCard(invite)
                    } else {
                        intro
                        rolePicker
                        nameField
                        createButton
                    }
                    previewCard
                    if let error = sharing.lastPublishError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(FDS.TypeScale.body(12))
                            .foregroundStyle(Color(hex: "F87171"))
                    }
                }
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Share support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPreview) {
                previewSheet
            }
            .confirmationDialog(
                revokeTarget.map { "Stop sharing with \($0.name)?" } ?? "Stop sharing?",
                isPresented: Binding(get: { revokeTarget != nil },
                                     set: { if !$0 { revokeTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("Stop sharing", role: .destructive) {
                    guard let target = revokeTarget else { return }
                    revokeTarget = nil
                    Task { await sharing.revoke(participantID: target.id) }
                }
                Button("Keep sharing", role: .cancel) { revokeTarget = nil }
            } message: {
                Text("They stop receiving updates. Anyone else you've invited is unaffected.")
            }
            .task {
                // Participants are fetched, never assumed. The local invite says
                // only that this device created a share — it cannot know whether
                // anyone accepted, or whether they have since been removed on
                // another device.
                await sharing.refreshParticipants()
            }
        }
    }

    // ------------------------------------------------------------
    // MARK: Set up
    // ------------------------------------------------------------

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "person.2.badge.key.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.ember)
            Text("Let someone support you")
                .font(FDS.TypeScale.title(22))
                .foregroundColor(.textPrimary)
            Text("They'll see a general picture — roughly where you are, whether your energy is low or high, and one line on how to show up. Not your logs.")
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Named up front, not buried at the bottom. Someone deciding whether
            // to share should know the exit exists before they walk in.
            Text("You can stop at any time, and they simply stop seeing updates.")
                .font(FDS.TypeScale.body(12))
                .foregroundStyle(Color(hex: "22C55E"))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(accent: .ember)
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHO ARE THEY TO YOU")
                .forgeSectionLabel()
            // The role decides whether intimate-health material appears at all,
            // so it is a privacy control wearing a personalisation hat. Asked
            // plainly rather than inferred from a free-text label.
            ForEach(CycleSupportRole.allCases) { option in
                Button {
                    role = option
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.icon)
                            .frame(width: 22)
                        Text(option.label)
                            .font(FDS.TypeScale.body(15))
                        Spacer()
                        if role == option {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.ember)
                        }
                    }
                    .foregroundColor(role == option ? .textPrimary : .textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(role == option ? Color.ember.opacity(0.12) : Color.surfaceElevated)
                    )
                }
                .buttonStyle(.plain)
            }
            if role == .romantic {
                Text("Partners also see comfort and intimacy notes. No fertility timing, for anyone.")
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW THEY'LL SEE YOUR NAME")
                .forgeSectionLabel()
            TextField("First name", text: $displayName)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.textPrimary)
            // A first name is enough, and an iMessage bubble is read on lock
            // screens by people who were not the intended audience.
            Text("A first name is plenty. This shows in the message they receive.")
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)
        }
    }

    private var createButton: some View {
        Button {
            Task { await createInvite() }
        } label: {
            HStack {
                if isMinting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "link.badge.plus")
                }
                Text(isMinting ? "Creating…" : "Create invite")
            }
            .font(FDS.TypeScale.label(15))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(resolvedName.isEmpty ? Color.gray.opacity(0.4) : Color.ember)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(resolvedName.isEmpty || isMinting)
    }

    // ------------------------------------------------------------
    // MARK: Already sharing
    // ------------------------------------------------------------

    private func activeCard(_ invite: PartnerCycleInvite) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Headline reflects whether anyone has actually accepted, not merely
            // that an invite exists locally. "Sharing is on" while nobody has
            // taken it up is the kind of reassurance that is worse than silence.
            Label(acceptedCount > 0 ? "Sharing is on" : "Invite sent, not accepted yet",
                  systemImage: acceptedCount > 0 ? "checkmark.seal.fill" : "clock.badge.questionmark")
                .font(FDS.TypeScale.label(15))
                .foregroundStyle(acceptedCount > 0 ? Color(hex: "22C55E") : Color(hex: "FBBF24"))

            Text("Invited as \(invite.role.shortLabel.lowercased()), from “\(invite.fromDisplayName)”.")
                .font(FDS.TypeScale.body(14))
                .foregroundColor(.textSecondary)

            participantList

            pauseControl

            if let updated = sharing.lastPublishedAt, !sharing.isPaused {
                // Tells the owner their device is actually keeping the shared
                // copy current, which is otherwise invisible.
                Label("Their view last updated \(updated.formatted(.relative(presentation: .named)))",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textTertiary)
            }

            // The extension only holds an invite for 30 minutes, so send it now
            // or come back. Said plainly rather than letting the button quietly
            // stop working.
            ShareLink(item: invite.shareURL, message: Text(invite.fallbackMessageBody)) {
                Label(acceptedCount > 0 ? "Invite someone else" : "Send the invite",
                      systemImage: "square.and.arrow.up")
                    .font(FDS.TypeScale.label(15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.ember)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("You can also open the Forge app inside Messages and send it there.")
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)

            Button(role: .destructive) {
                confirmRevoke = true
            } label: {
                Label("Stop sharing", systemImage: "hand.raised.fill")
                    .font(FDS.TypeScale.label(14))
                    .foregroundStyle(Color(hex: "F87171"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(hex: "F87171").opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Stop sharing?", isPresented: $confirmRevoke, titleVisibility: .visible) {
                Button("Stop sharing", role: .destructive) {
                    Task { await sharing.revokeAll() }
                }
                Button("Keep sharing", role: .cancel) {}
            } message: {
                // Says what revoking actually does, including the part people
                // most want to know: the copy on their device stops refreshing.
                Text("They stop receiving updates immediately, and the copy on their device has nothing left to refresh from.")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeGlassCard(accent: acceptedCount > 0 ? Color(hex: "22C55E") : Color(hex: "FBBF24"))
    }

    /// Who actually holds this share, straight from CloudKit's participant list.
    ///
    /// The owner's own row is filtered out — CloudKit always includes it, and
    /// "stop sharing with yourself" is not a thing anyone needs offered.
    @ViewBuilder
    private var participantList: some View {
        let others = sharing.activeShares.filter { !$0.isOwner }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("WHO CAN SEE IT")
                    .forgeSectionLabel()
                ForEach(others) { person in
                    HStack(spacing: 10) {
                        Image(systemName: person.status == .accepted
                              ? "person.fill.checkmark" : "person.fill.questionmark")
                            .font(.system(size: 13))
                            .foregroundStyle(person.status == .accepted
                                             ? Color(hex: "22C55E") : .textTertiary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name)
                                .font(FDS.TypeScale.body(14))
                                .foregroundColor(.textPrimary)
                            Text(person.status.caption)
                                .font(FDS.TypeScale.body(11))
                                .foregroundColor(.textTertiary)
                        }
                        Spacer(minLength: 0)
                        // Per-person, because removing your partner should not
                        // also cut off your sister. `revokeAll` deletes the zone
                        // and is the right tool only for stopping entirely.
                        //
                        // Hidden rather than disabled when CloudKit gave us no
                        // stable identity for them: a button that cannot work is
                        // worse than no button, and "Stop sharing" is not a
                        // control to leave looking broken.
                        if !person.id.isEmpty {
                            Button {
                                revokeTarget = person
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Color(hex: "F87171"))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop sharing with \(person.name)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.surfaceElevated)
            )
        }
    }

    /// Pause is the quiet alternative to revoking.
    ///
    /// Revoking is a social act — the other person notices, and coming back
    /// means asking again. Offering only the loud option means someone who wants
    /// a few days of privacy either takes it, or takes nothing and shares a week
    /// they did not want to.
    private var pauseControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { sharing.isPaused },
                set: { paused in Task { await sharing.setPaused(paused) } }
            )) {
                Label(sharing.isPaused ? "Updates paused" : "Pause updates",
                      systemImage: sharing.isPaused ? "pause.circle.fill" : "pause.circle")
                    .font(FDS.TypeScale.label(14))
                    .foregroundColor(.textPrimary)
            }
            .tint(Color.ember)

            Text(sharing.isPaused
                 // States exactly what the other side sees, so nobody has to
                 // guess whether pausing looks like an accusation.
                 ? "They see “No recent data” — not that you paused. Resume any time."
                 : "Stops sending updates without ending the share. They keep access; there's just nothing new to see.")
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.surfaceElevated)
        )
    }

    private var acceptedCount: Int {
        sharing.activeShares.filter { !$0.isOwner && $0.status == .accepted }.count
    }

    // ------------------------------------------------------------
    // MARK: Preview
    // ------------------------------------------------------------

    private var previewCard: some View {
        Button {
            showPreview = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "eye.fill")
                    .foregroundStyle(Color.ember)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview what they'd see")
                        .font(FDS.TypeScale.label(15))
                        .foregroundColor(.textPrimary)
                    Text("The same screen they get, from the same data")
                        .font(FDS.TypeScale.body(12))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.textTertiary)
            }
            .padding(16)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var previewSheet: some View {
        NavigationStack {
            ScrollView {
                SupporterDigestView(
                    digest: digest,
                    lens: lens,
                    personName: resolvedName,
                    isPreview: true
                )
                .padding(20)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationTitle("Their view")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { showPreview = false }
                }
            }
        }
    }

    // ------------------------------------------------------------

    private var resolvedName: String {
        let typed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return store.userProfile.name.split(separator: " ").first.map(String.init) ?? ""
    }

    private func createInvite() async {
        isMinting = true
        defer { isMinting = false }
        // The digest is published as part of minting, so a supporter who accepts
        // immediately has something to read rather than an empty zone.
        _ = try? await sharing.makeInvite(
            role: role,
            fromDisplayName: resolvedName,
            digest: digest
        )
    }
}
