import SwiftUI
import UIKit
import ForgeCore

enum ExerciseDemoTab: CaseIterable { case video, formCheck }

struct ExerciseDemonstrationView: View {
    let exercise: Exercise
    var definition: ExerciseDefinition? = nil
    @Binding var selectedTab: ExerciseDemoTab
    var onLaunchCamera: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tabOptions: [ForgeSegmentOption<ExerciseDemoTab>] {
        [
            ForgeSegmentOption(value: ExerciseDemoTab.video, title: "Technique", icon: "play.circle.fill"),
            ForgeSegmentOption(value: ExerciseDemoTab.formCheck, title: "ARIA Form Check", icon: "camera.fill"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForgeSegmentedControl(tabOptions, selection: $selectedTab, accent: .ember, bleed: 0)
            tabContent
        }
    }

    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .video:     ExerciseTechniqueView(exercise: exercise, definition: definition)
            case .formCheck: ExerciseFormCheckView(exercise: exercise, onLaunch: onLaunchCamera)
            }
        }
        .id(selectedTab)
        .transition(.opacity)
        .animation(reduceMotion ? nil : ForgeMotion.smooth, value: selectedTab)
    }
}

struct ExerciseTechniqueView: View {
    let exercise: Exercise
    var definition: ExerciseDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            visual
            if let def = definition {
                cueRows(def)
            } else {
                fallbackCopy
            }
        }
    }

    /// The decorative visual keeps a minimum height; the cues live below it so
    /// they can wrap and grow with Dynamic Type instead of being clipped.
    private var visual: some View {
        ZStack {
            LinearGradient(
                colors: [Color.ember.opacity(0.09), Color.ember.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: definition?.icon ?? "figure.strengthtraining.traditional")
                .font(.system(size: 36))
                .foregroundStyle(Color.ember.opacity(0.55))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .forgeWell(padding: 0)
    }

    private func cueRows(_ def: ExerciseDefinition) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForEach(Array(def.cues.prefix(3)), id: \.self) { cue in
                HStack(alignment: .firstTextBaseline, spacing: ForgeLayout.rowGap) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(HomeType.body)
                        .imageScale(.small)
                        .foregroundStyle(def.accent)
                        .accessibilityHidden(true)
                    Text(cue)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var fallbackCopy: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(exercise.name)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Focus on controlled tempo and full range.")
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }
}

struct ExerciseFormCheckView: View {
    let exercise: Exercise
    var onLaunch: (() -> Void)? = nil
    @State private var showCamera = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.steel.opacity(0.10), Color.steel.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: ForgeLayout.rowGap) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.steel.opacity(0.7))
                    .accessibilityHidden(true)
                VStack(spacing: ForgeLayout.pairGap) {
                    Text("ARIA Live Form Check")
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .forgeWrapping()
                    Text("ARIA watches one set and gives you live cues.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .forgeWrapping()
                }
                ForgeSecondaryButton(title: "Open Camera Coach", icon: "camera.fill", accent: .ember) {
                    if let onLaunch { onLaunch() } else { showCamera = true }
                }
            }
            .padding(FDS.Spacing.lg)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .forgeWell(padding: 0)
        .sheet(isPresented: $showCamera) { FormCheckCameraView(exercise: exercise, definition: ExerciseLibrary.definition(for: exercise), liveContext: nil) }
    }
}

@MainActor
struct FormCheckCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scoreRingSize: CGFloat = 54
    let exercise: Exercise
    var definition: ExerciseDefinition?
    var liveContext: ARIALiveContext?

    @StateObject private var camera = FormCameraController()
    @StateObject private var aria = ARIACoachService()
    @State private var feedback: FormFeedback?
    @State private var autoCoach = false
    @State private var autoTask: Task<Void, Never>? = nil
    @State private var captureFlash = false

    private var context: ARIALiveContext {
        liveContext ?? ARIALiveContext(
            exerciseName: exercise.name,
            setLabel: "Working set",
            weight: exercise.weight ?? 0, reps: exercise.reps,
            heartRate: nil, hrZone: nil, spO2: nil, elapsed: "—",
            cues: definition?.cues ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                cameraLayer
                if captureFlash { captureBorder }
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if aria.isAnalyzing { analyzingPill.padding(.bottom, FDS.Spacing.md) }
                    if let fb = feedback { feedbackCard(fb).padding(.horizontal, ForgeLayout.screenInset).padding(.bottom, FDS.Spacing.md) }
                    controlBar.padding(.bottom, FDS.Spacing.xl)
                }
            }
            .navigationBarHidden(true)
            .onAppear { camera.start() }
            .onDisappear { camera.stop(); autoTask?.cancel() }
        }
    }

    // ── Camera surface / permission states ────────────────────────────────────
    @ViewBuilder
    private var cameraLayer: some View {
        switch camera.status {
        case .running, .configuring:
            CameraPreview(session: camera.session).ignoresSafeArea()
        case .denied:
            permissionPlaceholder
        case .unavailable:
            statePlaceholder(icon: "camera.metering.unknown", title: "Camera isn't available here",
                             subtitle: "You can still preview ARIA's analysis below.")
        default:
            ZStack {
                Color.black
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Starting camera")
            }
            .ignoresSafeArea()
        }
    }

    private var permissionPlaceholder: some View {
        VStack {
            Spacer()
            ForgePermissionPrompt(
                title: "Camera access needed",
                message: "Enable camera in Settings so ARIA can watch your form.",
                systemImage: "lock.fill",
                accent: .steel,
                allowTitle: "Open Settings",
                skipTitle: "Close",
                onAllow: { openSettings() },
                onSkip: { dismiss() }
            )
            Spacer()
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forgeScreenBackground(accent: .ember)
    }

    private func statePlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: ForgeLayout.rowGap) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(HomeType.sessionTitle)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .forgeWrapping()
            Text(subtitle)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .forgeWrapping()
        }
        .padding(.horizontal, ForgeLayout.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forgeScreenBackground(accent: .ember)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// A thin border pulse marks each capture. It replaces the old full-screen
    /// white flash, which repeated every few seconds in Auto mode.
    private var captureBorder: some View {
        Rectangle()
            .stroke(Color.white.opacity(0.85), lineWidth: 4)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    // ── Chrome ────────────────────────────────────────────────────────────────
    private func cameraIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var topBar: some View {
        HStack(spacing: FDS.Spacing.md) {
            cameraIconButton(systemImage: "xmark", label: "Close") { dismiss() }
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text(exercise.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: FDS.Spacing.xs) {
                    Circle()
                        .fill(aria.isLiveCoachingAvailable ? Color.success : Color.warning)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(aria.isLiveCoachingAvailable ? "ARIA vision live" : "On-device preview")
                        .font(HomeType.micro)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
            Spacer(minLength: 0)
            if camera.status == .running {
                cameraIconButton(systemImage: "arrow.triangle.2.circlepath.camera.fill", label: "Flip camera") { camera.flip() }
            }
        }
        .padding(.horizontal, ForgeLayout.screenInset).padding(.top, FDS.Spacing.lg)
        .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var analyzingPill: some View {
        HStack(spacing: FDS.Spacing.sm) {
            ProgressView().tint(.white)
            Text("ARIA is reading your form…")
                .font(HomeType.label)
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.md).background(.ultraThinMaterial).clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }

    // ── Feedback ──────────────────────────────────────────────────────────────
    /// Local status map (never alert red for a status): good is vitality,
    /// adjust is amber, stop is the steel-family miss tone.
    private func statusTint(_ status: FormFeedback.Status) -> Color {
        switch status {
        case .good: return Color.vitality
        case .adjust: return Color.amber
        case .stop: return HudChrome.miss
        }
    }

    private func feedbackCard(_ fb: FormFeedback) -> some View {
        let tint = statusTint(fb.status)
        return VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
                scoreRing(fb, tint: tint)
                feedbackSummary(fb, tint: tint)
            }
            if !fb.cues.isEmpty {
                feedbackCues(fb)
            }
        }
        .padding(ForgeLayout.cardPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: ForgeUX.stroke)
        )
        .accessibilityElement(children: .contain)
    }

    private func scoreRing(_ fb: FormFeedback, tint: Color) -> some View {
        let size = ForgeLayout.scaledCap(scoreRingSize, base: 54)
        return ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(fb.score) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(fb.score)")
                .font(HomeType.metric)
                .foregroundStyle(Color.white)
                .hudInArcText()
                .padding(FDS.Spacing.sm)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Form score \(fb.score) out of 100")
    }

    private func feedbackSummary(_ fb: FormFeedback, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: fb.status.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(fb.status.label)
                    .font(HomeType.status)
                    .foregroundStyle(tint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !fb.isLive {
                ForgeChip(label: "DEMO")
            }
            Text(fb.summary)
                .font(HomeType.body)
                .foregroundStyle(Color.white.opacity(0.9))
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feedbackCues(_ fb: FormFeedback) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            ForEach(fb.cues, id: \.self) { cue in
                HStack(alignment: .firstTextBaseline, spacing: ForgeLayout.rowGap) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(HomeType.body)
                        .imageScale(.small)
                        .foregroundStyle(Color.ember)
                        .accessibilityHidden(true)
                    Text(cue)
                        .font(HomeType.body)
                        .foregroundStyle(Color.white)
                        .forgeWrapping()
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // ── Controls ──────────────────────────────────────────────────────────────
    private var controlBar: some View {
        HStack(alignment: .top, spacing: FDS.Spacing.xl) {
            autoControl
            shutterControl
            doneControl
        }
    }

    private func controlLabel(_ text: String) -> some View {
        Text(text)
            .font(HomeType.micro)
            .foregroundStyle(Color.white.opacity(0.85))
            .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
    }

    private var autoControl: some View {
        Button { toggleAuto() } label: {
            VStack(spacing: FDS.Spacing.xs) {
                Image(systemName: autoCoach ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(autoCoach ? Color.ember : Color.white.opacity(0.7))
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .frame(height: 74)
                controlLabel("Auto")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto coach")
        .accessibilityValue(autoCoach ? "On" : "Off")
        .accessibilityHint("Checks your form every few seconds")
        .accessibilityAddTraits(.isToggle)
    }

    private var shutterControl: some View {
        Button { Task { await analyze() } } label: {
            VStack(spacing: FDS.Spacing.xs) {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(aria.isAnalyzing ? Color.white.opacity(0.4) : Color.white).frame(width: 60, height: 60)
                    Image(systemName: "camera.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.black)
                }
                controlLabel("Check form")
            }
        }
        .buttonStyle(.plain)
        .disabled(aria.isAnalyzing || (camera.status != .running && camera.status != .unavailable))
        .accessibilityLabel("Check form")
        .accessibilityHint("Takes a photo for ARIA to read")
    }

    private var doneControl: some View {
        Button {
            dismiss()
        } label: {
            VStack(spacing: FDS.Spacing.xs) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.vitality)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .frame(height: 74)
                controlLabel("Done")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
    }

    // ── Actions ───────────────────────────────────────────────────────────────
    private func setCaptureFlash(_ on: Bool) {
        var animation: Animation? = nil
        if !reduceMotion {
            animation = on ? Animation.easeOut(duration: 0.12) : Animation.easeIn(duration: 0.25)
        }
        withAnimation(animation) { captureFlash = on }
    }

    private func analyze() async {
        ForgeHaptics.play(.press)
        setCaptureFlash(true)
        let image = await camera.capture()
        setCaptureFlash(false)
        // On a real device we send the captured frame; otherwise ARIA returns an on-device read.
        let fb: FormFeedback
        if let image { fb = await aria.analyzeForm(image: image, context: context) }
        else { fb = ARIACoachService.heuristicFeedback(for: context) }
        let reveal: Animation? = reduceMotion ? nil : ForgeMotion.smooth
        withAnimation(reveal) { feedback = fb }
        AccessibilityNotification.Announcement("\(fb.status.label). \(fb.cues.first ?? fb.summary)").post()
        if fb.status == .stop { ForgeHaptics.play(.error) }
    }

    private func toggleAuto() {
        autoCoach.toggle()
        ForgeHaptics.play(.selection)
        if autoCoach {
            autoTask = Task {
                while !Task.isCancelled && autoCoach {
                    await analyze()
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                }
            }
        } else {
            autoTask?.cancel(); autoTask = nil
        }
    }
}
