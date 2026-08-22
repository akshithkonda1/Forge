import SwiftUI

/// A titled block used by both the alarm editor and the sounds tab, which is
/// why it is not file-private: it was only ever private because there was one
/// file.
struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.textTertiary)
                .tracking(2.5)
            content()
        }
    }
}
