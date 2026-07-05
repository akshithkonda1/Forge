import SwiftUI
import ForgeCore

// MARK: - LifestyleContextView
//
// Manual context switching (Phase 2) + the settings that shape coaching:
// lifestyle profile and haptic intensity. Auto-detection only ever
// *suggests* — this screen is where the user stays in charge.

struct LifestyleContextView: View {
    @Environment(ContextEngine.self) private var contextEngine
    @Environment(MindfulnessSessionManager.self) private var session
    @State private var savingPlace: PlaceLabel?

    var body: some View {
        List {
            Section {
                ForEach(LifestyleMode.allCases) { mode in
                    modeRow(mode)
                }
                if contextEngine.currentMode != nil {
                    HapticButton(haptic: .click) {
                        contextEngine.setMode(nil)
                    } label: {
                        Label("Clear context", systemImage: "xmark.circle")
                            .font(.system(size: 12.5))
                            .foregroundStyle(ForgePalette.textTertiary)
                    }
                    .accessibilityHint("Removes the current context. Forge goes back to time-based suggestions.")
                }
            } header: {
                Text("Where are you in your day?")
            } footer: {
                if let mode = contextEngine.currentMode {
                    Text(mode.activationMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(mode.accentColor)
                }
            }

            Section("Your rhythm") {
                profilePicker
            }

            Section {
                ForEach(PlaceLabel.allCases) { label in
                    placeRow(label)
                }
            } header: {
                Text("Places")
            } footer: {
                Text("Saved places stay on this watch and help Forge suggest the right context — like noticing you've arrived at the gym.")
                    .font(.system(size: 10.5))
            }

            Section {
                hapticPicker
            } header: {
                Text("Breath haptics")
            } footer: {
                Text("Wrist taps pace each breath so sessions work eyes-free.")
                    .font(.system(size: 10.5))
            }
        }
        .navigationTitle("Context")
    }

    private func modeRow(_ mode: LifestyleMode) -> some View {
        let isCurrent = contextEngine.currentMode == mode
        return HapticButton(haptic: .click) {
            contextEngine.setMode(mode)
        } label: {
            HStack {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(mode.accentColor)
                    .frame(width: 22)
                Text(mode.displayName)
                    .font(.system(size: 13))
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(mode.accentColor)
                }
            }
        }
        .accessibilityLabel(mode.displayName)
        .accessibilityValue(isCurrent ? "Active" : "")
        .accessibilityHint("Sets your context so suggestions fit this part of your day.")
    }

    private func placeRow(_ label: PlaceLabel) -> some View {
        let saved = contextEngine.knownPlaces.places.contains { $0.label == label }
        return HapticButton(haptic: .click) {
            if saved {
                contextEngine.knownPlaces.remove(label: label)
            } else {
                savingPlace = label
                Task {
                    _ = await contextEngine.saveCurrentLocation(as: label)
                    savingPlace = nil
                }
            }
        } label: {
            HStack {
                Image(systemName: label.suggestedMode.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(label.suggestedMode.accentColor)
                    .frame(width: 22)
                Text(saved ? "\(label.displayName) saved" : "Save \(label.displayName.lowercased()) here")
                    .font(.system(size: 12.5))
                Spacer()
                if savingPlace == label {
                    ProgressView().controlSize(.mini)
                } else if saved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ForgePalette.success)
                }
            }
        }
        .accessibilityLabel(saved ? "\(label.displayName) location saved" : "Save current location as \(label.displayName)")
        .accessibilityHint(saved ? "Tap to remove this saved place." : "Uses one location fix, stored only on this watch.")
    }

    private var profilePicker: some View {
        // @Bindable would need Observation's Bindable wrapper; a manual
        // binding keeps `profile` a plain observable property.
        Picker("Lifestyle", selection: Binding(
            get: { contextEngine.profile },
            set: { contextEngine.profile = $0 }
        )) {
            ForEach(LifestyleProfile.allCases, id: \.self) { profile in
                Text(profile.displayName).tag(profile)
            }
        }
        .font(.system(size: 12.5))
        .accessibilityHint("Tailors coaching language to how your days actually run.")
    }

    private var hapticPicker: some View {
        Picker("Intensity", selection: Binding(
            get: { session.hapticIntensity },
            set: { session.hapticIntensity = $0 }
        )) {
            ForEach(MindfulnessSessionManager.HapticIntensity.allCases, id: \.self) { intensity in
                Text(intensity.label).tag(intensity)
            }
        }
        .font(.system(size: 12.5))
        .accessibilityLabel("Breath haptic intensity")
    }
}
