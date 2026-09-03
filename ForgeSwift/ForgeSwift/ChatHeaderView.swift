import SwiftUI

struct ChatHeaderView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var ariaService = AriaService.shared
    let mood:              ARIAMood
    var onAvatarLongPress: (() -> Void)? = nil
    @State private var pulse        = false
    @State private var appeared     = false

    private var scoreColor: Color {
        switch store.readiness.overall {
        case 85...:  return Color(hex: "22C55E")
        case 70..<85: return Color.ember
        case 50..<70: return Color.steel
        default:      return Color(hex: "EF4444")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ARIAIdentityMark(state: .idle, mood: mood, size: 44, amplitude: 0.2)

                // Presence pulse around the live orb
                ZStack {
                    Circle().fill(Color(hex: "080808")).frame(width: 14, height: 14)
                    Circle().fill(Color(hex: "22C55E")).frame(width: 9, height: 9)
                        .shadow(color: Color(hex: "22C55E").opacity(0.7), radius: 3)
                    Circle().fill(Color(hex: "22C55E").opacity(0.4))
                        .frame(width: 9, height: 9)
                        .scaleEffect(pulse ? 2.0 : 1.0)
                        .opacity(pulse ? 0 : 0.7)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
                }
                .offset(x: 3, y: 3)
            }
            .onAppear { pulse = true }
            .onLongPressGesture(minimumDuration: 0.45) {
                choreographedHaptic(.reactionAdded)
                onAvatarLongPress?()
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("ARIA")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .tracking(0.8)
                    if store.lastCoachWorkers.count > 1 {
                        Text("· " + store.lastCoachWorkers.map(\.kind.label).joined(separator: " + "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(store.lastRoutedCoachAgent.accent)
                            .lineLimit(1)
                    } else if store.lastRoutedCoachAgent != .aria {
                        Text("· \(store.lastRoutedCoachAgent.label)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(store.lastRoutedCoachAgent.accent)
                    } else {
                        Text("your coaches")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textTertiary)
                    }
                }

                HStack(spacing: 5) {
                    if ariaService.isTestReady {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.steel)
                        Text("On this phone · reading your month")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.steel.opacity(0.9))
                    } else if ariaService.isLocalFallback {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.ember)
                        Text("On this phone")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.ember.opacity(0.8))
                    } else {
                        Circle().fill(Color(hex: "22C55E")).frame(width: 5, height: 5)
                        Text(headerStatusLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                }
                .animation(FDS.Spring.standard, value: ariaService.isLocalFallback)
            }

            Spacer()

            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: CGFloat(store.readiness.overall) / 100.0)
                        .stroke(
                            AngularGradient(
                                colors: [scoreColor, scoreColor.opacity(0.3)],
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 38, height: 38)
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        .frame(width: 38, height: 38)
                    Text("\(store.readiness.overall)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                .shadow(color: scoreColor.opacity(0.3), radius: 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.background.opacity(0.3))
                LinearGradient(
                    colors: [mood.accentColor.opacity(0.04), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .overlay(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [mood.accentColor.opacity(0.2), Color.white.opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5),
            alignment: .bottom
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -10)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true } }
    }

    private var headerStatusLine: String {
        let first = store.userProfile.name.components(separatedBy: " ").first ?? ""
        let score = store.readiness.overall
        if first.isEmpty {
            return score < 55 ? "Easy day — I’m here" : "Ready when you are"
        }
        if score < 55 { return "\(first), let’s keep it easy" }
        if score >= 85 { return "You look ready, \(first)" }
        return "Here for you, \(first)"
    }
}
