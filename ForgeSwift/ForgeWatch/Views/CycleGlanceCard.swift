import SwiftUI
import ForgeCore

// MARK: - CycleGlanceCard
//
// A read-only glance at the cycle phase the iPhone already syncs into the
// shared snapshot. The fields have been in WatchSnapshot the whole time,
// written by MenstrualHealthStore.recompute(), and nothing on the watch read
// them.
//
// Deliberately read-only, and deliberately not on the default Home scroll for
// anyone without cycle data. This is the most sensitive category Forge holds:
// a wrist is glanced at by other people, and the iOS app has a whole redaction
// boundary around what a supporter may see. Adding *logging* here would mean
// reproducing that boundary on the watch, which is its own change with its own
// review — not something to slip into a batch of features.
//
// So: it shows a phase and a day count when the phone has synced them, and
// nothing at all otherwise.

struct CycleGlanceCard: View {
    let snapshot: WatchSnapshot?

    private var phase: String? {
        guard let phase = snapshot?.cyclePhase, !phase.isEmpty else { return nil }
        return phase.prefix(1).uppercased() + phase.dropFirst()
    }

    var body: some View {
        if let phase {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: ForgeDS.Spacing.sm) {
                    Image(systemName: "circle.hexagonpath.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ForgePalette.violet)
                    Text(phase)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(ForgePalette.textPrimary)
                    Spacer(minLength: 0)
                    if let day = snapshot?.cycleDayInCycle {
                        Text("Day \(day)")
                            .font(.system(size: 11))
                            .foregroundStyle(ForgePalette.textSecondary)
                    }
                }
                if let line = supportingLine {
                    Text(line)
                        .font(.system(size: 10.5))
                        .foregroundStyle(ForgePalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(ForgeDS.Spacing.md)
            .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.lg).fill(ForgePalette.surface))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    /// Days-until framed as information, never as a countdown to dread, and
    /// only when the estimate is close enough to be worth stating. Forge's
    /// estimate is an estimate; saying "18 days" implies a precision it does
    /// not have.
    private var supportingLine: String? {
        guard let days = snapshot?.cycleNextPeriodDaysAway, days >= 0, days <= 7 else { return nil }
        switch days {
        case 0: return "Period may start today, by Forge's estimate."
        case 1: return "Period estimated tomorrow."
        default: return "Period estimated in about \(days) days."
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let phase { parts.append("Cycle phase \(phase)") }
        if let day = snapshot?.cycleDayInCycle { parts.append("day \(day)") }
        if let line = supportingLine { parts.append(line) }
        return parts.joined(separator: ", ")
    }
}
