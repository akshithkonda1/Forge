import SwiftUI

/// Full-screen ARIA intro on first visit to the chat tab.
struct AriaUseOnboardingView: View {
    @EnvironmentObject var store: AppStore
    var onFinished: (String?) -> Void

    @State private var index = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pages: [AriaUseOnboardingPage] {
        AriaUseOnboarding.pages(
            name: store.userProfile.name.split(separator: " ").first.map(String.init) ?? "",
            snapshot: AriaFirstHealthBriefing.snapshot(from: store)
        )
    }

    private var page: AriaUseOnboardingPage { pages[min(index, pages.count - 1)] }
    private var isLast: Bool { page.step == .tryIt }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            ChatBackground(mood: .focused)
                .ignoresSafeArea()
                .opacity(0.55)

            VStack(spacing: 0) {
                HStack {
                    Text("ARIA")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(2.4)
                        .foregroundColor(.textTertiary)
                    Spacer()
                    Button("Skip intro") {
                        FDS.haptic(.light)
                        onFinished(nil)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)

                Spacer(minLength: 12)

                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color.ember.opacity(0.28), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 70
                        ))
                        .frame(width: 140, height: 140)
                        .blur(radius: 8)
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.ember.opacity(0.28), Color.ember.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 88, height: 88)
                        .overlay(
                            Circle().stroke(Color.ember.opacity(0.45), lineWidth: 1.5)
                        )
                    Image(systemName: page.symbol)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(FDS.Gradient.ember)
                }
                .scaleEffect(appeared ? 1 : 0.86)
                .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 14) {
                    Text(page.title)
                        .font(FDS.TypeScale.title(26))
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(page.body)
                        .font(.system(size: 16))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    if page.step == .specialists {
                        specialistRow
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 24)
                .id(page.step)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))

                Spacer(minLength: 16)

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Color.ember : Color.white.opacity(0.14))
                            .frame(width: i == index ? 22 : 7, height: 7)
                    }
                }
                .padding(.bottom, 18)

                VStack(spacing: 10) {
                    if isLast {
                        ForEach(AriaUseOnboarding.tryPrompts, id: \.self) { prompt in
                            Button {
                                FDS.haptic(.medium)
                                onFinished(prompt)
                            } label: {
                                HStack {
                                    Text(prompt)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.ember)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(Color.surfaceElevated)
                                .cornerRadius(FDS.Radius.md)
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        Button("I’ll look around first") {
                            FDS.haptic(.light)
                            onFinished(nil)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .padding(.top, 4)
                    } else {
                        Button {
                            FDS.haptic(.medium)
                            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : FDS.Spring.page) {
                                index = min(index + 1, pages.count - 1)
                            }
                        } label: {
                            Text("Next")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(FDS.Gradient.ember)
                                .cornerRadius(FDS.Radius.lg)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .onAppear { appeared = true }
    }

    private var specialistRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AriaCoachAgent.allCases) { agent in
                    VStack(spacing: 6) {
                        Image(systemName: agent.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(agent.accent)
                        Text(agent.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    }
                    .frame(width: 68, height: 62)
                    .background(agent.accent.opacity(0.12))
                    .cornerRadius(14)
                }
            }
        }
    }
}
