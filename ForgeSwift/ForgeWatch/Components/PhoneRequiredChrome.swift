import SwiftUI
import ForgeCore

// MARK: - Phone-required chrome
//
// Small, calm affordances when an action needs the paired iPhone. Standalone
// Watch work does not use these.

struct CompanionIndependenceBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "iphone.slash")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ForgePalette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(message)
    }
}

struct PhoneRequiredCaption: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(ForgePalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(message)
    }
}

extension View {
    /// Disables interaction and dims when ``allowed`` is false.
    func phoneRequired(_ allowed: Bool) -> some View {
        self
            .disabled(!allowed)
            .opacity(allowed ? 1 : 0.45)
    }
}
