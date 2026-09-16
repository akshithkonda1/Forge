import SwiftUI
import ForgeCore

/// Scrub surface for the live B+E nest mark.
/// Xcode: open `ForgeSwift/ForgeSwift.xcodeproj` → canvas on this file
/// (`#Preview("Nest demo")`) or run the app and present this view in DEBUG.
/// Idle / speaking / listening / still-pose (Reduce Motion + forgeMinimalAnimation).
struct AriaNestMarkDemoView: View {
    @State private var presence: AROrbState = .idle
    @State private var amplitude: Double = 0.34
    @State private var size: Double = 168
    @State private var reduceMotionOverride = false

    var body: some View {
        ZStack {
            Color(hex: "07060A").ignoresSafeArea()
            VStack(spacing: 22) {
                Text("B+E nest")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Color(hex: AriaNestGeometry.forgeOrangeHex))

                AuroraOrbView(
                    state: presence,
                    amplitude: Float(amplitude),
                    size: size,
                    followPresence: false
                )
                .environment(\.forgeMinimalAnimation, reduceMotionOverride)
                .id(reduceMotionOverride)

                Picker("Presence", selection: $presence) {
                    Text("Idle").tag(AROrbState.idle)
                    Text("Listening").tag(AROrbState.listening)
                    Text("Speaking").tag(AROrbState.speaking)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                Toggle("Still-pose (RM / forgeMinimalAnimation)", isOn: $reduceMotionOverride)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Size \(Int(size))pt")
                    Slider(value: $size, in: 28...220)
                    Text("Amplitude \(amplitude, specifier: "%.2f")")
                    Slider(value: $amplitude, in: 0...1)
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 24)

                Text("12 Hz · procedural · no PNG")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(.vertical, 28)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Nest demo") {
    AriaNestMarkDemoView()
}

#Preview("Nest idle") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.3, size: 180, followPresence: false)
    }
}

#Preview("Nest speaking") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        AuroraOrbView(state: .speaking, amplitude: 0.85, size: 180, followPresence: false)
    }
}

#Preview("Nest still-pose") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.3, size: 180, followPresence: false)
            .environment(\.forgeMinimalAnimation, true)
    }
}
