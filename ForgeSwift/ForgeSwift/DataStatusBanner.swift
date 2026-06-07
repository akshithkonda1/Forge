import SwiftUI

struct DataStatusBanner: View {
    let state: DataLoadState
    var onRetry: (() -> Void)?

    var body: some View {
        switch state {
        case .idle, .loaded:
            EmptyView()
        case .loading:
            banner(
                icon: "arrow.triangle.2.circlepath",
                title: "Syncing your data",
                tint: .steel
            )
        case .offlineFallback:
            #if DEBUG
            banner(
                icon: "wifi.slash",
                title: "Can't reach \(APIConfig.displayHost) — showing sample data. Run `npm run backend:dev`.",
                tint: .warning,
                actionTitle: "Retry",
                action: onRetry
            )
            #else
            banner(
                icon: "wifi.slash",
                title: "Can't reach the Forge API. Check your connection and try again.",
                tint: .warning,
                actionTitle: "Retry",
                action: onRetry
            )
            #endif
        case .error(let message):
            banner(
                icon: "exclamationmark.triangle.fill",
                title: message,
                tint: .danger,
                actionTitle: "Retry",
                action: onRetry
            )
        }
    }

    @ViewBuilder
    private func banner(
        icon: String,
        title: String,
        tint: Color,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.ember)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.surface.opacity(0.96))
        .overlay(
            Rectangle()
                .fill(tint.opacity(0.35))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}