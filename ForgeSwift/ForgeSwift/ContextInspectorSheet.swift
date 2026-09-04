import SwiftUI
import ForgeCore

/// Long-press avatar → what ARIA used, what was redacted, which habit it's on.
/// Grounded transparency, not a debug dump.
struct ContextInspectorSheet: View {
    @ObservedObject var aria = AriaContextStore.shared
    @ObservedObject var permissions = DataPermissionsStore.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("What ARIA sees")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("Long-press friendly — what was used, what was off, and which habit ARIA is on.")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)

                    // Used signals
                    InspectorSection(title: "Used", icon: "eye.fill", color: .success) {
                        if aria.context.lifestyleTags.isEmpty && aria.context.recentPatterns.isEmpty {
                            Text("No strong signals yet — ARIA is asking, not guessing.")
                                .font(.system(size: 13)).foregroundColor(.textTertiary)
                        } else {
                            ForEach(Array(aria.context.lifestyleTags.prefix(6)), id: \.self) { tag in
                                InspectorRow(text: tag, color: .success)
                            }
                            ForEach(Array(aria.context.recentPatterns.prefix(4)), id: \.self) { pat in
                                InspectorRow(text: pat, color: .steel)
                            }
                        }
                    }

                    // Redacted (permissions)
                    if !permissions.restrictedDomains.isEmpty {
                        InspectorSection(title: "Off — redacted before reasoning", icon: "eye.slash.fill", color: .warning) {
                            ForEach(permissions.restrictedDomains, id: \.self) { domain in
                                InspectorRow(text: "\(domain) is off (permission) — never sent", color: .warning)
                            }
                            Text("Off ≠ missing. ARIA says so explicitly.")
                                .font(.system(size: 11)).foregroundColor(.textTertiary).italic()
                        }
                    }

                    // Deep habit ARIA is on
                    InspectorSection(title: "Habit ARIA is breaking", icon: "infinity", color: .ember) {
                        if let habit = aria.context.deepHabits.first {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(habit.title).font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                                Text("Cue: \(habit.cue)").font(.system(size: 12)).foregroundColor(.textSecondary)
                                Text("Routine: \(habit.routine)").font(.system(size: 12)).foregroundColor(.textSecondary)
                                Text("Cost: \(habit.cost)").font(.system(size: 12)).foregroundColor(.danger)
                                Text(habit.evidence).font(.system(size: 11, weight: .medium)).foregroundColor(.steel)
                                Text("Breaker: \(habit.breaker)").font(.system(size: 12, weight: .semibold)).foregroundColor(.ember)
                            }
                            .padding(12).background(Color.ember.opacity(0.06)).cornerRadius(10)
                        } else {
                            Text("No strong loop detected — signals look balanced.")
                                .font(.system(size: 13)).foregroundColor(.textTertiary)
                        }
                    }

                    // Relationship + constraints
                    InspectorSection(title: "How ARIA knows you", icon: "person.fill", color: .steel) {
                        InspectorRow(text: "Level \(aria.context.relationshipLevel)/10 — \(aria.context.relationshipLabel)", color: .steel)
                        if !aria.context.constraints.isEmpty {
                            ForEach(Array(aria.context.constraints.prefix(4)), id: \.self) { c in
                                InspectorRow(text: c, color: .textTertiary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String; let icon: String; let color: Color; let content: Content
    init(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.color = color; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(color)
                Text(title).font(.system(size: 12, weight: .black)).foregroundColor(color).tracking(0.6)
            }
            content
        }
        .padding(14).background(Color.surface).cornerRadius(14)
    }
}

private struct InspectorRow: View {
    let text: String; let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6).padding(.top, 6)
            Text(text).font(.system(size: 12)).foregroundColor(.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
