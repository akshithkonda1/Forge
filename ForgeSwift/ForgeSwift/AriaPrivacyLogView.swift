import SwiftUI
import ForgeCore

/// Plain log of what left this phone today. Computed facts only.
struct AriaPrivacyLogView: View {
    @State private var events: [AriaDeviceEgress.Event] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            ForgeScreenStack(top: FDS.Spacing.sm) {
                Text("Health data, patterns, and memory stay on this phone. Models get bands and change flags, never samples. Forge does not sell health data or run ads on it.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()

                if events.isEmpty {
                    ForgeEmptyState(
                        icon: "lock.shield",
                        title: "Nothing left this phone today",
                        message: "Chat facts, server voice, and account calls show up here when they happen."
                    )
                } else {
                    VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                                Text(event.kind.label)
                                    .font(HomeType.micro)
                                    .foregroundStyle(Color.textTertiary)
                                Text(event.summary)
                                    .font(HomeType.body)
                                    .foregroundStyle(Color.textPrimary)
                                    .forgeWrapping()
                                if !event.factKeys.isEmpty {
                                    Text(event.factKeys.joined(separator: " · "))
                                        .font(HomeType.micro)
                                        .foregroundStyle(Color.textTertiary)
                                        .forgeWrapping()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, ForgeLayout.pairGap)
                        }
                    }
                    .forgeContentCard()
                }
            }
        }
        .forgeScreenBackground(accent: .steel)
        .navigationTitle("What left your phone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .foregroundColor(.ember)
            }
        }
        .onAppear {
            events = AriaDeviceEgress.today(AriaDeviceEgress.load())
        }
    }
}
