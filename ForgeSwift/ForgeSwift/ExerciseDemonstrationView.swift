import SwiftUI
import UIKit

enum ExerciseDemoTab: CaseIterable { case video, formCheck }

struct ExerciseDemonstrationView: View {
    let exercise: Exercise
    var definition: ExerciseDefinition? = nil
    @Binding var selectedTab: ExerciseDemoTab
    var onLaunchCamera: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ExerciseDemoTab.allCases, id: \.self) { tab in
                    Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { selectedTab = tab } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab == .video ? "play.circle.fill" : "camera.fill").font(.system(size: 12))
                            Text(tab == .video ? "Technique" : "ARIA Form Check").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(selectedTab == tab ? .white : .textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.ember : Color.surfaceElevated).cornerRadius(10)
                        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selectedTab)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Group {
                switch selectedTab {
                case .video:     ExerciseTechniqueView(exercise: exercise, definition: definition)
                case .formCheck: ExerciseFormCheckView(exercise: exercise, onLaunch: onLaunchCamera)
                }
            }
            .id(selectedTab)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(height: 190)
            .background(Color.background.opacity(0.5)).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: selectedTab)
        }
    }
}

struct ExerciseTechniqueView: View {
    let exercise: Exercise
    var definition: ExerciseDefinition?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.ember.opacity(0.09), Color.ember.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: definition?.icon ?? "figure.strengthtraining.traditional").font(.system(size: 36)).foregroundColor(.ember.opacity(0.55))
                if let def = definition {
                    VStack(spacing: 6) {
                        ForEach(def.cues.prefix(3), id: \.self) { cue in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(def.accent)
                                Text(cue).font(.system(size: 12)).foregroundColor(.textSecondary).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    Text(exercise.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                    Text("Focus on controlled tempo and full range.").font(.system(size: 12)).foregroundColor(.textTertiary)
                }
            }
            .padding(.vertical, 14)
        }
    }
}

struct ExerciseFormCheckView: View {
    let exercise: Exercise
    var onLaunch: (() -> Void)? = nil
    @State private var showCamera = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.success.opacity(0.08), Color.success.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: "camera.viewfinder").font(.system(size: 38)).foregroundColor(.success.opacity(0.5))
                Text("ARIA Live Form Check").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                Text("Show ARIA your set — get real-time cues via the Claude vision API.").font(.system(size: 11)).foregroundColor(.textTertiary).multilineTextAlignment(.center).padding(.horizontal, 24)
                Button {
                    if let onLaunch { onLaunch() } else { showCamera = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 13))
                        Text("Open Camera Coach").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.success).cornerRadius(20).shadow(color: Color.success.opacity(0.35), radius: 8, y: 3)
                }
            }
        }
        .sheet(isPresented: $showCamera) { FormCheckCameraView(exercise: exercise, definition: ExerciseLibrary.definition(for: exercise), liveContext: nil) }
    }
}

@MainActor
struct FormCheckCameraView: View {
    @Environment(\.dismiss) private var dismiss
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
            heartRate: 0, hrZone: 0, spO2: 98, elapsed: "—",
            cues: definition?.cues ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                cameraLayer
                if captureFlash { Color.white.opacity(0.6).ignoresSafeArea().transition(.opacity) }
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if aria.isAnalyzing { analyzingPill.padding(.bottom, 12) }
                    if let fb = feedback { feedbackCard(fb).padding(.horizontal, 16).padding(.bottom, 12) }
                    controlBar.padding(.bottom, 28)
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
            statePlaceholder(icon: "lock.fill", title: "Camera access needed",
                             subtitle: "Enable camera in Settings so ARIA can watch your form.")
        case .unavailable:
            statePlaceholder(icon: "camera.metering.unknown", title: "No camera here",
                             subtitle: "Run on a device to use ARIA's live form coach. You can still preview ARIA's analysis below.")
        default:
            ZStack { Color.black; ProgressView().tint(.white) }.ignoresSafeArea()
        }
    }

    private func statePlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44)).foregroundColor(.white.opacity(0.5))
            Text(title).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            Text(subtitle).font(.system(size: 13)).foregroundColor(.white.opacity(0.5)).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: "0A0A0A"))
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white).frame(width: 38, height: 38).background(.ultraThinMaterial).clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                HStack(spacing: 5) {
                    Circle().fill(aria.hasAPIKey ? Color.success : Color.warning).frame(width: 6, height: 6)
                    Text(aria.hasAPIKey ? "ARIA vision live" : "On-device preview").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
            if camera.status == .running {
                Button { camera.flip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill").font(.system(size: 15, weight: .semibold)).foregroundColor(.white).frame(width: 38, height: 38).background(.ultraThinMaterial).clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 16)
        .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var analyzingPill: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white)
            Text("ARIA is reading your form…").font(.system(size: 13, weight: .medium)).foregroundColor(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial).clipShape(Capsule())
    }

    private func feedbackCard(_ fb: FormFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 5).frame(width: 54, height: 54)
                    Circle().trim(from: 0, to: CGFloat(fb.score) / 100)
                        .stroke(fb.status.color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).frame(width: 54, height: 54).rotationEffect(.degrees(-90))
                    Text("\(fb.score)").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: fb.status.icon).font(.system(size: 12)).foregroundColor(fb.status.color)
                        Text(fb.status.label).font(.system(size: 14, weight: .bold)).foregroundColor(fb.status.color)
                        if !fb.isLive { Text("DEMO").font(.system(size: 8, weight: .black)).foregroundColor(.white.opacity(0.5)).padding(.horizontal, 4).padding(.vertical, 1).background(Color.white.opacity(0.12)).cornerRadius(3) }
                    }
                    Text(fb.summary).font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !fb.cues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(fb.cues, id: \.self) { cue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill").font(.system(size: 12)).foregroundColor(.ember)
                            Text(cue).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineSpacing(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(16).background(.ultraThinMaterial).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(fb.status.color.opacity(0.4), lineWidth: 1))
    }

    private var controlBar: some View {
        HStack(spacing: 20) {
            // Auto-coach toggle
            Button { toggleAuto() } label: {
                VStack(spacing: 4) {
                    Image(systemName: autoCoach ? "bolt.fill" : "bolt.slash.fill").font(.system(size: 18)).foregroundColor(autoCoach ? .ember : .white.opacity(0.6))
                    Text("Auto").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 56, height: 56).background(.ultraThinMaterial).clipShape(Circle())
            }
            // Shutter
            Button { Task { await analyze() } } label: {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(aria.isAnalyzing ? Color.white.opacity(0.4) : Color.white).frame(width: 60, height: 60)
                    Image(systemName: "camera.fill").font(.system(size: 22, weight: .bold)).foregroundColor(.black)
                }
            }
            .disabled(aria.isAnalyzing || (camera.status != .running && camera.status != .unavailable))
            // Done
            Button { dismiss() } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundColor(.success)
                    Text("Done").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 56, height: 56).background(.ultraThinMaterial).clipShape(Circle())
            }
        }
    }

    private func analyze() async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.12)) { captureFlash = true }
        let image = await camera.capture()
        withAnimation(.easeIn(duration: 0.25)) { captureFlash = false }
        // On a real device we send the captured frame; otherwise ARIA returns an on-device read.
        let fb: FormFeedback
        if let image { fb = await aria.analyzeForm(image: image, context: context) }
        else { fb = ARIACoachService.heuristicFeedback(for: context) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { feedback = fb }
        if fb.status == .stop { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    private func toggleAuto() {
        autoCoach.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
