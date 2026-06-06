import SwiftUI

struct ForgeEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(FDS.Gradient.ember)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(FDS.Gradient.ember)
                        .cornerRadius(FDS.Radius.sm)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.surface)
        .cornerRadius(FDS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: FDS.Radius.lg)
                .stroke(Color.borderColor.opacity(0.5), lineWidth: 1)
        )
    }
}

struct ForgeSkeletonBlock: View {
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 8

    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.surfaceElevated)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(shimmer ? 0.08 : 0.02),
                                Color.white.opacity(0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    shimmer.toggle()
                }
            }
    }
}
