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
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [mood.accentColor.opacity(0.22), mood.accentColor.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(
                            LinearGradient(
                                colors: [mood.accentColor.opacity(0.6), mood.accentColor.opacity(0.18)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 1.5
                        ))

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(LinearGradient(
                            colors: [mood.accentColor, mood.accentColor.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        ))
                }

                // Presence dot
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .tracking(0.3)
                    Text("your coach")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                }

                HStack(spacing: 5) {
                    if ariaService.isLocalFallback {
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

            // Readiness chip
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(scoreColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: scoreColor.opacity(0.7), radius: 4)
                    Text("\(store.readiness.overall)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                Text("ready")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.textMuted)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                ZStack {
                    Capsule().fill(Color.surfaceElevated.opacity(0.95))
                    Capsule().stroke(Color.borderHairline, lineWidth: 1)
                }
            }
            .overlay(Capsule().stroke(scoreColor.opacity(0.35), lineWidth: 1))
            .shadow(color: scoreColor.opacity(0.2), radius: 8, y: 3)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.borderColor.opacity(0.3)).frame(height: 0.5), alignment: .bottom)
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
