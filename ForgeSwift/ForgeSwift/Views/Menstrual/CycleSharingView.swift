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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var role: CycleSupportRole = .romantic
    @State private var displayName = ""
    @State private var isMinting = false
    @State private var showPreview = false
    @State private var confirmRevoke = false
    @State private var showInviteRules = false
    /// Non-nil while confirming removal of one specific supporter.
    @State private var revokeTarget: PartnerCycleSharing.ShareHandle?

    private var digest: PartnerCycleDigest { cycleStore.supporterDigest }
    private var lens: PartnerSupportLens {
        PartnerSupportLens(role: role, supporterSex: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ForgeScreenStack(top: FDS.Spacing.lg) {
                    if let invite = sharing.currentInvite {
                        activeCard(invite)
                    } else {
                        intro
                        rolePicker
                        tierPicker
                        nameField
                        createButton
                    }
                    previewCard
                    if let error = sharing.lastPublishError {
                        errorBanner(error)
                    }
                }
            }
            .forgeScreenBackground(accent: .indigo)
            .navigationTitle("Invite to support me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
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
                await sharing.refreshParticipants()
                if sharing.currentInvite != nil {
                    sharing.stageSupportUpdateForMessages()
                    sharing.publishSupportSurfaces()
                }
                _ = await sharing.fetchSharedDigest()
            }
        }
    }

    // ------------------------------------------------------------
    // MARK: Set up
    // ------------------------------------------------------------

    private var intro: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                ForgeIconWell(systemImage: "person.2.badge.key.fill", tint: .indigo, diameter: 44)
                Text("Invite someone to support me")
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Send them a short iMessage from Forge in Messages. They must have an iPhone.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                if showInviteRules {
                    Text("SMS, email, and a pasted link are not valid access — the invite never includes a redeemable URL outside iMessage.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                        .transition(AnyTransition.opacity)
                }
            }

            Text("They see how to help. They never see your log. If they use Forge, a Watch glance and a morning reminder stay lock-safe. You can stop at any time.")
                .font(HomeType.body)
                .foregroundStyle(Color.vitality)
                .forgeWrapping()

            ForgeTextLink(title: "How invites work", accent: .indigo, expanded: showInviteRules) {
                withAnimation(reduceMotion ? nil : FDS.Spring.standard) {
                    showInviteRules.toggle()
                }
            }
        }
        .forgeContentCard(tint: .indigo)
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("WHO ARE THEY TO YOU")
            // The role decides whether intimate-health material appears at all,
            // so it is a privacy control wearing a personalisation hat. Asked
            // plainly rather than inferred from a free-text label.
            VStack(spacing: ForgeLayout.tileGap) {
                ForEach(CycleSupportRole.selectableRoles) { option in
                    SharingOptionRow(
                        icon: option.icon,
                        title: option.label,
                        detail: option.pickerDetail,
                        selected: role == option
                    ) {
                        role = option
                    }
                }
            }
            if role == .romantic {
                Text("Partners also see comfort and intimacy notes. Fertility timing stays off unless you pick Timing. iPhone + iMessage required.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
        }
        .forgeContentCard(tint: .indigo)
    }

    private var tierPicker: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("HOW MUCH THEY SEE")
            VStack(spacing: ForgeLayout.tileGap) {
                ForEach(PartnerShareTier.allCases) { option in
                    SharingOptionRow(
                        icon: tierIcon(option),
                        title: option.label,
                        detail: option.detail,
                        selected: cycleStore.settings.partnerShareTier == option,
                        recommended: option.isRecommended
                    ) {
                        cycleStore.updateSettings { $0.partnerShareTier = option }
                    }
                }
            }
        }
        .forgeContentCard(tint: .indigo)
    }

    private func tierIcon(_ option: PartnerShareTier) -> String {
        switch option {
        case .supportCoach: return "heart.text.square.fill"
        case .onPeriod: return "drop.fill"
        case .timing: return "calendar"
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader("HOW THEY'LL SEE YOUR NAME")
            TextField("First name", text: $displayName)
                .textFieldStyle(.plain)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .frame(minHeight: ForgeUX.minTap)
                .forgeWell()
            // A first name is enough, and an iMessage bubble is read on lock
            // screens by people who were not the intended audience.
            Text("A first name is plenty. This shows in the message they receive.")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
        .forgeContentCard(tint: .indigo)
    }

    private var createButton: some View {
        let unavailable = resolvedName.isEmpty || isMinting
        return ForgePrimaryButton(
            title: isMinting ? "Creating…" : "Create iMessage invite",
            icon: "link.badge.plus"
        ) {
            Task { await createInvite() }
        }
        .disabled(unavailable)
        .opacity(unavailable ? 0.45 : 1)
    }

    // ------------------------------------------------------------
    // MARK: Already sharing
    // ------------------------------------------------------------

    private func activeCard(_ invite: PartnerCycleInvite) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            statusBlock(invite)

            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                participantList

                pauseControl

                if let updated = sharing.lastPublishedAt, !sharing.isPaused {
                    // Tells the owner their device is actually keeping the shared
                    // copy current, which is otherwise invisible.
                    Label("Their view last updated \(updated.formatted(.relative(presentation: .named)))",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
            }

            messagesInstruction

            stopSharingButton
        }
        .forgeContentCard(tint: .indigo)
    }

    /// Headline reflects whether anyone has actually accepted, not merely
    /// that an invite exists locally. "Sharing is on" while nobody has
    /// taken it up is the kind of reassurance that is worse than silence.
    private func statusBlock(_ invite: PartnerCycleInvite) -> some View {
        let accepted = acceptedCount > 0
        let tint = accepted ? Color.vitality : Color.steel
        return HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(
                systemImage: accepted ? "checkmark.seal.fill" : "clock.badge.questionmark",
                tint: tint
            )
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(accepted ? "Sharing is on" : "Invite sent, not accepted yet")
                    .font(HomeType.status)
                    .foregroundStyle(tint)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)
                Text("Invited as \(invite.role.shortLabel.lowercased()), from “\(invite.fromDisplayName)”.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
    }

    /// The extension only holds an invite for 30 minutes. iMessage on
    /// iPhone is the only valid send path — ShareLink/SMS is withheld
    /// because a CloudKit URL in a green bubble is redeemable access.
    /// Instructions, not a button: nothing here is tappable.
    private var messagesInstruction: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: "message.fill", tint: .indigo)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text("Ready for iMessage")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                Text("Open Messages, tap the app drawer, choose Forge, and send. SMS is not valid access.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .combine)
    }

    private var stopSharingButton: some View {
        ForgeSecondaryButton(title: "Stop sharing", icon: "hand.raised.fill", accent: .danger) {
            confirmRevoke = true
        }
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

    /// Who actually holds this share, straight from CloudKit's participant list.
    ///
    /// The owner's own row is filtered out — CloudKit always includes it, and
    /// "stop sharing with yourself" is not a thing anyone needs offered.
    @ViewBuilder
    private var participantList: some View {
        let others = sharing.activeShares.filter { !$0.isOwner }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                Text("WHO CAN SEE IT")
                    .forgeSectionLabel()
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    ForEach(others) { person in
                        participantRow(person)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeWell()
        }
    }

    private func participantRow(_ person: PartnerCycleSharing.ShareHandle) -> some View {
        let accepted = person.status == .accepted
        return HStack(spacing: ForgeLayout.rowGap) {
            ForgeIconWell(
                systemImage: accepted ? "person.fill.checkmark" : "person.fill.questionmark",
                tint: accepted ? Color.vitality : Color.steel
            )
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(person.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(person.status.caption)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
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
                    FDS.haptic(.press)
                    revokeTarget = person
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.title3)
                        .foregroundStyle(Color.danger)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop sharing with \(person.name)")
            }
        }
        .frame(minHeight: ForgeUX.minTap)
    }

    /// Pause is the quiet alternative to revoking.
    ///
    /// Revoking is a social act — the other person notices, and coming back
    /// means asking again. Offering only the loud option means someone who wants
    /// a few days of privacy either takes it, or takes nothing and shares a week
    /// they did not want to.
    private var pauseControl: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Toggle(isOn: Binding(
                get: { sharing.isPaused },
                set: { paused in Task { await sharing.setPaused(paused) } }
            )) {
                Label(sharing.isPaused ? "Updates paused" : "Pause updates",
                      systemImage: sharing.isPaused ? "pause.circle.fill" : "pause.circle")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.indigo)
            .frame(minHeight: ForgeUX.minTap)

            Text(sharing.isPaused
                 // States exactly what the other side sees, so nobody has to
                 // guess whether pausing looks like an accusation.
                 ? "They see “No recent data” — not that you paused. Resume any time."
                 : "Stops sending updates without ending the share. They keep access; there's just nothing new to see.")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private var acceptedCount: Int {
        sharing.activeShares.filter { !$0.isOwner && $0.status == .accepted }.count
    }

    // ------------------------------------------------------------
    // MARK: Preview
    // ------------------------------------------------------------

    private var previewCard: some View {
        Button {
            FDS.haptic(.press)
            showPreview = true
        } label: {
            ForgeListRow(
                icon: "eye.fill",
                iconColor: .indigo,
                title: "Preview what they'd see",
                subtitle: "The same screen they get, from the same data",
                showChevron: true
            )
            .forgeContentCard(tint: .indigo)
        }
        .buttonStyle(ForgePressStyle())
    }

    private func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(HomeType.body)
            .foregroundStyle(Color.danger)
            .forgeWrapping()
            .forgeContentCard(tint: .danger, padding: ForgeLayout.compactCardPadding)
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
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .forgeScreenBackground(accent: .indigo)
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
        sharing.stageSupportUpdateForMessages()
        sharing.publishSupportSurfaces()
    }
}

// ============================================================
// MARK: - Option row
// ============================================================

/// A single-select option: agenda-row anatomy (36 pt icon well, status title,
/// body detail) on a tinted well, with a checkmark and the `.isSelected`
/// trait when chosen. Indigo, because every choice here is about a supporter.
private struct SharingOptionRow: View {
    let icon: String
    let title: String
    let detail: String
    let selected: Bool
    var recommended: Bool = false
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ForgeLayout.innerRadius, style: .continuous)
    }

    private var fill: Color {
        selected ? Color.indigo.opacity(0.14) : Color.white.opacity(0.045)
    }

    private var stroke: Color {
        selected ? Color.indigo.opacity(0.32) : Color.white.opacity(0.08)
    }

    var body: some View {
        Button {
            FDS.haptic(.select)
            action()
        } label: {
            rowContent
                .padding(ForgeLayout.tilePadding)
                .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
                .background(shape.fill(fill))
                .overlay(shape.stroke(stroke, lineWidth: ForgeUX.stroke))
                .contentShape(shape)
        }
        .buttonStyle(ForgePressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            ForgeIconWell(systemImage: icon, tint: selected ? Color.indigo : Color.textTertiary)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeAdaptiveStack(spacing: FDS.Spacing.sm) {
                    Text(title)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if recommended {
                        HudVibeChip(label: "Recommended", energy: Color.indigo)
                    }
                }
                Text(detail)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.leading)
                    .forgeWrapping()
            }
            .layoutPriority(1)
            Spacer(minLength: FDS.Spacing.xs)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.indigo)
                    .accessibilityHidden(true)
            }
        }
    }
}
