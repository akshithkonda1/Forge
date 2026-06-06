import SwiftUI

// ============================================================
// MARK: - Aurora Orb State
// ============================================================

enum AROrbState: Equatable {
    case idle
    case listening
    case processing
    case speaking
}

// ============================================================
// MARK: - Aurora Orb View
// ============================================================

struct AuroraOrbView: View {
    let state:     AROrbState
    let amplitude: Float
    let size:      CGFloat
    
    @State private var rotation: Double = 0
    @State private var wavePhase: Double = 0
    @State private var particlePhase: Double = 0
    
    // Aurora color palette
    private let auroraColors: [Color] = [
        Color(hex: "00FFF0"), // Cyan
        Color(hex: "00CCFF"), // Sky Blue
        Color(hex: "0080FF"), // Deep Blue
        Color(hex: "6000FF"), // Purple
        Color(hex: "CC00FF"), // Magenta
        Color(hex: "00FFAA")  // Teal
    ]
    
    private var coreGradientColors: [Color] {
        [
            Color(hex: "00FFF0"), // Cyan
            Color(hex: "0080FF"), // Blue
            Color(hex: "6000FF"), // Purple
            Color(hex: "CC00FF"), // Magenta
            Color(hex: "FF6600"), // Orange
            Color(hex: "00FFF0")  // Back to Cyan
        ]
    }
    
    var body: some View {
        ZStack {
            // Flowing Aurora Layers (background)
            ForEach(0..<6, id: \.self) { i in
                AuroraWaveLayer(
                    phase: wavePhase + Double(i) * 0.5,
                    amplitude: Double(amplitude) * (0.3 + Double(i) * 0.15),
                    frequency: 2.0 + Double(i) * 0.3,
                    color: auroraColors[i % auroraColors.count],
                    blur: CGFloat(8 + i * 4)
                )
                .opacity(state == .idle ? 0.3 : 0.6)
            }
            
            // Prismatic Core Orb
            ZStack {
                // Rotating gradient core
                Circle()
                    .fill(
                        AngularGradient(
                            colors: coreGradientColors,
                            center: .center
                        )
                    )
                    .frame(width: size * 0.4, height: size * 0.4)
                    .blur(radius: 20)
                    .rotationEffect(.degrees(rotation))
                    .blendMode(.screen)
                
                // Additional glow layers
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(state == .speaking ? 0.3 : 0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.25
                        )
                    )
                    .frame(width: size * 0.5, height: size * 0.5)
                    .blur(radius: 12)
            }
            
            // Waveform Visualization (when listening/processing)
            if state == .listening || state == .processing {
                WaveformVisualization(
                    amplitude: amplitude,
                    barCount: 24,
                    size: size * 0.35,
                    color: auroraColors[0]
                )
            }
            
            // Ethereal Particle System
            ParticleOrbitSystem(
                phase: particlePhase,
                particleCount: 20,
                orbitRadius: size * 0.45,
                colors: auroraColors,
                isActive: state != .idle
            )
            
            // State-based accent ring
            Circle()
                .stroke(
                    stateColor.opacity(0.4),
                    lineWidth: state == .speaking ? 3 : 2
                )
                .frame(width: size, height: size)
                .scaleEffect(state == .listening ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: state == .listening)
        }
        .frame(width: size, height: size)
        .onAppear {
            // Continuous animations
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                wavePhase = .pi * 4
            }
            withAnimation(.linear(duration: 15).repeatForever(autoreverses: false)) {
                particlePhase = .pi * 2
            }
        }
    }
    
    private var stateColor: Color {
        switch state {
        case .idle:       return Color(hex: "00D2FF")
        case .listening:  return Color(hex: "00FFF0")
        case .processing: return Color(hex: "6000FF")
        case .speaking:   return Color(hex: "00FFAA")
        }
    }
}

// ============================================================
// MARK: - Aurora Wave Layer
// ============================================================

struct AuroraWaveLayer: View {
    let phase: Double
    let amplitude: Double
    let frequency: Double
    let color: Color
    let blur: CGFloat
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let animatedPhase = phase + time * 0.5
                
                var path = Path()
                let points = 100
                
                for i in 0...points {
                    let x = size.width * CGFloat(i) / CGFloat(points)
                    let normalizedX = Double(i) / Double(points)
                    let y = size.height / 2 + CGFloat(
                        amplitude * sin(normalizedX * .pi * frequency + animatedPhase)
                    )
                    
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                
                context.stroke(
                    path,
                    with: .color(color.opacity(0.6)),
                    lineWidth: 2
                )
            }
        }
        .blur(radius: blur)
        .blendMode(.screen)
    }
}

// ============================================================
// MARK: - Particle Orbit System
// ============================================================

struct ParticleOrbitSystem: View {
    let phase: Double
    let particleCount: Int
    let orbitRadius: CGFloat
    let colors: [Color]
    let isActive: Bool
    
    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { i in
                let angle = Double(i) / Double(particleCount) * .pi * 2 + phase
                let color = colors[i % colors.count]
                let radiusVariation = orbitRadius * (0.8 + 0.4 * sin(phase * 2 + Double(i)))
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                color.opacity(isActive ? 0.8 : 0.4),
                                color.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 6
                        )
                    )
                    .frame(width: 12, height: 12)
                    .offset(
                        x: cos(angle) * radiusVariation,
                        y: sin(angle) * radiusVariation
                    )
            }
        }
    }
}

// ============================================================
// MARK: - Waveform Visualization
// ============================================================

struct WaveformVisualization: View {
    let amplitude: Float
    let barCount: Int
    let size: CGFloat
    let color: Color
    
    @State private var barHeights: [CGFloat] = []
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(
                        width: size / CGFloat(barCount) - 3,
                        height: barHeights.indices.contains(i) ? barHeights[i] : 4
                    )
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            generateBarHeights()
        }
        .onChange(of: amplitude) { _, _ in
            generateBarHeights()
        }
    }
    
    private func generateBarHeights() {
        withAnimation(.easeInOut(duration: 0.15)) {
            barHeights = (0..<barCount).map { i in
                let baseHeight = CGFloat(amplitude) * size * 0.5
                let variation = sin(Double(i) / Double(barCount) * .pi * 2) * 0.3 + 0.7
                return max(4, baseHeight * CGFloat(variation))
            }
        }
    }
}

// ============================================================
// MARK: - Mesh Gradient Overlay
// ============================================================

struct MeshGradientOverlay: View {
    @State private var phase: Double = 0
    
    private let gradientColors: [Color] = [
        Color(hex: "00FFF0").opacity(0.15),
        Color(hex: "0080FF").opacity(0.12),
        Color(hex: "6000FF").opacity(0.1),
        Color(hex: "CC00FF").opacity(0.08),
        Color.clear
    ]
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // Create flowing gradient effect
                let gradient = Gradient(colors: gradientColors)
                
                for y in stride(from: 0, to: size.height, by: size.height / 5) {
                    for x in stride(from: 0, to: size.width, by: size.width / 5) {
                        let offsetX = sin(time * 0.5 + x / 100) * 30
                        let offsetY = cos(time * 0.3 + y / 100) * 30
                        
                        let rect = CGRect(
                            x: x + offsetX,
                            y: y + offsetY,
                            width: size.width / 4,
                            height: size.height / 4
                        )
                        
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .linearGradient(
                                gradient,
                                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                            )
                        )
                    }
                }
            }
        }
        .blur(radius: 40)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}
