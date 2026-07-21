import SwiftUI
import AuthenticationServices

// MARK: - Auth Welcome (first gate after splash)

/// Auth-first landing: Sign up → Onboarding, or Sign in (Apple / Google / Email).
struct AuthWelcomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var appeared = false
    @State private var showSignIn = false
    @State private var ringPulse = false

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            RadialGradient(
                colors: [Color.ember.opacity(0.18), Color.steel.opacity(0.06), .clear],
                center: UnitPoint(x: 0.5, y: 0.22),
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                ZStack {
                    Circle()
                        .stroke(Color.ember.opacity(0.2), lineWidth: 1)
                        .frame(width: ringPulse ? 148 : 120, height: ringPulse ? 148 : 120)
                        .opacity(ringPulse ? 0 : 0.85)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.ember.opacity(0.4), Color.ember.opacity(0.08), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 90
                            )
                        )
                        .frame(width: 180, height: 180)
                        .blur(radius: 18)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(FDS.Gradient.ember)
                        .shadow(color: Color.ember.opacity(0.7), radius: 16, y: 6)
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.85)

                Text("FORGE")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.top, 20)
                    .opacity(appeared ? 1 : 0)

                Text("Train smarter with ARIA")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .padding(.top, 10)
                    .opacity(appeared ? 1 : 0)

                Text("Readiness · lifestyle · cycle-aware coaching")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
                    .padding(.top, 6)
                    .opacity(appeared ? 1 : 0)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        FDS.haptic(.medium)
                        store.beginSignUp()
                    } label: {
                        Text("Create account")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(FDS.Gradient.ember)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.ember.opacity(0.45), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        FDS.haptic(.light)
                        showSignIn = true
                    } label: {
                        Text("Sign in")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.borderColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Text("By continuing you agree to lifestyle coaching terms — not medical advice.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
            }
        }
        .sheet(isPresented: $showSignIn) {
            AuthSignInView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.05)) { appeared = true }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                ringPulse = true
            }
        }
    }
}
