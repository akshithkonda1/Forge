import SwiftUI
import WatchKit
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
    @State private var crownIndex: Double = 0
    @FocusState private var crownFocused: Bool
    @State private var quickAddedFlash = false

    private var presets: [HydrationEngine.Preset] { HydrationEngine.presets }
    private var crownPreset: HydrationEngine.Preset {
        let clamped = min(max(0, Int(crownIndex.rounded())), max(0, presets.count - 1))
        return presets[clamped]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeDS.Spacing.sm) {
            header

            // Crown-scrubbable primary action — rotate to pick size, tap to log.
            VStack(spacing: 6) {
                HapticButton(haptic: .click) {
                    Task { await hydration.log(preset: crownPreset) }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        quickAddedFlash = true
                    }
                    WKInterfaceDevice.current().play(.success)
                    Task {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        quickAddedFlash = false
                    }
                } label: {
                    Label("Log \(crownPreset.title.lowercased())", systemImage: crownPreset.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .contentTransition(.identity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ForgePalette.steel.opacity(quickAddedFlash ? 1 : 0.85))
                .scaleEffect(quickAddedFlash ? 1.02 : 1)
                .accessibilityLabel("Log \(crownPreset.title), \(Int(crownPreset.milliliters)) millilitres")
                .accessibilityHint("Turn the Digital Crown to pick size, tap to log. Current: \(crownPreset.title).")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: crownIndex = min(Double(presets.count - 1), crownIndex + 1)
                    case .decrement: crownIndex = max(0, crownIndex - 1)
                    @unknown default: break
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "digitalcrown.horizontal.arrow.counterclockwise.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(ForgePalette.textTertiary.opacity(crownFocused ? 1 : 0.45))
                    Text(crownPreset.title)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(ForgePalette.textTertiary)
                        .contentTransition(.numericText())
                    Text("· \(Int(crownPreset.milliliters)) ml")
                        .font(.system(size: 10))
                        .foregroundStyle(ForgePalette.textTertiary.opacity(0.8))
                    Spacer(minLength: 0)
                    Button { showingSizes = true } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(ForgePalette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More sizes")
                }
                .animation(.easeInOut(duration: 0.2), value: crownPreset.id)
            }
            .focusable(true)
            .focused($crownFocused)
            .digitalCrownRotation(
                $crownIndex,
                from: 0,
                through: Double(max(0, presets.count - 1)),
                by: 1,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onAppear { crownFocused = true }

            Text(hydration.guidance)
                .font(.system(size: 10.5))
                .foregroundStyle(ForgePalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let last = hydration.lastLoggedAt {
                Label("Logged \(last.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(ForgePalette.textTertiary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: hydration.lastLoggedAt)
            }

            if hydration.lastWriteFailed {
                Label("Saved locally — will sync to Health", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 10))
                    .foregroundStyle(ForgePalette.textTertiary)
            }
        }
        .padding(ForgeDS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: ForgeDS.Radius.lg).fill(ForgePalette.surface))
        .sheet(isPresented: $showingSizes) { sizePicker }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: crownIndex)
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
