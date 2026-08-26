import SwiftUI
import ForgeCore

// MARK: - HydrationCard
//
// One-tap logging on Home, plus the pace line HydrationEngine computes.
//
// The design decision worth naming: the primary tap logs a glass without a
// sheet, a picker or a confirmation. Anything more is too much ceremony for an
// act that takes two seconds and happens eight times a day — the whole reason
// this belongs on a wrist rather than a phone. Other sizes are one level down,
// for the times it was a bottle.

struct HydrationCard: View {
    @Environment(HydrationManager.self) private var hydration
    @State private var showingSizes = false

    private var glass: HydrationEngine.Preset {
        HydrationEngine.presets.first { $0.id == "glass" } ?? HydrationEngine.presets[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            header

            HapticButton(haptic: .click) {
                Task { await hydration.log(preset: glass) }
            } label: {
                Label("Log a glass", systemImage: "drop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(ForgePalette.steel.opacity(0.85))
            .accessibilityLabel("Log a glass of water")
            .accessibilityHint("Adds \(Int(glass.milliliters)) millilitres and writes it to Health.")

            Button {
                showingSizes = true
            } label: {
                Text("Something bigger…")
                    .font(.system(size: 11))
                    .foregroundStyle(ForgePalette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose a bottle size instead of a glass.")

            Text(hydration.guidance)
                .font(.system(size: 10.5))
                .foregroundStyle(ForgePalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if hydration.lastWriteFailed {
                // The drink still counted; only the write to Health did not.
                // Saying so beats a number that quietly disagrees with Health.
                Label("Saved locally — will sync to Health", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 10))
                    .foregroundStyle(ForgePalette.textTertiary)
            }
        }
        .padding(ForgeDS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.lg).fill(ForgePalette.surface))
        .sheet(isPresented: $showingSizes) { sizePicker }
    }

    private var header: some View {
        HStack(spacing: ForgeDS.Spacing.sm) {
            Gauge(value: hydration.progress) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint)
                .scaleEffect(0.55)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 0) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ForgePalette.textPrimary)
                Text(subhead)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ForgePalette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(headline). \(subhead). \(hydration.guidance)")
    }

    private var tint: Color {
        switch hydration.status {
        case .behind: return ForgePalette.textTertiary
        case .onTrack: return ForgePalette.steel
        case .met, .over: return ForgePalette.jade
        }
    }

    private var headline: String {
        let glasses = HydrationEngine.glasses(fromMilliliters: hydration.consumedMilliliters)
        return "\(Int(glasses.rounded())) of \(Int(HydrationEngine.glasses(fromMilliliters: hydration.targetMilliliters).rounded())) glasses"
    }

    private var subhead: String {
        switch hydration.status {
        case .met: return "Need covered"
        case .over: return "Past today's need"
        case .onTrack: return "On pace"
        case .behind:
            let left = hydration.remainingGlasses
            return left <= 0 ? "Almost there" : "\(left) to go"
        }
    }

    private var sizePicker: some View {
        ScrollView {
            VStack(spacing: ForgeDS.Spacing.sm) {
                ForEach(HydrationEngine.presets) { preset in
                    HapticButton(haptic: .click) {
                        Task { await hydration.log(preset: preset) }
                        showingSizes = false
                    } label: {
                        HStack {
                            Image(systemName: preset.symbolName)
                                .foregroundStyle(ForgePalette.steel)
                                .frame(width: 22)
                            Text(preset.title).font(.system(size: 13))
                            Spacer()
                            Text("\(Int(preset.milliliters)) ml")
                                .font(.system(size: 11))
                                .foregroundStyle(ForgePalette.textTertiary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Log \(preset.title), \(Int(preset.milliliters)) millilitres")
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Water")
    }
}
