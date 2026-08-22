import SwiftUI

struct WakeUpTab: View {
    @EnvironmentObject private var hkService: HealthKitSleepService
    @State private var smartWakeEnabled = true
    @State private var smartWakeWindow  = 30
    @State private var sunriseEnabled   = true
    @State private var sunriseDuration  = 20          // minutes
    @State private var colorTemp        = 0.5         // 0=warm, 1=cool
    @State private var volumeRamp: VolumeRampCurve    = .gradual
    @State private var morningRoutine: [RoutineItem]  = RoutineItem.defaults

    var body: some View {
        VStack(spacing: 20) {
            SmartWakeCard(
                enabled: $smartWakeEnabled,
                windowMinutes: $smartWakeWindow
            )

            AdaptiveSunriseCard(
                config: hkService.currentSunriseConfig,
                enabled: $sunriseEnabled,
                duration: $sunriseDuration,
                colorTemp: $colorTemp
            )

            VolumeRampCard(curve: $volumeRamp)

            MorningRoutineCard(items: $morningRoutine)

            WakeGreetingCard()
        }
        .onAppear {
            let config = hkService.currentSunriseConfig
            sunriseDuration = config.durationMinutes
            colorTemp = config.colorTemp
            smartWakeWindow = hkService.computeSmartAlarmWindow(
                baseWindow: smartWakeWindow,
                recentScore: nil,
                debt: 0,
                chronotype: hkService.userProfile.chronotype
            )
        }
    }
}

struct SmartWakeCard: View {
    @Binding var enabled: Bool
    @Binding var windowMinutes: Int

    var body: some View {
        VStack(spacing: 0) {
            WakeUpSection(icon: "waveform.path.ecg", title: "Smart Wake", color: .steel) {
                VStack(spacing: 14) {
                    Toggle(isOn: $enabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Wake during lightest sleep")
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                            Text("Detects your sleep cycle and wakes you at the optimal moment")
                                .font(.system(size: 12)).foregroundColor(.textTertiary).lineSpacing(3)
                        }
                    }
                    .tint(.steel)

                    if enabled {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Detection window")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                            HStack(spacing: 10) {
                                ForEach([15, 30, 45], id: \.self) { mins in
                                    Button {
                                        windowMinutes = mins
                                        UISelectionFeedbackGenerator().selectionChanged()
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text("\(mins)")
                                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                                .foregroundColor(windowMinutes == mins ? .white : .textPrimary)
                                            Text("min")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(windowMinutes == mins ? .white.opacity(0.7) : .textTertiary)
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(windowMinutes == mins ? Color.steel : Color.surfaceElevated)
                                        .cornerRadius(14)
                                        .shadow(color: windowMinutes == mins ? Color.steel.opacity(0.35) : .clear, radius: 8, y: 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Visual representation
                            HStack(spacing: 0) {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6).fill(Color.borderColor.opacity(0.3)).frame(height: 8)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient(colors: [Color.steel.opacity(0.3), Color.steel], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: CGFloat(windowMinutes) / 45 * 200, height: 8)
                                }
                                .frame(width: 200)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Image(systemName: "alarm.fill").font(.system(size: 12)).foregroundColor(.ember)
                                    Text("Alarm").font(.system(size: 9, weight: .medium)).foregroundColor(.textMuted)
                                }
                                .padding(.leading, 6)
                            }
                            .padding(.top, 4)
                        }
                        .padding(12).background(Color.steel.opacity(0.06)).cornerRadius(12)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }
                }
            }
        }
    }
}

struct SunriseSimulationCard: View {
    @Binding var enabled: Bool
    @Binding var duration: Int
    @Binding var colorTemp: Double   // 0=warm 2700K, 1=cool 5000K

    private var displayColor: Color {
        Color(
            red: 1.0,
            green: 0.6 + colorTemp * 0.35,
            blue: 0.3 + colorTemp * 0.7
        ).opacity(0.9)
    }

    var body: some View {
        WakeUpSection(icon: "sunrise.fill", title: "Sunrise Simulation", color: Color(hex: "F59E0B")) {
            VStack(spacing: 16) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gradual light increase")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                        Text("Mimics a natural sunrise to gently bring you out of sleep")
                            .font(.system(size: 12)).foregroundColor(.textTertiary)
                    }
                }
                .tint(Color(hex: "F59E0B"))

                if enabled {
                    VStack(spacing: 14) {
                        // Duration
                        HStack {
                            Text("Duration").font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(duration) min")
                                    .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                                Stepper("", value: $duration, in: 5...60, step: 5)
                                    .labelsHidden().tint(Color(hex: "F59E0B"))
                            }
                        }

                        // Color temperature
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Color Temperature").font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                                Spacer()
                                Text(colorTemp < 0.3 ? "2700K Warm" : colorTemp < 0.7 ? "3500K Neutral" : "5000K Cool")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(displayColor)
                            }

                            // Gradient slider preview
                            ZStack(alignment: .bottom) {
                                LinearGradient(
                                    colors: [Color(hex: "FF8C42"), Color(hex: "FFD166"), Color(hex: "FEFAE0"), Color(hex: "C8E6FF")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(height: 24).cornerRadius(12)

                                Slider(value: $colorTemp)
                                    .tint(.clear)
                                    .padding(.horizontal, 2)
                            }
                        }

                        // Preview
                        HStack(spacing: 8) {
                            ForEach(Array(stride(from: 0.1, through: 1.0, by: 0.18)), id: \.self) { t in
                                Circle()
                                    .fill(Color(
                                        red: 1.0,
                                        green: 0.4 + t * 0.55,
                                        blue: 0.1 + t * 0.85
                                    ))
                                    .frame(width: 8, height: 8)
                                    .frame(maxWidth: .infinity)
                                    .opacity(0.3 + t * 0.7)
                            }
                        }
                        .frame(height: 16)
                        .padding(.horizontal, 4)
                        .overlay(alignment: .leading) {
                            Text("Start").font(.system(size: 9, weight: .medium)).foregroundColor(.textMuted)
                        }
                        .overlay(alignment: .trailing) {
                            Text("Full").font(.system(size: 9, weight: .medium)).foregroundColor(.textMuted)
                        }
                    }
                    .padding(12).background(Color(hex: "F59E0B").opacity(0.06)).cornerRadius(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
    }
}

struct VolumeRampCard: View {
    @Binding var curve: VolumeRampCurve

    var body: some View {
        WakeUpSection(icon: "speaker.wave.3.fill", title: "Volume Ramp", color: .ember) {
            VStack(spacing: 12) {
                ForEach(VolumeRampCurve.allCases, id: \.self) { option in
                    Button {
                        curve = option
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(curve == option ? Color.ember.opacity(0.15) : Color.surfaceElevated)
                                    .frame(width: 38, height: 38)
                                Image(systemName: option.icon)
                                    .font(.system(size: 15))
                                    .foregroundColor(curve == option ? .ember : .textTertiary)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.rawValue).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                                Text(option.description).font(.system(size: 12)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                            if curve == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18)).foregroundColor(.ember)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(curve == option ? Color.ember.opacity(0.07) : Color.surfaceElevated)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(curve == option ? Color.ember.opacity(0.4) : Color.borderColor.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                // Visual curve preview
                VolumeRampPreview(curve: curve)
            }
        }
    }
}

struct VolumeRampPreview: View {
    let curve: VolumeRampCurve

    private func height(for x: CGFloat) -> CGFloat {
        switch curve {
        case .instant: return x > 0.02 ? 1.0 : 0
        case .gentle:  return min(1.0, x * 6.67)
        case .gradual: return x * x
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Volume preview")
                .font(.system(size: 11, weight: .medium)).foregroundColor(.textMuted)
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<80, id: \.self) { i in
                        let x = CGFloat(i) / 79
                        let h = height(for: x)
                        Rectangle()
                            .fill(Color.ember.opacity(0.3 + h * 0.5))
                            .frame(width: geo.size.width / 80, height: geo.size.height * h)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: curve)
            }
            .frame(height: 44)
            .cornerRadius(6)
        }
        .padding(12).background(Color.surfaceElevated).cornerRadius(12)
    }
}

struct MorningRoutineCard: View {
    @Binding var items: [RoutineItem]
    @State private var editMode = false

    var totalMinutes: Int { items.filter { $0.isEnabled }.reduce(0) { $0 + $1.duration } }

    var body: some View {
        WakeUpSection(icon: "checklist", title: "Morning Routine", color: .success) {
            VStack(spacing: 12) {
                HStack {
                    Text("Total: \(totalMinutes) min")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.textSecondary)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { editMode.toggle() }
                    } label: {
                        Text(editMode ? "Done" : "Edit")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.success)
                    }
                }

                ForEach($items) { $item in
                    HStack(spacing: 12) {
                        // Drag handle (visible in edit mode)
                        if editMode {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 14)).foregroundColor(.textMuted)
                        }

                        Toggle(isOn: $item.isEnabled) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(item.isEnabled ? Color.success.opacity(0.15) : Color.surfaceElevated)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: item.icon)
                                        .font(.system(size: 14))
                                        .foregroundColor(item.isEnabled ? .success : .textMuted)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(item.isEnabled ? .textPrimary : .textTertiary)
                                    Text("\(item.duration) min")
                                        .font(.system(size: 11))
                                        .foregroundColor(.textMuted)
                                }
                            }
                        }
                        .tint(.success)

                        if editMode {
                            Stepper("", value: $item.duration, in: 1...60, step: 1).labelsHidden()
                                .tint(.success)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.surfaceElevated).cornerRadius(12)
                    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: item.isEnabled)
                }
                .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: items.map { $0.id })
            }
        }
    }
}

struct WakeGreetingCard: View {
    @State private var greeting = "Good morning, Akshith 🌅"
    @State private var showWeather = true
    @State private var showWorkout = true
    @State private var showSleepScore = true

    var body: some View {
        WakeUpSection(icon: "hand.wave.fill", title: "Wake Screen", color: Color(hex: "F59E0B")) {
            VStack(spacing: 14) {
                // Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [Color(hex: "0F172A"), Color(hex: "1E293B")], startPoint: .top, endPoint: .bottom))
                    VStack(spacing: 12) {
                        Text("6:45 AM")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(greeting)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            if showSleepScore { Label("Sleep 82", systemImage: "moon.stars.fill").foregroundColor(.steel) }
                            if showWeather   { Label("72°F", systemImage: "sun.max.fill").foregroundColor(Color(hex: "F59E0B")) }
                            if showWorkout   { Label("Upper Body", systemImage: "dumbbell.fill").foregroundColor(.ember) }
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(20)
                }
                .frame(height: 140)

                // Greeting field
                TextField("Wake greeting…", text: $greeting)
                    .font(.system(size: 14)).foregroundColor(.textPrimary).tint(Color(hex: "F59E0B"))
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color.surfaceElevated).cornerRadius(12)

                // Toggles
                VStack(spacing: 2) {
                    WakeToggle(label: "Show sleep score", value: $showSleepScore, color: .steel)
                    WakeToggle(label: "Show weather",     value: $showWeather,    color: Color(hex: "F59E0B"))
                    WakeToggle(label: "Show today's workout", value: $showWorkout, color: .ember)
                }
            }
        }
    }
}

struct WakeToggle: View {
    let label: String
    @Binding var value: Bool
    let color: Color
    var body: some View {
        Toggle(isOn: $value) {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
        }
        .tint(color)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.surfaceElevated).cornerRadius(12)
    }
}

struct WakeUpSection<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(color)
                }
                Text(title).font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
            }
            content()
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 14, y: 5)
    }
}

struct ChronotypeBadge: View {
    @EnvironmentObject var hkService: HealthKitSleepService
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: hkService.userProfile.chronotype.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.steel)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hkService.userProfile.chronotype.displayName) Chronotype")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(hkService.userProfile.chronotype.tagline)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct AdaptiveSunriseCard: View {
    let config: AdaptiveSunriseConfig
    @Binding var enabled: Bool
    @Binding var duration: Int
    @Binding var colorTemp: Double

    private var displayColor: Color {
        Color(
            red: 1.0,
            green: 0.6 + colorTemp * 0.35,
            blue: 0.3 + colorTemp * 0.7
        ).opacity(0.9)
    }

    var body: some View {
        WakeUpSection(icon: "sunrise.fill", title: "Adaptive Sunrise", color: Color(hex: "F59E0B")) {
            VStack(spacing: 16) {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gradual light increase")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                        Text(config.rationale)
                            .font(.system(size: 12)).foregroundColor(.textTertiary)
                    }
                }
                .tint(Color(hex: "F59E0B"))

                if enabled {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Duration").font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(duration) min")
                                    .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                                Stepper("", value: $duration, in: 5...60, step: 5)
                                    .labelsHidden().tint(Color(hex: "F59E0B"))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Color Temperature").font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                                Spacer()
                                Text(colorTemp < 0.3 ? "2700K Warm" : colorTemp < 0.7 ? "3500K Neutral" : "5000K Cool")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(displayColor)
                            }
                            ZStack(alignment: .bottom) {
                                LinearGradient(
                                    colors: [Color(hex: "FF8C42"), Color(hex: "FFD166"), Color(hex: "FEFAE0"), Color(hex: "C8E6FF")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                                .frame(height: 24).cornerRadius(12)
                                Slider(value: $colorTemp)
                                    .tint(.clear)
                                    .padding(.horizontal, 2)
                            }
                        }

                        HStack(spacing: 8) {
                            ForEach(Array(stride(from: 0.1, through: 1.0, by: 0.18)), id: \.self) { t in
                                Circle()
                                    .fill(Color(
                                        red: 1.0,
                                        green: 0.4 + t * 0.55,
                                        blue: 0.1 + t * 0.85
                                    ))
                                    .frame(width: 8, height: 8)
                                    .frame(maxWidth: .infinity)
                                    .opacity(0.3 + t * Double(config.intensity))
                            }
                        }
                        .frame(height: 16)
                    }
                    .padding(12).background(Color(hex: "F59E0B").opacity(0.06)).cornerRadius(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
        }
    }
}
