import SwiftUI

// ============================================================
// MARK: - What a supporter sees
// ============================================================

/// Renders a received `PartnerCycleDigest` through a `PartnerSupportLens`.
///
/// This view takes a **digest**, never a `MenstrualCycleSnapshot`. That is not a
/// style preference — it is the enforcement. The snapshot type carries
/// `fertileScore`, `ovulationDayInCycle`, `cycleGoal`, `twwDaysElapsed` and
/// day-level bleeding state, and a view that accepted one would put every future
/// edit one autocomplete away from rendering them. There is no initialiser here
/// that can take one.
///
/// Doubles as the owner's "preview as they'd see it" screen, driven by exactly
/// the same inputs — so the preview cannot flatter the real thing.
struct SupporterDigestView: View {
    let digest: PartnerCycleDigest
    let lens: PartnerSupportLens
    /// Who is being supported. Display only — never used to widen what is shown.
    let personName: String
    /// True when the owner is previewing their own digest.
    var isPreview: Bool = false

    @ScaledMetric(relativeTo: .title3) private var digestCircleSize: CGFloat = 62

    private var guidance: SupporterGuidance.Guidance {
        SupporterGuidance.make(digest: digest, lens: lens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            if isPreview { previewBanner }
            if digest.periodFinished { finishedBanner }
            if !isPreview && digest.isStale { staleBanner }

            ForEach(lens.sections, id: \.self) { section in
                switch section {
                case .todayAtAGlance:     glance
                case .howToShowUp:        howToShowUp
                case .intimacyAndComfort: intimacyAndComfort
                case .parentPlaybook:     parentPlaybook
                case .whatYouCannotSee:   withheld
                }
            }

            Text(PartnerSupportBrief.disclaimer)
                .font(HomeType.micro)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    // ------------------------------------------------------------

    /// One-line status banner: tinted compact card, icon plus a wrapping sentence.
    private func banner(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .forgeContentCard(tint: tint, padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .combine)
    }

    private var previewBanner: some View {
        banner(
            icon: "eye.fill",
            text: "This is exactly what they see. Nothing more.",
            tint: .vitality
        )
    }

    /// Shown when the owner's device has not published in a while.
    ///
    /// Without it, a digest that stopped updating goes on looking authoritative
    /// indefinitely — a supporter would read a phase that moved on days ago and
    /// act on it. Says what to do about it, because "this is old" with no next
    /// step just makes someone uneasy.
    private var staleBanner: some View {
        let days = digest.ageInDays
        let text = days.map { "No update in \($0) days. Their app may not have run — this could be out of date." }
            ?? "This may be out of date."
        return banner(
            icon: "exclamationmark.arrow.triangle.2.circlepath",
            text: text,
            tint: .warning
        )
    }

    private var finishedBanner: some View {
        banner(
            icon: "checkmark.circle.fill",
            text: "Period finished — both of you can see this.",
            tint: .vitality
        )
    }

    // MARK: - Hero: today at a glance

    /// The digest summary is this surface's one hero plate.
    private var glance: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.heroGap) {
            glanceHeader

            // Support card is whole-person intent — single line, 280 chars, owner-authored.
            // It travels while cramping/flow/notes stay vaulted. Prefer it when present.
            if let card = digest.supportCardLine, !card.isEmpty {
                supportCardQuote(card)
                Text(guidance.headline)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            } else {
                Text(guidance.headline)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
            }

            // A rough distance, never a date. A date invites counting down, and
            // a supporter counting down is the failure mode this avoids.
            if let days = digest.daysUntilNextPeriodApprox {
                nextPeriodRow(approximateNextPeriod(days))
            }

            // Says out loud that this is a snapshot from their device, not a
            // live feed. Nobody should think they are watching in real time.
            Text(asOfLine)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgePlate(energy: .indigo)
        .accessibilityElement(children: .contain)
    }

    private var glanceHeader: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.heroGap, alignment: .center) {
            phaseBadge
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(personName.isEmpty ? "SUPPORT" : personName.uppercased())
                    .forgeSectionLabel(tint: accent)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
                Text(digest.phase.label)
                    .font(HomeType.sessionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                glanceDetail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var phaseBadge: some View {
        let diameter = ForgeLayout.scaledCap(digestCircleSize, base: 62)
        return ZStack {
            Circle()
                .fill(accent.opacity(0.18))
            Image(systemName: phaseIcon)
                .font(.system(size: diameter * 0.39, weight: .semibold))
                .foregroundStyle(accent)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glanceDetail: some View {
        if let day = digest.periodDay {
            Text("Day \(day)")
                .font(HomeType.metric)
                .foregroundStyle(Color.textPrimary)
                .forgeSingleLine()
                .contentTransition(.numericText())
        } else if digest.phase != .notBleeding {
            Text(digest.energy.label)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    private func supportCardQuote(_ card: String) -> some View {
        HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.indigo)
                .accessibilityHidden(true)
            Text(card)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
        .accessibilityElement(children: .combine)
    }

    private func nextPeriodRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
            Image(systemName: "calendar")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            Text(text)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Guidance cards

    private var howToShowUp: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeCardHeader(PartnerSupportLens.Section.howToShowUp.title, tint: .indigo)
            if guidance.doThis.isEmpty && guidance.notThis.isEmpty {
                ForgeEmptyNote(
                    title: "Nothing specific right now",
                    message: "Being around and listening is enough.",
                    systemImage: "heart.fill",
                    tint: .indigo
                )
            }
            if !guidance.doThis.isEmpty {
                iconBulletList(guidance.doThis, tint: .indigo, icon: "checkmark.circle.fill", spokenPrefix: "Do:")
            }
            if !guidance.doThis.isEmpty && !guidance.notThis.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))
            }
            if !guidance.notThis.isEmpty {
                iconBulletList(guidance.notThis, tint: ForgeProgressChrome.miss, icon: "minus.circle.fill", spokenPrefix: "Avoid:")
            }
        }
        .forgeContentCard(tint: .indigo)
    }

    @ViewBuilder
    private var intimacyAndComfort: some View {
        // Belt and braces: the lens already excludes this section for every
        // non-romantic role, and the array is empty for them too. Two
        // independent guards, because a parent seeing this is the failure that
        // must not happen once.
        if lens.intimacy == .full, !guidance.intimacy.isEmpty {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForgeCardHeader(PartnerSupportLens.Section.intimacyAndComfort.title, tint: .aurora)
                bulletList(guidance.intimacy, tint: .aurora)
                Text("Nothing here tells you when they're fertile. That stays with them.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }
            .forgeContentCard(tint: .aurora)
        }
    }

    @ViewBuilder
    private var parentPlaybook: some View {
        if !guidance.parentNotes.isEmpty {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForgeCardHeader(PartnerSupportLens.Section.parentPlaybook.title, tint: .steel)
                bulletList(guidance.parentNotes, tint: .steel)
            }
            .forgeContentCard(tint: .steel)
        }
    }

    /// Always rendered, always last. The privacy promise is only worth something
    /// if it is legible to *both* sides — the supporter who might otherwise ask
    /// the person they support to fill in the gaps, and the owner previewing
    /// this to decide whether to share at all.
    private var withheld: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(title: PartnerSupportLens.Section.whatYouCannotSee.title) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
            Text(lens.withheldExplanation)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
        .forgeContentCard()
    }

    // ------------------------------------------------------------

    private func bulletList(_ items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            ForEach(items, id: \.self) { item in
                ForgeBulletRow(text: item, tint: tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Icon-led list for the do / don't pair, so polarity never rests on colour alone.
    private func iconBulletList(_ items: [String], tint: Color, icon: String, spokenPrefix: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.tileGap) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: FDS.Spacing.sm) {
                    Image(systemName: icon)
                        .font(HomeType.body)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(spokenPrefix) \(item)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Phase identity colour. Bleeding uses the menstruation phase red
    /// (`MenstrualPhase.menstruation.accentHex`, EF4444, the `alert` token's value);
    /// it identifies the phase and is never a status.
    private var accent: Color {
        switch digest.phase {
        case .bleeding:     return Color.alert
        case .rebuilding:   return Color.vitality
        case .winding:      return Color.aurora
        case .notBleeding:  return Color.textSecondary
        case .unknown:      return Color.textSecondary
        }
    }

    private var phaseIcon: String {
        switch digest.phase {
        case .bleeding:     return "drop.fill"
        case .rebuilding:   return "sun.max.fill"
        case .winding:      return "moon.fill"
        case .notBleeding:  return "heart.fill"
        case .unknown:      return "questionmark"
        }
    }

    private func approximateNextPeriod(_ days: Int) -> String {
        switch days {
        case ...1:  return "Next period likely within a day or so"
        case 2...3: return "Next period likely in a few days"
        case 4...7: return "Next period likely within the week"
        case 8...14: return "Next period likely in a couple of weeks"
        default:    return "Next period isn't close"
        }
    }

    private var asOfLine: String {
        guard let date = CycleDayKey.date(from: digest.asOfDayKey) else {
            return "Updated by their device."
        }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        switch days {
        case ...0: return "As of today, from their device."
        case 1:    return "As of yesterday, from their device."
        default:   return "As of \(days) days ago, from their device."
        }
    }
}
