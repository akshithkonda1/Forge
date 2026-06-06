# Aurora Orb - Quick Customization Guide

## 🎨 Common Customizations

### Change Color Palette

**Make it warmer (sunset theme):**
```swift
func auroraColor(for layer: Int) -> Color {
    let colors: [Color] = [
        Color(hex: "FF6B00"), // Orange
        Color(hex: "FF0080"), // Hot pink
        Color(hex: "FF00FF"), // Magenta
        Color(hex: "8000FF"), // Purple
        Color(hex: "FF4D00"), // Ember
        Color(hex: "FFB800")  // Gold
    ]
    return colors[layer % colors.count]
}
```

**Make it cooler (ice theme):**
```swift
func auroraColor(for layer: Int) -> Color {
    let colors: [Color] = [
        Color(hex: "00FFFF"), // Aqua
        Color(hex: "00CCFF"), // Light blue
        Color(hex: "0099FF"), // Sky blue
        Color(hex: "CCF5FF"), // Ice blue
        Color(hex: "E0FFFF"), // Pale cyan
        Color(hex: "B3E5FC")  // Powder blue
    ]
    return colors[layer % colors.count]
}
```

**Make it match Forge brand (ember theme):**
```swift
func auroraColor(for layer: Int) -> Color {
    let colors: [Color] = [
        Color.ember,           // #FF4D00
        Color.emberLight,      // #FF6B2B
        Color(hex: "FF8800"), // Orange
        Color(hex: "FFA500"), // Amber
        Color.steel,          // #3B82F6
        Color.steelLight      // #60A5FA
    ]
    return colors[layer % colors.count]
}
```

---

### Adjust Animation Speed

**Make it slower (more calming):**
```swift
.onAppear {
    withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
        animationPhase = .pi * 2
    }
    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
        wavePhase = .pi * 2
    }
    withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
        particlePhase = .pi * 2
    }
    withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
        auroraFlow = .pi * 2
    }
}
```

**Make it faster (more energetic):**
```swift
.onAppear {
    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
        animationPhase = .pi * 2
    }
    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
        wavePhase = .pi * 2
    }
    withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
        particlePhase = .pi * 2
    }
    withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
        auroraFlow = .pi * 2
    }
}
```

---

### Reduce Complexity (Better Performance)

**Minimal version (50% fewer elements):**
```swift
// Reduce aurora layers from 6 to 3
ForEach(0..<3) { layer in
    AuroraWaveLayer(...)
}

// Reduce particles from 20 to 10
ForEach(0..<10) { index in
    Circle()...
}

// Reduce waveform bars from 24 to 16
HStack(spacing: 5) {
    ForEach(0..<16) { index in
        RoundedRectangle(...)
    }
}

// Reduce light rays from 8 to 4
ForEach(0..<4) { ray in
    Rectangle()...
}

// Reduce stars from 50 to 25
ForEach(0..<25) { index in
    Circle()...
}
```

**Ultra-minimal (25% of original):**
```swift
// 1 aurora layer
// 5 particles
// 12 waveform bars
// 0 light rays
// 15 stars
```

---

### Change Orb Size

**Larger orb (for iPad or emphasis):**
```swift
// Find all .frame(width: 240, height: 240)
// Change to:
.frame(width: 320, height: 320)

// Adjust waveform accordingly:
.frame(width: 240, height: 130)

// Adjust particles orbit:
x: 160 * cos(...) // was 120
y: 160 * sin(...)
```

**Smaller orb (for compact spaces):**
```swift
.frame(width: 180, height: 180)
.frame(width: 120, height: 70) // waveform
x: 90 * cos(...) // particles
y: 90 * sin(...)
```

---

### Add Sound Reactivity

**Connect to real audio input:**
```swift
import AVFoundation

class AudioLevelMonitor: ObservableObject {
    @Published var levels: [Float] = Array(repeating: 0.0, count: 24)
    private var audioRecorder: AVAudioRecorder?
    
    func startMonitoring() {
        // Set up AVAudioRecorder
        // Update levels array with real audio FFT data
    }
}

// In view:
@StateObject var audioMonitor = AudioLevelMonitor()

// Replace waveformHeight calculation:
func waveformHeight(for index: Int) -> CGFloat {
    let audioLevel = CGFloat(audioMonitor.levels[index])
    return 8 + audioLevel * 70 // Scale to visual range
}
```

---

### Accessibility Mode

**Reduced motion version:**
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

var body: some View {
    if reduceMotion {
        // Simple static orb
        Circle()
            .fill(Color.cyan.opacity(0.3))
            .frame(width: 240, height: 240)
            // ... minimal styling
    } else {
        // Full aurora animation
        ZStack {
            // ... existing code
        }
    }
}
```

**High contrast version:**
```swift
@Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor

func auroraColor(for layer: Int) -> Color {
    if differentiateWithoutColor {
        // Use brightness instead of hue
        return Color.white.opacity(0.8 - Double(layer) * 0.12)
    } else {
        // Normal colors
        // ...
    }
}
```

---

### State-Based Colors

**Different colors for different states:**
```swift
enum VoiceState {
    case listening
    case thinking
    case speaking
    case error
}

@Binding var state: VoiceState

func auroraColor(for layer: Int) -> Color {
    switch state {
    case .listening:
        // Cool blues and cyans
        return [Color.cyan, Color.blue, ...][layer]
    case .thinking:
        // Warm purples and magentas
        return [Color.purple, Color(hex: "CC00FF"), ...][layer]
    case .speaking:
        // Vibrant oranges and pinks
        return [Color.ember, Color(hex: "FF0080"), ...][layer]
    case .error:
        // Red and orange warnings
        return [Color.danger, Color.warning, ...][layer]
    }
}
```

---

### Add Haptics

**Subtle feedback for immersion:**
```swift
.onAppear {
    // Gentle tap when orb appears
    let impact = UIImpactFeedbackGenerator(style: .soft)
    impact.impactOccurred()
    
    // Continuous subtle pulses
    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred(intensity: 0.3)
    }
}
```

---

### Custom Waveform Styles

**Circular waveform (like Siri):**
```swift
// Replace HStack of bars with:
ForEach(0..<24) { index in
    RoundedRectangle(cornerRadius: 3)
        .fill(waveformColor(for: index))
        .frame(width: 3, height: waveformHeight(for: index))
        .offset(y: 60) // Radius
        .rotationEffect(.degrees(Double(index) * 15)) // 360/24
}
```

**Wave pattern:**
```swift
Path { path in
    let points = (0..<100).map { i -> CGPoint in
        let x = CGFloat(i) * 2
        let y = 40 + sin(wavePhase + Double(i) * 0.1) * 30
        return CGPoint(x: x, y: y)
    }
    
    path.move(to: points[0])
    points.forEach { path.addLine(to: $0) }
}
.stroke(Color.white, lineWidth: 2)
```

---

## 🎛️ Parameter Reference

### Aurora Wave Layer
```swift
AuroraWaveLayer(
    phase: 0.0...∞,        // Animation offset (radians)
    color: Color,          // Layer color
    amplitude: 10...100,   // Wave height (points)
    frequency: 1.0...5.0,  // Wave density
    offset: -50...50       // Vertical position (points)
)
```

**Recommended ranges:**
- `amplitude`: 20-50 for subtle, 50-100 for dramatic
- `frequency`: 1.5-3.0 for natural looking waves
- `offset`: Space layers 10-20 points apart

### Particle System
```swift
ForEach(0..<count) { index in
    Circle()
        .fill(gradient)
        .frame(width: 4...12)  // Particle size
        .offset(
            x: radius * cos(angle),  // radius: 80-150
            y: radius * sin(angle)
        )
        .blur(radius: 2...5)
        .opacity(0.2...0.8)
}
```

**Recommended values:**
- Particle count: 10-30
- Orbit radius: 100-140
- Size range: 4-12
- Blur: 3-4 for soft glow

### Waveform Bars
```swift
.frame(width: 3...6)        // Bar width
.frame(height: 8...80)      // Min/max height
.spacing: 4...8             // Gap between bars
.cornerRadius: 2...4        // Rounded ends
```

**Recommended:**
- Width: 3-4 (crisp), 5-6 (bold)
- Height range: 60-70 points swing
- Spacing: Match ~50% of width
- Corner: Match ~50% of width

---

## 🔧 Troubleshooting

### Orb looks choppy on older devices
**Solution:** Reduce element counts and blur radius
```swift
// Instead of 6 layers:
ForEach(0..<3) { layer in ...}

// Instead of blur(radius: 15):
.blur(radius: 8)
```

### Colors don't blend nicely
**Solution:** Use `.blendMode(.screen)` for light colors
```swift
Circle()
    .fill(color)
    .blendMode(.screen)  // Only for bright colors!
```

### Animation feels stutter-y
**Solution:** Use `.linear` curves for continuous rotations
```swift
// Good for endless rotation:
.linear(duration: 8).repeatForever(autoreverses: false)

// Good for pulsing:
.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
```

### Too much GPU usage
**Solution:** Reduce blur operations
```swift
// Combine blur operations:
ZStack {
    layer1
    layer2
    layer3
}
.blur(radius: 10)  // Single blur instead of 3

// Or remove blur from less important layers
```

### Particles look scattered
**Solution:** Adjust orbit calculation
```swift
// Circular orbit:
x: radius * cos(angle)
y: radius * sin(angle)

// Elliptical orbit:
x: radiusX * cos(angle)
y: radiusY * sin(angle)

// Ensure angle cycles through 0 to 2π
```

---

## 📱 Device-Specific Optimizations

### iPhone SE / older devices
```swift
if UIDevice.current.userInterfaceIdiom == .phone {
    // Reduce complexity by 50%
}
```

### iPad
```swift
if UIDevice.current.userInterfaceIdiom == .pad {
    // Increase orb size by 25%
    // Add more particles for larger screen
}
```

### ProMotion displays (120Hz)
```swift
if UIScreen.main.maximumFramesPerSecond == 120 {
    // Smoother animation curves
    .easeInOut(duration: 0.8) // was 1.5
}
```

---

## 💾 Save Custom Styles

```swift
struct AuroraConfig: Codable {
    var colorPalette: [String] // Hex codes
    var particleCount: Int
    var layerCount: Int
    var animationSpeed: Double
    var orbSize: CGFloat
    var showStars: Bool
    var showRays: Bool
}

// Save/load from UserDefaults
```

---

## 🎉 Have Fun!

The Aurora Orb is designed to be **customizable**. Don't be afraid to:
- 🎨 Try wild color combinations
- ⚡ Experiment with animation speeds
- 🔬 Add your own effects
- 🎭 Create themes for different moods
- 🎪 Make it uniquely yours

The math and structure are solid—now make it **beautiful** in your own way!

---

*"There are no rules in creating wonder."* ✨
