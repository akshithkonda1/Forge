import SwiftUI
import ForgeCore

/// Event-only close-the-day moment. Tesserae light once; there is no looping
/// confetti, glass banner, or decorative clock. Reduce Motion is a still card.
struct CelebrationOverlay: View {
    let key: Int
    let onDismiss: () -> Void
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// No decorative clock — a win is a haptic plus a hairline pulse.
    static let tickHz: Double = 0
    static let tickInterval: Double = 1

    static func isClockPaused(
        reduceMotion: Bool,
        sceneActive: Bool,
        onscreen: Bool
    ) -> Bool {
        true
    }

    static let title = "That's who you are"
    static let line = "Five tesserae lit. The day closed."

    var body: some View {
        ZStack {
            Color.background.opacity(revealed ? 0.72 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                ForgeMosaicStrip(
                    lit: Array(repeating: true, count: ForgeMosaicTracks.count),
                    energy: .ember
                )
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(Self.title)
                        .font(ForgeType.pageTitle)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(Self.line)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .forgeContentCard()
            .padding(.horizontal, ForgeLayout.screenInset)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.96)
            .opacity(revealed || reduceMotion ? 1 : 0)
        }
        .id(key)
        .onAppear {
            ForgeHaptics.play(.success)
            if reduceMotion {
                revealed = true
            } else {
                withForgeMotion(ForgeMotion.gentle) { revealed = true }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 1_600 : 2_400))
                onDismiss()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.title). \(Self.line)")
    }
}

struct VoiceQuickLaunchOrb: View {
    @EnvironmentObject var store: AppStore
    @State private var pressed = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            store.openChat(with: "Voice check-in — what should I do next?", voice: true)
        } label: {
            ZStack {
                // Flat accent button — no pulsing halos.
                Circle()
                    .fill(Color.ember)
                    .frame(width: 44, height: 44)
                    .overlay { Circle().stroke(Color.white.opacity(0.16), lineWidth: 1) }

                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(pressed ? 0.94 : (appeared ? 1.0 : 0.9))
            .opacity(appeared ? 1 : 0)
            .forgeAnimation(ForgeMotion.snappy, value: pressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Talk to ARIA")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .onAppear {
            // One entrance, then still. No idle pulse.
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : ForgeMotion.snappy.delay(0.4)) { appeared = true }
        }
    }
}
