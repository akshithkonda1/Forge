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

    private var guidance: SupporterGuidance.Guidance {
        SupporterGuidance.make(digest: digest, lens: lens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)
        }
    }

    // ------------------------------------------------------------

    private var previewBanner: some View {
        Label("This is exactly what they see. Nothing more.", systemImage: "eye.fill")
            .font(FDS.TypeScale.label(13))
            .foregroundStyle(Color(hex: "22C55E"))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "22C55E").opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Shown when the owner's device has not published in a while.
    ///
    /// Without it, a digest that stopped updating goes on looking authoritative
    /// indefinitely — a supporter would read a phase that moved on days ago and
    /// act on it. Says what to do about it, because "this is old" with no next
    /// step just makes someone uneasy.
    private var staleBanner: some View {
        let days = digest.ageInDays
        return Label(
            days.map { "No update in \($0) days. Their app may not have run — this could be out of date." }
                ?? "This may be out of date.",
            systemImage: "exclamationmark.arrow.triangle.2.circlepath"
        )
        .font(FDS.TypeScale.body(12))
        .foregroundStyle(Color(hex: "FBBF24"))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FBBF24").opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var finishedBanner: some View {
        Label("Period finished — both of you can see this.", systemImage: "checkmark.flag.fill")
            .font(FDS.TypeScale.label(13))
            .foregroundStyle(Color(hex: "22C55E"))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "22C55E").opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 62, height: 62)
                    Image(systemName: phaseIcon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(personName.isEmpty ? "SUPPORT" : personName.uppercased())
                        .font(FDS.TypeScale.micro(10))
                        .tracking(1.3)
                        .foregroundStyle(accent)
                    Text(digest.phase.label)
                        .font(FDS.TypeScale.title(20))
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(digest.energy.label)
                        .font(FDS.TypeScale.body(13))
                        .foregroundColor(.textSecondary)
                }
                Spacer(minLength: 0)
            }

            Text(guidance.headline)
                .font(FDS.TypeScale.body(15))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // A rough distance, never a date. A date invites counting down, and
            // a supporter counting down is the failure mode this avoids.
            if let days = digest.daysUntilNextPeriodApprox {
                Label(approximateNextPeriod(days), systemImage: "calendar")
                    .font(FDS.TypeScale.body(13))
                    .foregroundColor(.textSecondary)
            }

            // Says out loud that this is a snapshot from their device, not a
            // live feed. Nobody should think they are watching in real time.
            Text(asOfLine)
                .font(FDS.TypeScale.body(11))
                .foregroundColor(.textTertiary)
        }
        .padding(20)
        .forgeGlassCard(accent: accent)
    }

    private var howToShowUp: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(PartnerSupportLens.Section.howToShowUp.title.uppercased())
                .forgeSectionLabel()
            bulletList(guidance.doThis, tint: accent, icon: "checkmark.circle.fill")
            if !guidance.notThis.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))
                bulletList(guidance.notThis, tint: Color(hex: "F87171"), icon: "xmark.circle.fill")
            }
        }
        .padding(20)
        .forgeGlassCard(accent: accent)
    }

    @ViewBuilder
    private var intimacyAndComfort: some View {
        // Belt and braces: the lens already excludes this section for every
        // non-romantic role, and the array is empty for them too. Two
        // independent guards, because a parent seeing this is the failure that
        // must not happen once.
        if lens.intimacy == .full, !guidance.intimacy.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(PartnerSupportLens.Section.intimacyAndComfort.title.uppercased())
                    .forgeSectionLabel()
                bulletList(guidance.intimacy, tint: Color(hex: "F472B6"), icon: "heart.fill")
                Text("Nothing here tells you when they're fertile. That stays with them.")
                    .font(FDS.TypeScale.body(11))
                    .foregroundColor(.textTertiary)
            }
            .padding(20)
            .forgeGlassCard(accent: Color(hex: "F472B6"))
        }
    }

    @ViewBuilder
    private var parentPlaybook: some View {
        if !guidance.parentNotes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(PartnerSupportLens.Section.parentPlaybook.title.uppercased())
                    .forgeSectionLabel()
                bulletList(guidance.parentNotes, tint: Color(hex: "60A5FA"), icon: "hand.raised.fill")
            }
            .padding(20)
            .forgeGlassCard(accent: Color(hex: "60A5FA"))
        }
    }

    /// Always rendered, always last. The privacy promise is only worth something
    /// if it is legible to *both* sides — the supporter who might otherwise ask
    /// the person they support to fill in the gaps, and the owner previewing
    /// this to decide whether to share at all.
    private var withheld: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(PartnerSupportLens.Section.whatYouCannotSee.title.uppercased(),
                  systemImage: "eye.slash.fill")
                .forgeSectionLabel()
            Text(lens.withheldExplanation)
                .font(FDS.TypeScale.body(13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // ------------------------------------------------------------

    private func bulletList(_ items: [String], tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(tint)
                        .padding(.top, 1)
                    Text(item)
                        .font(FDS.TypeScale.body(14))
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accent: Color {
        switch digest.phase {
        case .bleeding:   return Color(hex: "F43F5E")
        case .rebuilding: return Color(hex: "22C55E")
        case .winding:    return Color(hex: "A78BFA")
        case .unknown:    return Color(hex: "94A3B8")
        }
    }

    private var phaseIcon: String {
        switch digest.phase {
        case .bleeding:   return "drop.fill"
        case .rebuilding: return "sun.max.fill"
        case .winding:    return "moon.fill"
        case .unknown:    return "questionmark"
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
