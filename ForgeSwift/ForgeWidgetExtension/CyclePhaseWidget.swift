import WidgetKit
import SwiftUI
import ForgeCore

// MARK: - CyclePhaseWidget
//
// Lockscreen widget (accessoryCircular + accessoryRectangular) showing the
// user's current cycle phase and day. Data comes from the shared App Group
// WatchSnapshot — same path as Watch complications, updated every recompute().

struct CyclePhaseEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
}

struct CyclePhaseProvider: TimelineProvider {
    func placeholder(in context: Context) -> CyclePhaseEntry {
        CyclePhaseEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CyclePhaseEntry) -> Void) {
        completion(CyclePhaseEntry(date: Date(), snapshot: WatchSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CyclePhaseEntry>) -> Void) {
        let entry = CyclePhaseEntry(date: Date(), snapshot: WatchSnapshotStore.load())
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct CyclePhaseWidgetView: View {
    let entry: CyclePhaseEntry
    @Environment(\.widgetFamily) var family

    private var mode: CycleDiscretionMode {
        CycleDiscretionMode(rawValue: entry.snapshot?.cycleDiscretion ?? "") ?? .clinical
    }

    private var phaseIcon: String {
        switch entry.snapshot?.cyclePhase {
        case "menstruation":  return "drop.fill"
        case "follicular":    return "leaf.fill"
        case "fertileWindow": return "waveform.path.ecg"
        case "ovulation":     return "sparkles"
        case "luteal":        return "moon.fill"
        default:              return "circle.dashed"
        }
    }

    private var phaseLabel: String {
        switch entry.snapshot?.cyclePhase {
        case "menstruation":  return "Period"
        case "follicular":    return "Follicular"
        case "fertileWindow": return "Fertile"
        case "ovulation":     return "Ovulation"
        case "luteal":        return "Luteal"
        default:              return "—"
        }
    }

    var body: some View {
        switch mode {
        case .stealth:
            stealth
        case .kind:
            kind
        case .clinical:
            clinical
        }
    }

    private var stealth: some View {
        Image(systemName: "lock.fill")
            .foregroundStyle(.secondary)
            .accessibilityLabel("Cycle Health is hidden")
    }

    private var kind: some View {
        let line = entry.snapshot?.cycleLockSafeLine ?? "Take it easy"
        return Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                    Text("Easy")
                        .font(.caption2)
                }
            case .accessoryRectangular:
                Label(line, systemImage: "heart.fill")
                    .font(.caption)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Text("CYCLE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                    Text(line)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
        .accessibilityLabel(line)
    }

    @ViewBuilder
    private var clinical: some View {
        if let snap = entry.snapshot, snap.cyclePhase != nil {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: phaseIcon)
                        .font(.title3)
                        .foregroundStyle(Color.orange)
                    if let day = snap.cycleDayInCycle {
                        Text("Day \(day)")
                            .font(.caption2)
                    }
                }
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Image(systemName: phaseIcon)
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(phaseLabel)
                            .font(.caption).fontWeight(.semibold)
                        if let day = snap.cycleDayInCycle {
                            Text("Day \(day)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Text("CYCLE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Color.orange)
                        Spacer()
                    }
                    Image(systemName: phaseIcon)
                        .font(.title2)
                        .foregroundStyle(Color.orange)
                    Text(phaseLabel)
                        .font(.headline)
                    if let day = snap.cycleDayInCycle {
                        Text("Day \(day)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }
}

struct CyclePhaseWidget: Widget {
    let kind = "CyclePhaseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CyclePhaseProvider()) { entry in
            CyclePhaseWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(ForgeWidgetLink.cycle)
        }
        .configurationDisplayName("Cycle Phase")
        .description("Cycle glance. Discretion Mode in Settings controls whether phase is visible.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
