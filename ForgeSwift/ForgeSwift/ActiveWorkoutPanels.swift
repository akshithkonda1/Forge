import SwiftUI
import UIKit

struct AutoRegStrip: View {
    let recommendation: SetRecommendation
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(recommendation.primaryAction.tone.opacity(0.14)).frame(width: 36, height: 36)
                Image(systemName: recommendation.primaryAction.icon).font(.system(size: 15, weight: .semibold)).foregroundColor(recommendation.primaryAction.tone)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("ARIA AUTO-REG").font(.system(size: 9, weight: .black)).tracking(1.5).foregroundColor(.textTertiary)
                    if recommendation.weightDelta != 0 {
                        Text("\(recommendation.weightDelta > 0 ? "+" : "")\(recommendation.weightDelta) lb")
                            .font(.system(size: 9, weight: .black)).foregroundColor(recommendation.primaryAction.tone)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(recommendation.primaryAction.tone.opacity(0.14)).cornerRadius(4)
                    }
                }
                Text(recommendation.rationale).font(.system(size: 12)).foregroundColor(.textSecondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(Color.surfaceElevated).cornerRadius(13)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(recommendation.primaryAction.tone.opacity(0.2), lineWidth: 1))
    }
}

struct SubstitutionBanner: View {
    let target: ExerciseDefinition
    let reason: String
    let onApply: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.steel.opacity(0.2)).frame(width: 40, height: 40)
                        Image(systemName: "arrow.triangle.swap").font(.system(size: 17)).foregroundColor(.steel)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARIA SUGGESTS A SWAP").font(.system(size: 10, weight: .black)).tracking(1.5).foregroundColor(.steel)
                        Text("\(reason) — try \(target.name)").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                    }
                    Spacer()
                    Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.textMuted).frame(width: 28, height: 28).background(Color.surfaceElevated).clipShape(Circle()) }
                }
                Button(action: onApply) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .bold))
                        Text("Swap to \(target.name)").font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 44).background(Color.steel).cornerRadius(12)
                }
            }
            .padding(16)
            .background(ZStack { Color.surface; LinearGradient(colors: [Color.steel.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing) })
            .cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.steel.opacity(0.4), lineWidth: 1.5))
            .shadow(color: Color.steel.opacity(0.25), radius: 20, y: 6)
            .padding(.horizontal, 16).padding(.top, 56)
            Spacer()
        }
    }
}

struct O2WarningBanner: View {
    let spO2: Int
    let onDismiss: () -> Void
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.danger.opacity(0.2)).frame(width: 40, height: 40)
                    Image(systemName: "lungs.fill").font(.system(size: 18)).foregroundColor(.danger)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOW O₂ SATURATION").font(.system(size: 11, weight: .black)).foregroundColor(.danger).tracking(1.5)
                    Text("\(spO2)% — Slow down and breathe deeply").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.textMuted).frame(width: 28, height: 28).background(Color.surfaceElevated).clipShape(Circle()) }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(ZStack { Color.surface; LinearGradient(colors: [Color.danger.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing) })
            .cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.danger.opacity(0.45), lineWidth: 1.5))
            .shadow(color: Color.danger.opacity(0.25), radius: 20, y: 6)
            .padding(.horizontal, 16).padding(.top, 56)
            Spacer()
        }
    }
}

struct SetLoggerPanel: View {
    let exercise: Exercise
    let definition: ExerciseDefinition?
    let currentSet: Int
    let recommendation: SetRecommendation
    @Binding var proposedReps: Int
    @Binding var proposedWeight: Int
    @Binding var proposedRPE: Int
    let onConfirm: () -> Void
    let onCancel:  () -> Void
    @State private var rpePulsing: Int? = nil

    private func rpeLabel(_ r: Int) -> String {
        switch r {
        case 1...3: return "Easy"
        case 4...5: return "Moderate"
        case 6...7: return "Hard"
        case 8: return "Very Hard"
        case 9: return "Max Effort"
        default: return "All Out 🔥"
        }
    }
    private func rpeColor(_ r: Int) -> Color { r <= 4 ? .success : r <= 7 ? Color(hex: "F59E0B") : .danger }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { onCancel() }
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    VStack(spacing: 14) {
                        Capsule().fill(Color.white.opacity(0.18)).frame(width: 36, height: 4)
                        Text("SET \(currentSet) — \(exercise.name.uppercased())").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.45)).tracking(2.5)
                    }
                    .padding(.top, 16).padding(.bottom, 14)

                    // ARIA recommendation
                    HStack(spacing: 10) {
                        Image(systemName: recommendation.primaryAction.icon).font(.system(size: 13)).foregroundColor(recommendation.primaryAction.tone)
                        Text(recommendation.rationale).font(.system(size: 12)).foregroundColor(.white.opacity(0.7)).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 14)

                    Divider().background(Color.white.opacity(0.08))
                    VStack(spacing: 18) {
                        VStack(spacing: 10) {
                            Text("REPS PERFORMED").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                            HStack(spacing: 32) {
                                stepperButton("minus", tint: .white.opacity(0.7), bg: .white.opacity(0.08)) { if proposedReps > 1 { proposedReps -= 1 } }
                                Text("\(proposedReps)").font(.system(size: 72, weight: .black, design: .rounded)).foregroundColor(.white).frame(minWidth: 90).contentTransition(.numericText())
                                stepperButton("plus", tint: .ember, bg: .ember.opacity(0.22)) { proposedReps += 1 }
                            }
                        }
                        if exercise.weight != nil && proposedWeight > 0 {
                            VStack(spacing: 10) {
                                Text("WEIGHT (LBS)").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                                HStack(spacing: 7) {
                                    ForEach([(-10, "-10"), (-5, "-5"), (5, "+5"), (10, "+10")], id: \.0) { delta, lbl in
                                        Button {
                                            proposedWeight = max(0, proposedWeight + delta); UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } label: {
                                            Text(lbl).font(.system(size: 14, weight: .bold)).foregroundColor(delta > 0 ? .ember : .white.opacity(0.6))
                                                .frame(maxWidth: .infinity).frame(height: 40)
                                                .background(delta > 0 ? Color.ember.opacity(0.15) : Color.white.opacity(0.07)).cornerRadius(10)
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(delta > 0 ? Color.ember.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1))
                                        }
                                    }
                                    Text("\(proposedWeight)").font(.system(size: 18, weight: .black, design: .rounded)).foregroundColor(.white).contentTransition(.numericText()).frame(minWidth: 52)
                                }
                            }
                        }
                        VStack(spacing: 10) {
                            HStack {
                                Text("EFFORT").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.4)).tracking(2.5)
                                Spacer()
                                Text("RPE \(proposedRPE) — \(rpeLabel(proposedRPE))").font(.system(size: 12, weight: .bold)).foregroundColor(rpeColor(proposedRPE)).animation(.spring(response: 0.3, dampingFraction: 0.7), value: proposedRPE)
                            }
                            HStack(spacing: 3) {
                                ForEach(1...10, id: \.self) { level in
                                    Button {
                                        proposedRPE = level; rpePulsing = level; UISelectionFeedbackGenerator().selectionChanged()
                                        Task { try? await Task.sleep(nanoseconds: 180_000_000); rpePulsing = nil }
                                    } label: {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(level <= proposedRPE ? rpeColor(level) : Color.white.opacity(0.07))
                                            .frame(maxWidth: .infinity).frame(height: 36)
                                            .overlay(Text("\(level)").font(.system(size: 11, weight: .black)).foregroundColor(level <= proposedRPE ? .white : .white.opacity(0.25)))
                                            .scaleEffect(rpePulsing == level ? 1.18 : 1.0).animation(.spring(response: 0.2, dampingFraction: 0.5), value: rpePulsing)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Button(action: onConfirm) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                                Text("Log Set").font(.system(size: 20, weight: .black))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 60)
                            .background(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(20).shadow(color: Color.ember.opacity(0.55), radius: 20, y: 6)
                        }
                        Button(action: onCancel) { Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.4)) }.padding(.bottom, 8)
                    }
                    .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 28)
                }
                .background(ZStack { Color(hex: "0E0E0E"); LinearGradient(colors: [Color.ember.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .bottomTrailing) })
                .roundedCorners(32, corners: [.topLeft, .topRight])
                .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color.white.opacity(0.09), lineWidth: 1).mask(Rectangle().padding(.bottom, -40)))
            }
        }
        .ignoresSafeArea()
    }

    private func stepperButton(_ icon: String, tint: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button { action(); UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
            ZStack {
                Circle().fill(bg).frame(width: 44, height: 44).overlay(Circle().stroke(tint.opacity(0.4), lineWidth: 1))
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundColor(tint)
            }
        }
    }
}

struct PainLoggerPanel: View {
    let exerciseName: String
    let onLog:    (PainEntry) -> Void
    let onCancel: () -> Void
    @State private var selectedLocation = "Knee"
    @State private var severity = 5
    private let locations = ["Shoulder", "Elbow", "Wrist", "Lower Back", "Hip", "Knee", "Ankle", "Neck", "Other"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Capsule().fill(Color.textTertiary.opacity(0.4)).frame(width: 36, height: 4).padding(.top, 12)
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15)).foregroundColor(.warning)
                    Text("LOG PAIN / DISCOMFORT").font(.system(size: 11, weight: .black)).foregroundColor(.textTertiary).tracking(2)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("LOCATION").font(.system(size: 10, weight: .black)).foregroundColor(.textMuted).tracking(2)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(locations, id: \.self) { loc in
                            Button { selectedLocation = loc; UISelectionFeedbackGenerator().selectionChanged() } label: {
                                Text(loc).font(.system(size: 13, weight: .medium)).foregroundColor(selectedLocation == loc ? .white : .textSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(selectedLocation == loc ? Color.warning : Color.surfaceElevated).cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedLocation == loc ? Color.warning.opacity(0.5) : Color.borderColor.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("SEVERITY").font(.system(size: 10, weight: .black)).foregroundColor(.textMuted).tracking(2)
                        Spacer()
                        Text("\(severity)/10").font(.system(size: 13, weight: .bold)).foregroundColor(severity >= 7 ? .danger : .warning)
                    }
                    HStack(spacing: 3) {
                        ForEach(1...10, id: \.self) { level in
                            Button { severity = level; UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(level <= severity ? (severity >= 7 ? Color.danger : Color.warning) : Color.surfaceElevated)
                                    .frame(maxWidth: .infinity).frame(height: 32)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.borderColor.opacity(0.3), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(severity >= 7 ? "Sharp pain — ARIA will pull you off this movement." : severity >= 5 ? "ARIA may swap to a joint-friendly variant." : "Logged for ARIA to monitor.")
                        .font(.system(size: 11)).foregroundColor(.textTertiary)
                }
                Button { onLog(PainEntry(location: selectedLocation, severity: severity, exerciseName: exerciseName)) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18))
                        Text("Log Pain").font(.system(size: 18, weight: .black))
                    }
                    .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 56)
                    .background(LinearGradient(colors: [Color.warning, Color.warning.opacity(0.82)], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(18).shadow(color: Color.warning.opacity(0.5), radius: 16, y: 6)
                }
                .padding(.horizontal, 4)
                Button(action: onCancel) { Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundColor(.textSecondary) }.padding(.bottom, 32)
            }
            .padding(.horizontal, 24).background(Color.surface).roundedCorners(28, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.22), radius: 40, y: -10)
        }
        .ignoresSafeArea()
    }
}

struct PRBannerView: View {
    let exerciseName: String
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.warning.opacity(0.2)).frame(width: 40, height: 40)
                    Image(systemName: "trophy.fill").font(.system(size: 18)).foregroundColor(.warning)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("PERSONAL RECORD 🏆").font(.system(size: 12, weight: .black)).foregroundColor(.warning).tracking(1.5)
                    Text(exerciseName).font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(ZStack { Color.surface; LinearGradient(colors: [Color.warning.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing) })
            .cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.warning.opacity(0.4), lineWidth: 1.5))
            .shadow(color: Color.warning.opacity(0.25), radius: 20, y: 6)
            .padding(.horizontal, 16).padding(.top, 56)
            Spacer()
        }
    }
}

struct RestTimerView: View {
    let restTimeLeft: Int
    let totalRest:    Int
    let nextLabel:    String
    let onSkip:       () -> Void
    @State private var breathPhase = false

    private var progress: CGFloat { totalRest > 0 ? CGFloat(restTimeLeft) / CGFloat(totalRest) : 0 }
    private var urgency: Bool { restTimeLeft <= 5 && restTimeLeft > 0 }
    private var ringColor: Color { urgency ? .danger : Color(hex: "38BDF8") }
    private var breathLabel: String { breathPhase ? "Exhale slowly" : "Breathe in" }

    var body: some View {
        VStack(spacing: 20) {
            Text("REST").font(.system(size: 11, weight: .black)).foregroundColor(.textMuted).tracking(4)
                .padding(.horizontal, 14).padding(.vertical, 6).background(Color.surfaceElevated).cornerRadius(100)
                .overlay(Capsule().stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
            ZStack {
                Circle().fill(ringColor.opacity(0.06)).frame(width: 220, height: 220).animation(.easeInOut(duration: 1.0), value: ringColor)
                Circle().stroke(Color.borderColor.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 170, height: 170)
                Circle().trim(from: 0, to: progress).stroke(ringColor.opacity(0.5), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 170, height: 170).rotationEffect(.degrees(-90)).blur(radius: 6).animation(.linear(duration: 1), value: progress)
                Circle().trim(from: 0, to: progress)
                    .stroke(LinearGradient(colors: [ringColor, ringColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 170, height: 170).rotationEffect(.degrees(-90)).animation(.linear(duration: 1), value: progress).animation(.easeInOut(duration: 0.6), value: ringColor)
                ZStack {
                    Circle().stroke(Color(hex: "38BDF8").opacity(breathPhase ? 0.15 : 0.0), lineWidth: 1.5).frame(width: breathPhase ? 130 : 80, height: breathPhase ? 130 : 80).animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathPhase)
                    Circle().stroke(Color(hex: "38BDF8").opacity(breathPhase ? 0.25 : 0.08), lineWidth: 2).frame(width: breathPhase ? 100 : 60, height: breathPhase ? 100 : 60).animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathPhase)
                    Circle().fill(Color(hex: "38BDF8").opacity(breathPhase ? 0.15 : 0.04)).frame(width: breathPhase ? 80 : 50, height: breathPhase ? 80 : 50).animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathPhase)
                }
                .opacity(urgency ? 0 : 1)
                VStack(spacing: 3) {
                    Text("\(restTimeLeft)").font(.system(size: 62, weight: .black, design: .rounded)).foregroundColor(urgency ? .danger : .textPrimary).contentTransition(.numericText())
                        .scaleEffect(urgency ? 1.1 : 1.0).animation(.spring(response: 0.3, dampingFraction: 0.55), value: urgency)
                    Text("sec").font(.system(size: 12, weight: .semibold)).foregroundColor(.textMuted)
                }
            }
            .frame(width: 220, height: 220)
            if !urgency {
                Text(breathLabel).font(.system(size: 13, weight: .medium)).foregroundColor(Color(hex: "38BDF8").opacity(0.8)).animation(.easeInOut(duration: 0.5), value: breathPhase)
            }
            Text(nextLabel).font(.system(size: 14, weight: .medium)).foregroundColor(.textTertiary).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button(action: onSkip) {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill").font(.system(size: 13))
                    Text("Skip Rest").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.textSecondary).padding(.horizontal, 28).padding(.vertical, 14).background(Color.surfaceElevated).cornerRadius(100)
                .overlay(Capsule().stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .onAppear { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathPhase = true } }
    }
}
